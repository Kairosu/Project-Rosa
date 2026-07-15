--!strict
-- Client half of the sim: steps the LOCAL character only (the predicted instance).
-- Same deterministic solve from the same replicated attributes as the server, so
-- prediction agrees with authority. Other characters arrive via replication untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MuscleSystem = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MuscleSystem"))

local player = Players.LocalPlayer

local function simStep(_dt: number)
	local character = player.Character
	if character then
		MuscleSystem.step(character)
		MuscleSystem.updateBalance(character)
	end
end

local ok, err = pcall(function()
	(RunService :: any):BindToSimulation(simStep)
end)
if not ok then
	warn("[MuscleClient] BindToSimulation FAILED (" .. tostring(err) .. ") — PreSimulation fallback. CHECK Workspace.AuthorityMode = Server.")
	RunService.PreSimulation:Connect(simStep)
end
