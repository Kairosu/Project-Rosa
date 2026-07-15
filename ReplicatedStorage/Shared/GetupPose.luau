--!strict
-- Layer 1 · INTENT, get-up half: procedural pose sequences for GETUP.
--
-- No Animation assets: the "clip" is authored keyframes written into
-- AnimationConstraint.Transform during PreSimulation (the official procedural
-- hook — last writer before the batch application, stacks correctly with the
-- Animator). The muscles STRIVE toward these poses at whatever tone the state
-- machine allows — the body physically pushes itself up, or physically fails
-- to. There is no blend, because there is nothing to blend from.
--
-- The FIRST keyframe is not authored: it is the CAPTURED landed pose (the
-- physical relative attachment frames at GETUP entry, latched by PoseDriver).
-- The sequence therefore starts "from whatever contorted pose he actually
-- landed in" — literally — instead of snapping limbs to a canonical tuck
-- (user feedback: "ragdoll to pure stiff limbs back in their regular spot").
--
-- Both peers evaluate the same sequence from the same replicated clock (the
-- "GT" attribute, server-written elapsed getup time), so prediction agrees.
--
-- Staggering is deliberate: arms organize FIRST (0.35), the push happens
-- through the middle (0.8), the legs take the load into a crouch (1.2), and
-- only then does the body finish to stand. Tone scheduling in
-- MuscleSystem.step follows the same order (arms lead, spine unfurls last).

local CONFIG = {
	CLIP_TIME = 1.6, -- total sequence length; PelvisDrive ramps hover height across it
	TIME_ATTR = "GT",
}

export type Pose = { [string]: CFrame }
type Key = { t: number, joints: Pose }

local GetupPose = {}
GetupPose.CONFIG = CONFIG

-- shorthand: rotations in degrees
local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- FACE-UP (supine): hands plant beside the pelvis, knees tuck, sit up
-- through the waist, roll onto the feet.
local FACE_UP: { Key } = {
	{ t = 0.35, joints = {
		-- gather: knees come up, hands move to plant beside the hips
		LeftHip = ang(-75, 0, 0), RightHip = ang(-75, 0, 0),
		LeftKnee = ang(95, 0, 0), RightKnee = ang(95, 0, 0),
		Waist = ang(-25, 0, 0), Neck = ang(-15, 0, 0),
		LeftShoulder = ang(-30, 0, -35), RightShoulder = ang(-30, 0, 35),
		LeftElbow = ang(30, 0, 0), RightElbow = ang(30, 0, 0),
	} },
	{ t = 0.8, joints = {
		-- the push: arms drive behind, torso sits up, feet find the ground
		LeftHip = ang(-95, 0, 0), RightHip = ang(-95, 0, 0),
		LeftKnee = ang(105, 0, 0), RightKnee = ang(105, 0, 0),
		Waist = ang(-45, 0, 0), Neck = ang(-5, 0, 0),
		LeftShoulder = ang(-70, 0, -15), RightShoulder = ang(-70, 0, 15),
		LeftElbow = ang(10, 0, 0), RightElbow = ang(10, 0, 0),
	} },
	{ t = 1.2, joints = {
		-- crouch: weight over the feet, arms easing off
		LeftHip = ang(-55, 0, 0), RightHip = ang(-55, 0, 0),
		LeftKnee = ang(65, 0, 0), RightKnee = ang(65, 0, 0),
		Waist = ang(-10, 0, 0),
		LeftShoulder = ang(-15, 0, -10), RightShoulder = ang(-15, 0, 10),
	} },
	{ t = 1.6, joints = {} }, -- stand: identity, the Animator's idle takes over
}

-- FACE-DOWN (prone): hands under the shoulders, press the chest up, drag the
-- knees under, rise from the crouch.
local FACE_DOWN: { Key } = {
	{ t = 0.35, joints = {
		LeftShoulder = ang(-60, 0, -25), RightShoulder = ang(-60, 0, 25),
		LeftElbow = ang(70, 0, 0), RightElbow = ang(70, 0, 0),
		Waist = ang(15, 0, 0), Neck = ang(25, 0, 0),
		LeftHip = ang(-15, 0, 0), RightHip = ang(-15, 0, 0),
	} },
	{ t = 0.8, joints = {
		-- the press: elbows extend, hips flex hard to drag the knees under
		LeftShoulder = ang(-85, 0, -10), RightShoulder = ang(-85, 0, 10),
		LeftElbow = ang(5, 0, 0), RightElbow = ang(5, 0, 0),
		Waist = ang(0, 0, 0), Neck = ang(10, 0, 0),
		LeftHip = ang(-85, 0, 0), RightHip = ang(-85, 0, 0),
		LeftKnee = ang(95, 0, 0), RightKnee = ang(95, 0, 0),
	} },
	{ t = 1.2, joints = {
		LeftHip = ang(-55, 0, 0), RightHip = ang(-55, 0, 0),
		LeftKnee = ang(65, 0, 0), RightKnee = ang(65, 0, 0),
		Waist = ang(-10, 0, 0),
		LeftShoulder = ang(-15, 0, -10), RightShoulder = ang(-15, 0, 10),
	} },
	{ t = 1.6, joints = {} },
}

local IDENTITY = CFrame.identity

-- lying orientation from the PELVIS frame: LookVector points out the belly.
-- Belly toward the sky = supine. On the side counts as supine (the tuck
-- sequence rolls it the rest of the way).
function GetupPose.isFaceUp(pelvis: BasePart): boolean
	return pelvis.CFrame.LookVector.Y > -0.3
end

-- the full target pose at elapsed time t, starting FROM entryPose (the
-- captured landed pose); nil once the clip is over
function GetupPose.poseAt(faceUp: boolean, t: number, jointNames: { string }, entryPose: Pose?): Pose?
	if t >= CONFIG.CLIP_TIME then
		return nil
	end
	t = math.max(t, 0)
	local keys = if faceUp then FACE_UP else FACE_DOWN
	local pose: Pose = {}
	-- before the first authored key: lerp captured-entry → first key
	if t < keys[1].t then
		local alpha = t / keys[1].t
		local k = keys[1].joints
		for _, name in jointNames do
			local ce = (entryPose and entryPose[name]) or IDENTITY
			pose[name] = ce:Lerp(k[name] or IDENTITY, alpha)
		end
		return pose
	end
	local a, b = keys[#keys], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local span = math.max(b.t - a.t, 1e-3)
	local alpha = math.clamp((t - a.t) / span, 0, 1)
	for _, name in jointNames do
		local ca = a.joints[name] or IDENTITY
		local cb = b.joints[name] or IDENTITY
		pose[name] = ca:Lerp(cb, alpha)
	end
	return pose
end

function GetupPose.progress(t: number): number
	return math.clamp(t / CONFIG.CLIP_TIME, 0, 1)
end

return GetupPose
