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
local balanceState = Iris.State(MuscleSystem.CONFIG.BALANCE_TORQUE)
local turnState = Iris.State(MuscleSystem.CONFIG.TURN_SPEED)
local leanState = Iris.State(MuscleSystem.CONFIG.ACCEL_LEAN)
local standState = Iris.State(MuscleSystem.CONFIG.STAND_FORCE)
local lastPowered = false

-- fall recorder: a ring buffer of what THIS CLIENT actually rendered — the
-- instrument that closes the server-verified vs client-felt gap. Frozen to the
-- FallCapture StringValue 3 s after a knockdown starts (tone crash), or on
-- demand via the panel button the moment something merely FEELS wrong.
local REC_WINDOW = 420 -- ≈7 s at 60 fps
local REC_TAIL = 3
local recorder = {
	buf = table.create(REC_WINDOW) :: { string },
	head = 0,
	count = 0,
	tail = -1,
	lastMT = 1,
	clock = 0,
	frozenAt = 0,
	value = nil :: StringValue?,
}

local function recorderFreeze(reason: string)
	local v = recorder.value
	if not v then
		v = Instance.new("StringValue")
		v.Name = "FallCapture"
		v.Parent = ReplicatedStorage -- client-side only; read via the Client DM
		recorder.value = v
	end
	local lines = { "reason=" .. reason .. "  cols: t hrpY pelvisY upY SF BMS BMT MT Rising speed" }
	for i = 1, recorder.count do
		local idx = ((recorder.head - recorder.count + i - 1) % REC_WINDOW) + 1
		table.insert(lines, recorder.buf[idx])
	end
	v.Value = table.concat(lines, "\n")
	recorder.frozenAt = os.clock()
end

RunService.RenderStepped:Connect(function(dt)
	recorder.clock += dt
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pelvis = char and char:FindFirstChild("LowerTorso") :: BasePart?
	local cm = char and char:FindFirstChildOfClass("ControllerManager")
	local gc = cm and cm:FindFirstChildWhichIsA("GroundController", true)
	if not (char and hrp and pelvis and cm and gc) then
		return
	end
	local mt = tonumber(char:GetAttribute(MuscleSystem.CONFIG.MASTER_TONE_ATTR)) or 1
	local vel = hrp.AssemblyLinearVelocity
	recorder.head = recorder.head % REC_WINDOW + 1
	recorder.buf[recorder.head] = string.format(
		"%.2f %.1f %.1f %.2f %d %d %d %.2f %d %.1f",
		recorder.clock,
		hrp.Position.Y,
		pelvis.Position.Y,
		hrp.CFrame.UpVector.Y,
		(gc :: any).StandForce,
		(cm :: any).BaseMoveSpeed,
		(gc :: any).BalanceMaxTorque,
		mt,
		if char:GetAttribute(MuscleSystem.CONFIG.RISING_ATTR) == true then 1 else 0,
		Vector3.new(vel.X, 0, vel.Z).Magnitude
	)
	recorder.count = math.min(recorder.count + 1, REC_WINDOW)
	if mt < 0.5 and recorder.lastMT >= 0.5 and recorder.tail < 0 then
		recorder.tail = REC_TAIL -- knockdown began: keep rolling, then freeze
	end
	recorder.lastMT = mt
	if recorder.tail >= 0 then
		recorder.tail -= dt
		if recorder.tail < 0 then
			recorderFreeze("auto")
		end
	end
end)

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
		balanceState:set(attrOr(char, MuscleSystem.CONFIG.BALANCE_ATTR, MuscleSystem.CONFIG.BALANCE_TORQUE))
		turnState:set(attrOr(char, MuscleSystem.CONFIG.TURN_ATTR, MuscleSystem.CONFIG.TURN_SPEED))
		leanState:set(attrOr(char, MuscleSystem.CONFIG.LEAN_ATTR, MuscleSystem.CONFIG.ACCEL_LEAN))
		standState:set(attrOr(char, MuscleSystem.CONFIG.STAND_ATTR, MuscleSystem.CONFIG.STAND_FORCE))
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

	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local vel = if hrp then hrp.AssemblyLinearVelocity else Vector3.zero
	Iris.Text({
		("joints: %d/15   powered: %s   speed: %.1f   recv: %.1f KB/s   frame: %.1f ms"):format(
			jointCount,
			tostring(powered),
			Vector3.new(vel.X, 0, vel.Z).Magnitude,
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

	-- Gate 2 knob: lower it, get knocked over easier
	local balance = Iris.SliderNum({ "BalanceTorque", 10, 0, 5000 }, { number = balanceState })
	if balance.numberChanged() then
		remote:FireServer(MuscleSystem.CONFIG.BALANCE_ATTR, balanceState:get())
	end

	-- feel knobs: how fast the capsule pivots, how far the body leans into accel
	local turn = Iris.SliderNum({ "TurnSpeed", 0.5, 0, 40 }, { number = turnState })
	if turn.numberChanged() then
		remote:FireServer(MuscleSystem.CONFIG.TURN_ATTR, turnState:get())
	end
	local lean = Iris.SliderNum({ "AccelLean", 0.05, 0, 4 }, { number = leanState })
	if lean.numberChanged() then
		remote:FireServer(MuscleSystem.CONFIG.LEAN_ATTR, leanState:get())
	end

	-- hover ladder: lower it and the legs carry more of the body's real weight
	local stand = Iris.SliderNum({ "StandForce (hover)", 100, 0, 20000 }, { number = standState })
	if stand.numberChanged() then
		remote:FireServer(MuscleSystem.CONFIG.STAND_ATTR, standState:get())
	end

	Iris.SeparatorText({ "fall recorder (client-side truth)" })
	Iris.Text({
		if recorder.frozenAt > 0
			then ("last capture: %.0f s ago (%d samples)"):format(os.clock() - recorder.frozenAt, recorder.count)
			else "no capture yet — auto on knockdown, or press when something feels wrong",
	})
	if Iris.Button({ "Capture last 7 s" }).clicked() then
		recorderFreeze("manual")
	end

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
