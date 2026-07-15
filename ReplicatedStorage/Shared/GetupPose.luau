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
	CLIP_TIME = 1.6, -- total rise length; everything schedules against this
	TIME_ATTR = "GT",
	FACE_ATTR = "GF",
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

return GetupPose
