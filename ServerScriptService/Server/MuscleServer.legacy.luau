--!strict
-- Server sim driver: seeds muscle attributes, powers joints once the spawn settles,
-- lands debug-slider writes on the simulation timeline, guards against explosions.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MuscleSystem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MuscleSystem"))

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
	setupDone: boolean,
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
		setupDone = false,
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
			if w.key == MuscleSystem.CONFIG.MASTER_TONE_ATTR then
				st.mtTarget = w.value -- slewed below, never stepped
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

		-- master tone slews toward its target every step
		local mtNow = tonumber(character:GetAttribute(MuscleSystem.CONFIG.MASTER_TONE_ATTR)) or 1
		if mtNow ~= st.mtTarget then
			local stepSize = CONFIG.MT_RAMP_PER_SECOND * (if type(_dt) == "number" then _dt else 1 / 60)
			local newMt = mtNow + math.clamp(st.mtTarget - mtNow, -stepSize, stepSize)
			character:SetAttribute(MuscleSystem.CONFIG.MASTER_TONE_ATTR, newMt)
		end

		local offender, peakRel = MuscleSystem.scanBody(character)
		MuscleSystem.noteImpact(character, peakRel, if type(_dt) == "number" then _dt else 1 / 60)
		if st.settle == 0 and st.resetLock == 0 then
			if offender then
				warn("[MuscleServer] stability guard: " .. offender .. " — resetting " .. player.Name)
				character:SetAttribute(MuscleSystem.CONFIG.POWERED_ATTR, false)
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

