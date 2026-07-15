--!strict
-- Server sim driver: seeds muscle attributes, powers joints once the spawn settles,
-- lands debug-slider writes on the simulation timeline, guards against explosions.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MuscleSystem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MuscleSystem"))
local Locomotion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locomotion"))
local PelvisDrive = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PelvisDrive"))
local GetupPose = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GetupPose"))
local PoseDriver = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PoseDriver"))

-- body parts must never appear in the root's FloorSensor ray (see MuscleSystem.setupBody)
pcall(function()
	PhysicsService:RegisterCollisionGroup("CharBody")
end)
pcall(function()
	PhysicsService:RegisterCollisionGroup("CharRoot")
end)
PhysicsService:CollisionGroupSetCollidable("CharBody", "CharRoot", false)

local CONFIG = {
	POWER_ON_DELAY_STEPS = 60, -- spawn flow can stomp joint properties; let it finish
	RESET_RELOCK_STEPS = 45, -- kinematic relock window after a guard reset
	RESET_HEIGHT = 6,
	RESET_STILL_SPEED = 5, -- don't re-power until every part is at least this still
	VOID_Y = -50, -- below the room = lost; reset instead of falling forever
	-- tone slews instead of stepping: snapping full muscle onto a displaced body is a
	-- slingshot (verified live — 539 stud/s off a 2.7-stud Root stretch)
	MT_RAMP_PER_SECOND = 1.5,
}

local remote = Instance.new("RemoteEvent")
remote.Name = "MuscleDebug"
remote.Parent = ReplicatedStorage

type CharState = {
	character: Model,
	settle: number,
	resetLock: number,
	spawnCFrame: CFrame,
	mtTarget: number,
	userMt: number, -- what the player/panel asked for; falls override it temporarily
	fallTimer: number, -- > 0 while limp from a fall
	fallArmed: boolean, -- re-arms only after standing again, else lying re-triggers forever
	upHold: number, -- continuous seconds spent upright
	downHold: number, -- continuous seconds spent DOWN outside the fall cycle (stranded)
	torsoHold: number, -- continuous seconds the torso has left the pose (trip detector)
	riseTimer: number, -- watchdog: a rise that never reaches upright retries the fall cycle
	riseElapsed: number, -- getup clip clock, mirrored to the GT attribute
	riseFails: number, -- consecutive failed physical get-ups (3 = loud last-resort assist)
	setupDone: boolean,
	sprint: boolean, -- client intent via remote; custom InputActions don't sync (see Locomotion)
}
local charStates: { [Player]: CharState } = {}
local pending: { { player: Player, key: string, value: number } } = {}

-- a remote is untrusted input, SA or not: whitelist and clamp before it nears the sim.
-- Values are queued and applied inside the sim step so attributes stay on the shared
-- timeline (the official SA custom-state pattern).
remote.OnServerEvent:Connect(function(player, key: unknown, value: unknown)
	if type(key) ~= "string" or type(value) ~= "number" or value ~= value then
		return
	end
	if key == Locomotion.CONFIG.REMOTE_KEY or key == PelvisDrive.CONFIG.REMOTE_KEY then
		table.insert(pending, { player = player, key = key, value = if value == 1 then 1 else 0 })
		return
	end
	if not MuscleSystem.isValidAttr(key) then
		return
	end
	table.insert(pending, { player = player, key = key, value = MuscleSystem.clampAttr(key, value) })
end)

local function onCharacter(player: Player, character: Model)
	charStates[player] = {
		character = character,
		settle = CONFIG.POWER_ON_DELAY_STEPS,
		resetLock = 0,
		spawnCFrame = character:GetPivot(),
		mtTarget = 1,
		userMt = 1,
		fallTimer = 0,
		fallArmed = true,
		upHold = 0,
		downHold = 0,
		torsoHold = 0,
		riseTimer = 0,
		riseElapsed = 0,
		riseFails = 0,
		setupDone = false,
		sprint = false,
	}
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
-- players who joined before this script ran (guaranteed in Studio solo tests)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	charStates[player] = nil
end)

