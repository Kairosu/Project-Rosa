--!strict
-- Phase 1 debug panel. Presentation only — it READS joint state freely, but every WRITE
-- goes through the MuscleDebug remote so the server lands it on the simulation timeline.
-- Never writes joint properties directly: under Server Authority that's a lie the
-- rollback would immediately un-tell.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Iris = require(Shared:WaitForChild("Iris")) :: any
local MuscleSystem = require(Shared:WaitForChild("MuscleSystem"))

local CONFIG = {
	STRENGTH_MAX = 2, -- phase spec range; Roblox warns >1 can destabilize
	DAMPING_MAX = 4,
	TORQUE_LOG_MAX = 7,
}

local remote = ReplicatedStorage:WaitForChild("MuscleDebug") :: RemoteEvent
local player = Players.LocalPlayer

-- rolling frame-time (gate metric, presentation-side)
local frameMs = 0
RunService.RenderStepped:Connect(function(dt)
	frameMs = frameMs * 0.95 + (dt * 1000) * 0.05
end)

local jointStates: { [string]: { [string]: any } } = {}
local masterState = Iris.State(1)
local lastPowered = false

local function attrOr(char: Model, attr: string, fallback: number): number
	return tonumber(char:GetAttribute(attr)) or fallback
end

local function statesFor(char: Model, joint: string): { [string]: any }
	local s = jointStates[joint]
	if not s then
		local v = MuscleSystem.getValues(char)[joint]
		s = {
			strength = Iris.State(v[1]),
			damping = Iris.State(v[2]),
			torqueLog = Iris.State(math.clamp(math.log10(math.max(v[3], 1)), 0, CONFIG.TORQUE_LOG_MAX)),
		}
		jointStates[joint] = s
	end
	return s
end

local function reread(char: Model?)
	table.clear(jointStates)
	if char then
		masterState:set(attrOr(char, MuscleSystem.CONFIG.MASTER_TONE_ATTR, 1))
	end
end

player.CharacterAdded:Connect(function()
	table.clear(jointStates)
end)

Iris.Init()

Iris:Connect(function()
	local char = player.Character

	Iris.Window({ "Body · Muscle (Phase 1)" })

	if not char then
		Iris.Text({ "waiting for character..." })
		Iris.End()
		return
	end

	local joints, jointCount = MuscleSystem.getJoints(char)
	local powered = char:GetAttribute(MuscleSystem.CONFIG.POWERED_ATTR) == true

	-- attributes are seeded server-side after spawn; snap states to truth when they land
	if powered and not lastPowered then
		reread(char)
	end
	lastPowered = powered

	Iris.Text({
		("joints: %d/15   powered: %s   recv: %.1f KB/s   frame: %.1f ms"):format(
			jointCount,
			tostring(powered),
			(Stats :: any).DataReceiveKbps or 0,
			frameMs
		),
	})
	if MuscleSystem.lastBalanceError then
		Iris.Text({ "!! balance hook error: " .. tostring(MuscleSystem.lastBalanceError) })
	end

	Iris.SeparatorText({ "master tone" })

	local master = Iris.SliderNum({ "MasterTone", 0.01, 0, 1 }, { number = masterState })
	if master.numberChanged() then
		remote:FireServer(MuscleSystem.CONFIG.MASTER_TONE_ATTR, masterState:get())
	end
	Iris.SameLine()
	if Iris.Button({ "Collapse (tone 0)" }).clicked() then
		masterState:set(0)
		remote:FireServer(MuscleSystem.CONFIG.MASTER_TONE_ATTR, 0)
	end
	if Iris.Button({ "Restore (tone 1)" }).clicked() then
		masterState:set(1)
		remote:FireServer(MuscleSystem.CONFIG.MASTER_TONE_ATTR, 1)
	end
	Iris.End()

	if Iris.Button({ "Re-read values" }).clicked() then
		reread(char)
	end

	Iris.SeparatorText({ "joints (root-out order)" })

	for _, name in MuscleSystem.JOINTS do
		local joint = joints and joints[name]
		Iris.Tree({ name })
		if joint then
			local s = statesFor(char, name)

			local strength = Iris.SliderNum({ "AngularStrength", 0.01, 0, CONFIG.STRENGTH_MAX }, { number = s.strength })
			if strength.numberChanged() then
				remote:FireServer(MuscleSystem.fieldKey(name, "s"), s.strength:get())
			end

			local damping = Iris.SliderNum({ "AngularDamping", 0.01, 0, CONFIG.DAMPING_MAX }, { number = s.damping })
			if damping.numberChanged() then
				remote:FireServer(MuscleSystem.fieldKey(name, "d"), s.damping:get())
			end

			local torque = Iris.SliderNum({ "MaxTorque (log10)", 0.05, 0, CONFIG.TORQUE_LOG_MAX }, { number = s.torqueLog })
			if torque.numberChanged() then
				remote:FireServer(MuscleSystem.fieldKey(name, "t"), 10 ^ s.torqueLog:get())
			end

			local a = joint :: any
			Iris.Text({
				("live: kin=%s str=%.2f damp=%.2f torque=%.0f"):format(
					tostring(a.IsKinematic),
					tonumber(a.AngularStrength) or -1,
					tonumber(a.AngularDamping) or -1,
					tonumber(a.MaxTorque) or -1
				),
			})
		else
			Iris.Text({ "missing" })
		end
		Iris.End()
	end

	Iris.End()
end)
