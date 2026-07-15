--!strict
-- Layer 1 · INTENT, locomotion half: sprint.
--
-- ☠️ Two custom-input paths are DEAD ENDS under Server Authority (verified live
-- 2026-07-14, both):
-- 1. A custom InputAction's state does NOT sync client→server — not even read
--    inside the server's BindToSimulation (client GetState=true, server false).
-- 2. Adding custom InputAction/InputContext instances near the stock input tree
--    correlates with the engine's input sync WEDGING for the whole session
--    (server stops receiving movement entirely: client walks in place while
--    the server sees MovingDirection = 0,0,0 forever). Do not create custom
--    IAS instances until Roblox documents support.
--
-- So the keybind is plain UserInputService on the client (local, presentation
-- input), and sprint INTENT travels over the validated MuscleDebug remote.
-- BOTH peers then write the same speed knob deterministically: the client from
-- its local key state (instant prediction), the server from the remote
-- (authority). The knob is a replicated attribute, so SA attribute rollback
-- reconciles the ~one-RTT seam on each transition.
--
-- Speed itself goes through the AvatarAbilities Running ability's own
-- SpeedMultiplier attribute — never Humanoid.WalkSpeed, and we don't fight the
-- ability for BaseMoveSpeed. Verified live: 1.6 → 26.8 stud/s cruise (walk 16).

local UserInputService = game:GetService("UserInputService")

local CONFIG = {
	SPRINT_MULT = 1.6,
	SPRINT_KEY = Enum.KeyCode.LeftShift,
	REMOTE_KEY = "SPRINT",
}

local Locomotion = {}
Locomotion.CONFIG = CONFIG

-- client only: the local key state
function Locomotion.localSprint(): boolean
	return UserInputService:IsKeyDown(CONFIG.SPRINT_KEY)
end

-- both peers, inside sim: sprint intent → the ability's speed knob
function Locomotion.apply(character: Model, sprinting: boolean)
	local manager = character:FindFirstChild("AbilityManagerActor")
	local abilities = manager and manager:FindFirstChild("Abilities")
	local running = abilities and abilities:FindFirstChild("Running")
	if not running then
		return
	end
	local want = if sprinting then CONFIG.SPRINT_MULT else 1
	if running:GetAttribute("SpeedMultiplier") ~= want then
		running:SetAttribute("SpeedMultiplier", want)
	end
end

return Locomotion
