--!strict
-- Client half of the sim: steps the LOCAL character only (the predicted instance).
-- Same deterministic solve from the same replicated attributes as the server, so
-- prediction agrees with authority. Other characters arrive via replication untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MuscleSystem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MuscleSystem"))
local Locomotion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locomotion")) -- key watch + remote only

local player = Players.LocalPlayer

local function simStep(_dt: number)
	local character = player.Character
	if character then
		local _, peakRel = MuscleSystem.scanBody(character)
		MuscleSystem.noteImpact(character, peakRel, if type(_dt) == "number" then _dt else 1 / 60)
		-- SpeedMultiplier is written by the SERVER ONLY. Writing it from both peers
		-- compounds it (16 → 41 stud/s measured live): under SA the two writes land
		-- as separate attribute-change events and the ability multiplies on each.
		MuscleSystem.step(character)
		MuscleSystem.updateBalance(character)
	end
end

-- sprint INTENT to the server, outside the sim step (a remote fired inside
-- BindToSimulation would re-fire on every rollback resimulation)
local sprintRemote = ReplicatedStorage:WaitForChild("MuscleDebug") :: RemoteEvent
local lastSprint = false
RunService.RenderStepped:Connect(function()
	local sprinting = Locomotion.localSprint()
	if sprinting ~= lastSprint then
		lastSprint = sprinting
		sprintRemote:FireServer(Locomotion.CONFIG.REMOTE_KEY, if sprinting then 1 else 0)
	end
end)

local ok, err = pcall(function()
	(RunService :: any):BindToSimulation(simStep)
end)
if not ok then
	warn("[MuscleClient] BindToSimulation FAILED (" .. tostring(err) .. ") — PreSimulation fallback. CHECK Workspace.AuthorityMode = Server.")
	RunService.PreSimulation:Connect(simStep)
end
