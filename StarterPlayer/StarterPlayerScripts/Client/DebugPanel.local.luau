--!strict
-- Gate 0 debug panel: enumerates every joint on the local character and reads/writes
-- muscle properties live. 15 AnimationConstraints expected; any Motor6D means AJU is off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Iris = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Iris")) :: any

local CONFIG = {
	STRENGTH_MAX = 2, -- Roblox warns >1 may destabilize; slider allows probing anyway
	DAMPING_MAX = 4, -- root joints need > critical per official anti-oscillation recipe
	TORQUE_LOG_MAX = 7, -- MaxTorque slider is log10: 1 → 1e7
}

local player = Players.LocalPlayer

local joints: { Instance } = {}
local motor6DCount = 0
local dirty = true

-- Iris states per joint, created lazily so respawns/rescans stay cheap
local stateCache: { [Instance]: { [string]: any } } = {}

local function rescan(char: Model?)
	table.clear(joints)
	table.clear(stateCache)
	motor6DCount = 0
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			table.insert(joints, d)
		elseif d:IsA("Motor6D") then
			motor6DCount += 1
			table.insert(joints, d)
		end
	end
	table.sort(joints, function(a, b)
		return a.Name < b.Name
	end)
end

local function watchCharacter(char: Model)
	dirty = true
	-- joints stream in during appearance load; coalesce rescans to one per frame
	char.DescendantAdded:Connect(function()
		dirty = true
	end)
	char.DescendantRemoving:Connect(function()
		dirty = true
	end)
end

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

local function statesFor(j: Instance): { [string]: any }
	local s = stateCache[j]
	if not s then
		local a = j :: any
		local torque = tonumber(a.MaxTorque) or 0
		s = {
			kin = Iris.State(a.IsKinematic == true),
			strength = Iris.State(tonumber(a.AngularStrength) or 0),
			damping = Iris.State(tonumber(a.AngularDamping) or 0),
			torqueLog = Iris.State(math.clamp(math.log10(math.max(torque, 1)), 0, CONFIG.TORQUE_LOG_MAX)),
		}
		stateCache[j] = s
	end
	return s
end

Iris.Init()

Iris:Connect(function()
	if dirty then
		dirty = false
		rescan(player.Character)
	end

	Iris.Window({ "Body · Joints (Gate 0)" })

	local acCount = #joints - motor6DCount
	Iris.Text({ ("AnimationConstraints: %d   Motor6D: %d"):format(acCount, motor6DCount) })
	if motor6DCount > 0 then
		Iris.Text({ "!! Motor6D present — AvatarJointUpgrade is OFF" })
	elseif acCount == 15 then
		Iris.Text({ "OK: 15/15 AnimationConstraints — AJU active" })
	elseif acCount == 0 then
		Iris.Text({ "waiting for character..." })
	end

	if Iris.Button({ "Re-read values from joints" }).clicked() then
		table.clear(stateCache)
	end

	for _, j in joints do
		Iris.Tree({ j.Name })
		Iris.Text({ j.ClassName })

		if j:IsA("AnimationConstraint") then
			local a = j :: any
			local s = statesFor(j)

			local cb = Iris.Checkbox({ "IsKinematic" }, { isChecked = s.kin })
			if cb.checked() or cb.unchecked() then
				a.IsKinematic = s.kin:get()
			end

			local strength = Iris.SliderNum(
				{ "AngularStrength", 0.01, 0, CONFIG.STRENGTH_MAX },
				{ number = s.strength }
			)
			if strength.numberChanged() then
				a.AngularStrength = s.strength:get()
			end

			local damping = Iris.SliderNum(
				{ "AngularDamping", 0.01, 0, CONFIG.DAMPING_MAX },
				{ number = s.damping }
			)
			if damping.numberChanged() then
				a.AngularDamping = s.damping:get()
			end

			local torque = Iris.SliderNum(
				{ "MaxTorque (log10)", 0.05, 0, CONFIG.TORQUE_LOG_MAX },
				{ number = s.torqueLog }
			)
			if torque.numberChanged() then
				a.MaxTorque = 10 ^ s.torqueLog:get()
			end

			Iris.Text({
				("live: kin=%s str=%.2f damp=%.2f torque=%s"):format(
					tostring(a.IsKinematic),
					tonumber(a.AngularStrength) or -1,
					tonumber(a.AngularDamping) or -1,
					tostring(a.MaxTorque)
				),
			})
		end

		Iris.End()
	end

	Iris.End()
end)