local function simStep(_dt: number)
	for _, w in pending do
		local st = charStates[w.player]
		if st and st.character.Parent then
			if w.key == Locomotion.CONFIG.REMOTE_KEY then
				st.sprint = w.value == 1
			elseif w.key == PelvisDrive.CONFIG.REMOTE_KEY then
				st.character:SetAttribute(PelvisDrive.CONFIG.MODE_ATTR, w.value == 1)
			elseif w.key == MuscleSystem.CONFIG.MASTER_TONE_ATTR then
				st.userMt = w.value -- slewed below, never stepped
			else
				MuscleSystem.applyDebugWrite(st.character, w.key, w.value)
			end
		end
	end
	table.clear(pending)

	for player, st in charStates do
		local character = st.character
		if not character.Parent then
			continue
		end
		local joints = MuscleSystem.getJoints(character)
		if not joints then
			continue
		end

		MuscleSystem.ensureDefaults(character)

		if not st.setupDone then
			st.setupDone = MuscleSystem.setupBody(character)
		end

		if st.settle > 0 then
			st.settle -= 1
			if st.settle == 0 then
				character:SetAttribute(MuscleSystem.CONFIG.POWERED_ATTR, true)
			end
		end
		if st.resetLock > 0 then
			st.resetLock -= 1
			if st.resetLock == 0 then
				local still = true
				for _, part in character:GetChildren() do
					if part:IsA("BasePart") and part.AssemblyLinearVelocity.Magnitude > CONFIG.RESET_STILL_SPEED then
						still = false
						break
					end
				end
				if still then
					character:SetAttribute(MuscleSystem.CONFIG.POWERED_ATTR, true)
				else
					-- still tumbling: re-pin to spawn and wait another window
					for _, part in character:GetChildren() do
						if part:IsA("BasePart") then
							part.AssemblyLinearVelocity = Vector3.zero
							part.AssemblyAngularVelocity = Vector3.zero
						end
					end
					character:PivotTo(st.spawnCFrame + Vector3.new(0, CONFIG.RESET_HEIGHT, 0))
					st.resetLock = CONFIG.RESET_RELOCK_STEPS
				end
			end
		end

		-- fall reflex: a body that is going down goes LIMP (this is the ragdoll fall);
		-- tone restores after downTime, and restoring tone is also what lifts him back
		local FALL = MuscleSystem.CONFIG.FALL
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- pelvis-driven is THE architecture since the Gate 2 pivot; the panel
		-- toggle flips back to the legacy capsule for A/B only
		if character:GetAttribute(PelvisDrive.CONFIG.MODE_ATTR) == nil then
			character:SetAttribute(PelvisDrive.CONFIG.MODE_ATTR, true)
		end
		-- pelvis mode: the capsule is a dangling ghost — the PELVIS is the
		-- posture truth for every fall/rise decision
		local pelvisMode = character:GetAttribute(PelvisDrive.CONFIG.MODE_ATTR) == true
		local upPart: BasePart? = if pelvisMode
			then (character:FindFirstChild("LowerTorso") :: BasePart?) or hrp
			else hrp
		local upY = if upPart then upPart.CFrame.UpVector.Y else 1
		local dtStep = if type(_dt) == "number" then _dt else 1 / 60
		if st.fallTimer > 0 then
			st.fallTimer -= dtStep
			st.upHold = 0
			st.downHold = 0
			st.torsoHold = 0
			if st.fallTimer <= 0 then
				-- GETUP (Phase 3): NO teleport — the pose clip + tone ramp +
				-- boosted pelvis springs push the body up from wherever and
				-- however it actually lies. Face-up/down is latched by the
				-- PoseDriver on state entry.
				character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, true)
				character:SetAttribute(GetupPose.CONFIG.TIME_ATTR, 0)
				st.riseTimer = FALL.riseTimeout
				st.riseElapsed = 0
			end
		else
			st.upHold = if upY > FALL.riseUp then st.upHold + dtStep else 0
			if st.upHold >= FALL.riseHold and not st.fallArmed then
				st.fallArmed = true
				st.riseFails = 0
				character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, false)
			end
			-- rise watchdog. A rise that TOPPLES has failed NOW — waiting out the
			-- clock leaves a downed body pinned to a fully powered, walkable
			-- capsule for seconds (the marionette window, caught in telemetry:
			-- 0.9 s at up=0.00 with StandForce 10000). On expiry, posture decides:
			-- an upright body just needs more time for upHold to clear Rising (a
			-- blind retry knocked down SUCCESSFUL stands, verified live); a body
			-- still down genuinely failed and retries the down-and-right cycle.
			if character:GetAttribute(MuscleSystem.CONFIG.RISING_ATTR) == true then
				st.riseTimer -= dtStep
				st.riseElapsed += dtStep
				character:SetAttribute(GetupPose.CONFIG.TIME_ATTR, st.riseElapsed)
				-- fast-fail only once the clip has had its runtime — early in
				-- the clip the body is SUPPOSED to be low and tilted (tucking)
				local clipDone = st.riseElapsed >= GetupPose.CONFIG.CLIP_TIME * 0.85
				if st.riseTimer <= 0 or (clipDone and upY < FALL.tiltUp) then
					if upY > FALL.riseUp then
						st.riseTimer = 0.5
					else
						st.riseFails += 1
						local riseCap = tonumber(character:GetAttribute(MuscleSystem.CONFIG.RISE_CAP_ATTR)) or 1
						if st.riseFails >= 3 and riseCap > 0.8 then
							-- the PHYSICAL get-up failed three straight times at
							-- full allowed tone: last-resort assist, loudly — if
							-- this fires in normal play, fix the clip/gains
							warn("[MuscleServer] physical get-up failed x3 — assist pivot for " .. player.Name)
							MuscleSystem.getUpAssist(character)
							st.riseFails = 0
							st.riseTimer = FALL.riseTimeout
							st.riseElapsed = 0
							character:SetAttribute(GetupPose.CONFIG.TIME_ATTR, 0)
						else
							-- health/RC-capped failures buckle back down and
							-- retry — that IS the intended read (Gate 3 item 3)
							character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, false)
							st.fallTimer = FALL.retryDown
							-- a failed rise carries hover+spring momentum; cutting
							-- tone releases it ballistically (probe: pelvis flung to
							-- standing height, INVERTED, between attempts — read as
							-- "hit again"). Bleed it at the transition — EVERY part:
							-- under AJU each body part is its own assembly, and a
							-- pelvis-only bleed let the other 14 yank it right back
							-- up (verified: still tossed to pY 2.9 inverted).
							for _, part in character:GetChildren() do
								if part:IsA("BasePart") then
									local pv = part.AssemblyLinearVelocity
									part.AssemblyLinearVelocity = Vector3.new(pv.X * 0.3, math.min(pv.Y, 0), pv.Z * 0.3)
									part.AssemblyAngularVelocity *= 0.3
								end
							end
						end
					end
				end
			end
			-- three ways down: an ARMED tilt (the normal trip), a knockdown dip
			-- (the reflex is upright-gated and rise-deaf, so it cannot loop on
			-- a lying body — safe WITHOUT arming; wall hits during the disarm
			-- window were silently ignored, user-reported), and the stranded
			-- catch-all (down > strandedDown at full power = the frozen pin
			-- the recorder caught — force the cycle, whatever the state)
			local knockedDown = MuscleSystem.impactFactor(character) < MuscleSystem.CONFIG.IMPACT.knockdownFactor
			-- committed topple: tilted AND rotating over fast — release NOW
			-- instead of letting balance fight the fall to the 49° line
			local wv = if hrp then hrp.AssemblyAngularVelocity else Vector3.zero
			local toppling = upY < FALL.tipUp and Vector3.new(wv.X, 0, wv.Z).Magnitude > FALL.tipRate
			-- trip detector: the capsule is orientation-locked by balance and
			-- NEVER tips in a trip — the BODY folds over the obstacle while
			-- the hips hang from a gyroscope. Torso divergence is the truth.
			-- contact-gated: a trip means the body FOLDED OVER SOMETHING —
			-- sprint strafes whip the torso hard with nothing nearby
			-- (rel ~70 measured) and must never read as trips
			local torso = character:FindFirstChild("UpperTorso") :: BasePart?
			local torsoUp = if torso then torso.CFrame.UpVector.Y else 1
			st.torsoHold = if torsoUp < FALL.torsoDiverge and MuscleSystem.recentContact(character)
				then st.torsoHold + dtStep
				else 0
			st.downHold = if upY < FALL.tiltUp and character:GetAttribute(MuscleSystem.CONFIG.RISING_ATTR) ~= true
				then st.downHold + dtStep
				else 0
			if
				(
					(st.fallArmed and (upY < FALL.tiltUp or toppling or st.torsoHold >= FALL.torsoTime))
					or knockedDown
					or st.downHold >= FALL.strandedDown
				)
				and st.settle == 0
				and st.resetLock == 0
				and character:GetAttribute(MuscleSystem.CONFIG.POWERED_ATTR) == true
			then
				st.fallArmed = false
				st.downHold = 0
				st.torsoHold = 0
				st.fallTimer = FALL.downTime
				-- the hips must FALL WITH the body, not from hover-zero: the
				-- capsule's vertical velocity starts at ~0 while the body is
				-- already going down, and that one-gravity-lag reads as an
				-- onset pin. Hand it the pelvis's downward velocity.
				local pelvis = character:FindFirstChild("LowerTorso") :: BasePart?
				if hrp and pelvis then
					local hv = hrp.AssemblyLinearVelocity
					hrp.AssemblyLinearVelocity = Vector3.new(hv.X, math.min(pelvis.AssemblyLinearVelocity.Y, 0), hv.Z)
				end
			end
		end
		-- RC is a GLOBAL tone ceiling (health drives it in Phase 4; the slider
		-- drives it for the Gate 3 buckle test). Capping only the ramp let a
		-- lucky rise finish at full tone (verified: RC 0.4 stood, maxMT 1.0).
		local riseCap = tonumber(character:GetAttribute(MuscleSystem.CONFIG.RISE_CAP_ATTR)) or 1
		st.mtTarget = if st.fallTimer > 0
			then math.min(st.userMt, FALL.tone)
			else math.min(st.userMt, riseCap)

		-- master tone: DOWN is instant (muscles switching off can't slingshot —
		-- user felt the 0.6 s slew as knockdown lag), UP slews (snapping tone onto
		-- a displaced body slingshots it, 539 stud/s measured — the original law).
		-- While Rising the up-ramp is fast: the capsule was just righted with
		-- velocities zeroed, and at 1.5/s the limp body pulls it back down first.
		local mtNow = tonumber(character:GetAttribute(MuscleSystem.CONFIG.MASTER_TONE_ATTR)) or 1
		if st.mtTarget < mtNow then
			character:SetAttribute(MuscleSystem.CONFIG.MASTER_TONE_ATTR, st.mtTarget)
		elseif mtNow ~= st.mtTarget then
			local rate = if character:GetAttribute(MuscleSystem.CONFIG.RISING_ATTR) == true
				then FALL.riseRamp
				else CONFIG.MT_RAMP_PER_SECOND
			local stepSize = rate * (if type(_dt) == "number" then _dt else 1 / 60)
			local newMt = mtNow + math.clamp(st.mtTarget - mtNow, -stepSize, stepSize)
			character:SetAttribute(MuscleSystem.CONFIG.MASTER_TONE_ATTR, newMt)
		end

		local offender, peakRel = MuscleSystem.scanBody(character)
		MuscleSystem.noteImpact(character, peakRel, if type(_dt) == "number" then _dt else 1 / 60)
		if not offender and hrp and hrp.Position.Y < CONFIG.VOID_Y then
			offender = "below void plane"
		end
		if st.settle == 0 and st.resetLock == 0 then
			if offender then
				warn("[MuscleServer] stability guard: " .. offender .. " — resetting " .. player.Name)
				character:SetAttribute(MuscleSystem.CONFIG.POWERED_ATTR, false)
				-- a guard reset mid-fall must not leave the capsule released;
				-- the per-step enforcement below restores it from this state.
				-- MUST re-arm the trigger: a reset that landed badly with the
				-- trigger disarmed was the door into the frozen pin (a body
				-- lying at full tone forever, caught by the fall recorder)
				st.fallTimer = 0
				st.fallArmed = true
				st.downHold = 0
				character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, false)
				for _, part in character:GetChildren() do
					if part:IsA("BasePart") then
						part.AssemblyLinearVelocity = Vector3.zero
						part.AssemblyAngularVelocity = Vector3.zero
					end
				end
				character:PivotTo(st.spawnCFrame + Vector3.new(0, CONFIG.RESET_HEIGHT, 0))
				st.resetLock = CONFIG.RESET_RELOCK_STEPS
			end
		end

		-- enforced every step so no transition or ability stomp can strand a limp
		-- body on a live capsule; the get-up keeps hover but not walking.
		-- Pelvis mode keeps the capsule permanently released (input conduit
		-- only) and drives the body directly.
		local rising = character:GetAttribute(MuscleSystem.CONFIG.RISING_ATTR) == true
		MuscleSystem.setCapsuleReleased(
			character,
			pelvisMode or st.fallTimer > 0,
			pelvisMode or st.fallTimer > 0 or rising
		)
		if pelvisMode then
			PelvisDrive.step(character, dtStep)
		else
			PelvisDrive.idle(character)
		end

		-- the four-state machine (Phase 3), mirrored for both peers: drives the
		-- leg dip (step), the flail (PoseDriver), the getup clip, and the
		-- pelvis springs (PelvisDrive)
		local fs = if st.fallTimer > 0
			then "down"
			elseif rising then "getup"
			elseif MuscleSystem.impactFactor(character) < 1 then "stumble"
			else "upright"
		if character:GetAttribute(MuscleSystem.CONFIG.STATE_ATTR) ~= fs then
			character:SetAttribute(MuscleSystem.CONFIG.STATE_ATTR, fs)
		end

		-- the platform ability scripts drive the legacy trip state via
		-- ChangeState (bypasses SetStateEnabled) and it REPLICATES: on the
		-- client, FallingDown stops every animation track mid-walk — the
		-- post-fall "super jittery, one leg trailing in the air" walk the
		-- user reported is the stock fall pose flapping in and out. While the
		-- body is functionally upright, force the state machine back to
		-- Running. task.defer: state changes are wiring, not sim math — keep
		-- them off the simulation timeline (same law as Touched).
		if fs == "upright" or fs == "stumble" then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local hs = humanoid:GetState()
				if
					hs == Enum.HumanoidStateType.FallingDown
					or hs == Enum.HumanoidStateType.GettingUp
					or hs == Enum.HumanoidStateType.Ragdoll
				then
					task.defer(function()
						if character.Parent and character:GetAttribute(MuscleSystem.CONFIG.STATE_ATTR) == fs then
							humanoid:ChangeState(Enum.HumanoidStateType.Running)
						end
					end)
				end
			end
		end

		Locomotion.apply(character, st.sprint)
		MuscleSystem.step(character)
		MuscleSystem.updateBalance(character)
	end
end

-- getup clip + stumble flail live on the presentation timeline (PreSimulation),
-- for every character this peer simulates — the server simulates all of them
PoseDriver.wire(function()
	local chars = {}
	for _, st in charStates do
		if st.character.Parent then
			table.insert(chars, st.character)
		end
	end
	return chars
end)

local ok, err = pcall(function()
	(RunService :: any):BindToSimulation(simStep)
end)
if not ok then
	-- Server Authority is off or the API moved. Loud, not silent: the muscle system is
	-- designed for the sim timeline; Heartbeat is a degraded stand-in for tuning only.
	warn("[MuscleServer] BindToSimulation FAILED (" .. tostring(err) .. ") — Heartbeat fallback. CHECK Workspace.AuthorityMode = Server.")
	RunService.Heartbeat:Connect(simStep)
end


