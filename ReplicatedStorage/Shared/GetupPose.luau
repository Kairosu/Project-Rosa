--!strict
-- Layer 1 · INTENT, get-up half: the shared getup CLOCK and orientation latch.
--
-- The pose itself lives in PoseDriver as IK plant targets (hands to the
-- ground beside the hips, feet under the body) — the ONE target channel the
-- engine applies on every peer (☠️ Transform-ownership law, ENGINE_FACTS §1:
-- script Transform writes are client-placebo, runtime AnimationTracks are
-- gated by the SA animate state machine). Earlier incarnations of this module
-- carried an authored joint-space keyframe clip; it rendered only on the
-- server and the actor's screen read stiff (then "possessed" once the client
-- went limp) — full autopsy in tuning log Addenda 8–9. Git history keeps the
-- clip if it's ever wanted for an uploaded-asset route.
--
-- What remains here is the shared state every module keys off:
--   GT  — server-written elapsed getup time (the clip clock)
--   GF  — server-latched face-up/down at the rise moment (one truth, no
--         per-peer threshold disagreements)
-- MuscleSystem schedules tone from progress(); PelvisDrive ramps hover
-- height from it; PoseDriver schedules IK plant weights from it.

local CONFIG = {
	-- total rise length; everything schedules against this. 1.6 crowded the
	-- IK phases (bridge/downward-dog reads + retries — user report, Add. 9 v2)
	CLIP_TIME = 2.0,
	TIME_ATTR = "GT",
	FACE_ATTR = "GF",
	AXIS_ATTR = "GA",
}

local GetupPose = {}
GetupPose.CONFIG = CONFIG

-- lying orientation from the PELVIS frame: LookVector points out the belly.
-- Belly toward the sky = supine. On the side counts as supine (the rise
-- rolls it the rest of the way).
function GetupPose.isFaceUp(pelvis: BasePart): boolean
	return pelvis.CFrame.LookVector.Y > -0.3
end

function GetupPose.progress(t: number): number
	return math.clamp(t / CONFIG.CLIP_TIME, 0, 1)
end

-- head-ward axis of a lying body, projected flat: the pelvis UP vector is the
-- spine (the look vector points into/out of the ground on a lying body and
-- lies about facing); near-upright frames fall back to look. The server calls
-- this ONCE at the rise moment and latches the result (GA): recomputing it
-- live swiveled every plant with the pelvis wobble, and the projection
-- genuinely REVERSES mid-rise on a face-up body (sitting up flips facing) —
-- near the switch threshold the axis flickered 180° frame-to-frame and the
-- plant targets teleported with it (the late-rise leg spasm, user report).
function GetupPose.headAxis(pelvis: BasePart): Vector3
	local upv = pelvis.CFrame.UpVector
	local flat = Vector3.new(upv.X, 0, upv.Z)
	if flat.Magnitude < 0.15 then
		local look = pelvis.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	return if flat.Magnitude > 0.001 then flat.Unit else Vector3.zAxis
end

return GetupPose
