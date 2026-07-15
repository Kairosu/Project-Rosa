--!strict
-- Server sim driver: seeds muscle attributes, powers joints once the spawn settles,
-- lands debug-slider writes on the simulation timeline, guards against explosions.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MuscleSystem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MuscleSystem"))
local Locomotion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locomotion"))

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
	riseTimer: number, -- watchdog: a rise that never reaches upright retries the fall cycle
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
	if key == Locomotion.CONFIG.REMOTE_KEY then
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
		riseTimer = 0,
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
		local upY = if hrp then hrp.CFrame.UpVector.Y else 1
		local dtStep = if type(_dt) == "number" then _dt else 1 / 60
		if st.fallTimer > 0 then
			st.fallTimer -= dtStep
			st.upHold = 0
			if st.fallTimer <= 0 then
				-- limp period over: right the capsule (it fell with the body and
				-- cannot right itself — see getUpAssist), then one boosted rise
				MuscleSystem.getUpAssist(character)
				MuscleSystem.setCapsuleReleased(character, false)
				character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, true)
				st.riseTimer = FALL.riseTimeout
			end
		else
			st.upHold = if upY > FALL.riseUp then st.upHold + dtStep else 0
			if st.upHold >= FALL.riseHold and not st.fallArmed then
				st.fallArmed = true
				character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, false)
			end
			-- rise watchdog: when the clock runs out, check posture — an upright
			-- body just needs more time for upHold to clear Rising (a blind retry
			-- here knocked down SUCCESSFUL stands, verified live); a body still
			-- on the ground genuinely failed and retries the down-and-right cycle
			if character:GetAttribute(MuscleSystem.CONFIG.RISING_ATTR) == true then
				st.riseTimer -= dtStep
				if st.riseTimer <= 0 then
					if upY > FALL.riseUp then
						st.riseTimer = 0.5
					else
						character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, false)
						MuscleSystem.setCapsuleReleased(character, true)
						st.fallTimer = FALL.retryDown
					end
				end
			end
			-- going down by TILT, or knocked down by a hard impact (wall crash /
			-- massive hit): a deep reflex dip means the body cannot stay up — the
			-- readable reaction is the tone crash, not the balance dip
			local knockedDown = MuscleSystem.impactFactor(character) < MuscleSystem.CONFIG.IMPACT.knockdownFactor
			if
				st.fallArmed
				and (upY < FALL.tiltUp or knockedDown)
				and st.settle == 0
				and st.resetLock == 0
				and character:GetAttribute(MuscleSystem.CONFIG.POWERED_ATTR) == true
			then
				st.fallArmed = false
				st.fallTimer = FALL.downTime
				-- the hips go down WITH the body (user feedback: limbs ragdolled
				-- but still standing and walkable = broken)
				MuscleSystem.setCapsuleReleased(character, true)
			end
		end
		st.mtTarget = if st.fallTimer > 0 then math.min(st.userMt, FALL.tone) else st.userMt

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
				-- a guard reset mid-fall must not leave the capsule released
				st.fallTimer = 0
				character:SetAttribute(MuscleSystem.CONFIG.RISING_ATTR, false)
				MuscleSystem.setCapsuleReleased(character, false)
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

		Locomotion.apply(character, st.sprint)
		MuscleSystem.step(character)
		MuscleSystem.updateBalance(character)
	end
end

local ok, err = pcall(function()
	(RunService :: any):BindToSimulation(simStep)
end)
if not ok then
	-- Server Authority is off or the API moved. Loud, not silent: the muscle system is
	-- designed for the sim timeline; Heartbeat is a degraded stand-in for tuning only.
	warn("[MuscleServer] BindToSimulation FAILED (" .. tostring(err) .. ") — Heartbeat fallback. CHECK Workspace.AuthorityMode = Server.")
	RunService.Heartbeat:Connect(simStep)
end

