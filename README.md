# SUB ROSA — POWERED RAGDOLL BODY

A fully physically-simulated character for Roblox. Every joint is a powered constraint that
*strives* toward an animated pose and can fail to reach it.

**This repo builds the body. Nothing else.**

**Workflow: MCP-first. The Studio place is the single source of truth for all code.**
There is no filesystem sync. Claude Code works on scripts inside Studio directly, through
the Roblox Studio MCP. This repo holds the docs, the tuning log, and gate-by-gate script
snapshots — never live code.

---

## SETUP (do this once)

### 1. Studio place — these settings are not optional
| Setting | Value | Where |
|---|---|---|
| `AvatarJointUpgrade` | **Enabled** | StarterPlayer properties |
| `AuthorityMode` | **Server** | Workspace properties (set manually) |
| Character Controller Library | **ON** | Avatar tab → Avatar Settings → Movement (place must be published first) |
| `CharacterBreakJointsOnDeath` | **false** | StarterPlayer properties |

**Verify:** spawn in, check the character's joints are `AnimationConstraint`, **not**
`Motor6D`. If they're Motor6D, AJU isn't on and nothing in this repo will work.

### 2. Iris (the one dependency)
Download the rbxm from the latest release of SirMallard/Iris on GitHub and drop it into
`ReplicatedStorage`. Iris has no external dependencies — no package manager needed.

### 3. ⭐ Connect the Roblox Studio MCP to Claude Code
**With no file sync, the MCP is Claude Code's ONLY access to the code.** It must work.
Install Roblox's official Studio MCP server and register it with Claude Code (its config
is separate from Claude Desktop's). Verification is the first act of the first session —
see `docs/04_PREFLIGHT.md` §6 for the exact opening message.

---

## HOW TO DRIVE IT

Open Claude Code in this directory. First session: paste the verification message from
`docs/04_PREFLIGHT.md`. Then say:

> **"start phase 0"**

`CLAUDE.md` is auto-loaded and points at everything else. Phases and their hard gates are
in `docs/02_PHASES.md`, tested on two clients under simulated latency + packet loss.

**At every passed gate:** Claude Code snapshots all scripts (via MCP) into `snapshots/`,
commits, and you publish the place — Roblox's own version history is the rollback point
between snapshots.

---

## THE DOCS

| File | What it's for |
|---|---|
| **`CLAUDE.md`** | The constitution. Auto-loaded. Scope fence, workflow, the one test that matters. |
| **`docs/00_ENGINE_FACTS.md`** | ⚠️ **The most important file here.** Every API this project depends on shipped in 2026 and postdates the model's training data. This file is the inoculation against confidently-wrong `Motor6D` code. |
| **`docs/01_ARCHITECTURE.md`** | The three-layer model. Intent → Muscle → World. |
| **`docs/02_PHASES.md`** | Phases 0–6 + the final gate. Say "start phase N". |
| **`docs/03_TUNING_LOG.md`** | **Append-only.** The stable region of a 15-joint PD controller is found empirically. Values not written down are values lost. |
| **`docs/04_PREFLIGHT.md`** | One hour of setup before the first session. |

---

## THE ONE TEST THAT MATTERS

> Player A holds a heavy briefcase out toward Player B.
> B — on 150ms with packet loss — sees the arm. Steady. Correct. Readable.
> Then A takes a round in that arm, and **B watches the briefcase drop.**
>
> Not because it was animated. Because the muscle failed and the arm could no longer hold
> the weight.

---

## SCOPE FENCE

**Not in this repo, and not to be built toward:** items · weapons · economy · map ·
vehicles · voice · phones · rounds · corporations · missions · UI · persistence.

If you catch the model building an abstraction "for later" — stop it. Later is not this repo.
