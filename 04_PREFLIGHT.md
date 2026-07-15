# 04 · PRE-FLIGHT
## Do these before the first Claude Code session. ~1 hour total.

---

## 1. Git — before anything touches the repo
```bash
cd subrosa-body
git init
git add -A
git commit -m "baseline: docs + scaffolding, pre-code"
```
The docs are the project's memory; the history is its lab notebook.
**Standing rule at every passed gate:** Claude Code snapshots all scripts (via MCP) into
`snapshots/gateN_<name>/`, commits with `gate N passed: <one line of what held>`, and you
**publish the place** — Roblox keeps place version history you can roll back to, which is
the checkpoint between snapshots.
A failed tuning direction you can diff back out of costs nothing. One you can't costs a day.

---

## 2. The Roblox Studio MCP — for CLAUDE CODE, not the desktop app
The MCP timed out when tested from the chat app during planning. **Claude Code's MCP
config is separate from Claude Desktop's** — setting up one does not set up the other.

- Install Roblox's official Studio MCP server (Roblox/studio-rust-mcp-server on GitHub)
  and register it with Claude Code (`claude mcp add ...`, per that repo's README).
- Open the Studio place, start the plugin/connection, then verify **from Claude Code**.
- **With no file sync, the MCP is the only path to the code — a single point of failure.**
  If it proves flaky in session one, fix it before proceeding. The only alternatives are
  a miserable manual copy-paste loop or reintroducing a file-sync tool. There is no third
  option, so it's worth an hour of getting this rock-solid now.

**The first message of the first session is a verification, not work** (see §6).

### ⚠️ Open question to answer in session one — it shapes the whole workflow
Every gate needs **two clients** (Studio → Test → 2 Players). It is unverified whether the
MCP can see and switch between the test server + both client instances
(`list_roblox_studios` / `set_active_studio` suggest multi-instance support, but
two-player test sessions are untested). Have Claude Code check this immediately:
- **If yes** → it can drive the actor AND read the observer. Fully self-serve tuning loops.
- **If no** → you are the observing client for every gate. Still fine — plan sessions
  so gate checks batch at the end rather than interrupting you every five minutes.

---

## 3. The Studio place
- Create the place, **publish it** (the Character Controller Library toggle requires a
  published experience).
- Flip all four switches from ENGINE_FACTS, by hand:
  `StarterPlayer.AvatarJointUpgrade = Enabled` · `Workspace.AuthorityMode = Server` ·
  Avatar Settings → Movement → **Character Controller Library ON** ·
  `StarterPlayer.CharacterBreakJointsOnDeath = false`.
- Drop the **Iris rbxm** (latest GitHub release, SirMallard/Iris) into `ReplicatedStorage`.
  It has no dependencies.
- Locate Studio's **network simulation** settings (latency / jitter / packet loss —
  shipped June 2026) so they're one click away at gate time.

---

## 4. Reference material — 30 minutes that anchors every tuning session
Tuning *feel* without a reference is how projects drift into "technically working,
feels wrong."

- **Record 6 short clips of actual Sub Rosa** (or pull from YouTube): walk, run, a stumble,
  getting shot while moving, a bleed-out, carrying items in both hands. Drop them in a
  `reference/` folder. When Phase 2–4 tuning stalls on "is this right?", the answer is in
  the clips, not in anyone's memory.
- **Save local copies of Roblox's official reference places** (Claude Code cannot browse
  Roblox): *Physically Simulated Characters Demo* (uncopylocked — Roblox's own powered-
  joint implementation, read before Phase 1), and the *Laser Tag* + *Racing* Server
  Authority templates (SA patterns in working form).

---

## 5. Session protocol — protects exactly what you said you wanted protected
- **One phase per session.** Finish the gate, log the tuning values, commit, `/clear`.
- **The docs and the tuning log are the memory. The conversation is disposable.**
  If something matters, it goes in `03_TUNING_LOG.md` before the session ends — that's
  what makes `/clear` free.
- Start each phase in **plan mode** (have it restate the gate and its approach before
  touching code); approve, then let it run.
- When prompted for permissions, allowlist the boring loop (MCP read/inspect tools, `git`)
  so sessions don't stall on approvals.
- Phase 1 will be **multiple sessions**. That's by design, not failure — it's the hard one.
  The tuning log is what makes session N+1 start where N ended.

---

## 6. First session, exact opening message
Paste this, verbatim, before any work:

> Read CLAUDE.md, docs/00_ENGINE_FACTS.md, and docs/02_PHASES.md in full.
> Then verify the Roblox Studio MCP connection: list connected Studio instances, read the
> game tree, round-trip one script edit (write → read back → confirm it matches), and tell
> me whether you can see multiple instances during a 2-player test session.
> Report findings. Do not build anything yet.

Then, as the second message:

> start phase 0

---

## 7. Naming & IP hygiene — one paragraph, then never think about it again
"subrosa-body" is an internal codename. The shipped game gets its own name, and nothing
is copied from the original — no assets, no logos, no title. A spiritual successor with
original art and its own identity is standard practice; shipping under the original's
name or look is asking for a takedown. Decide the real name whenever — nothing in this
repo depends on it.

---

*That's the whole list. Everything still unknown after this is empirical — which is what
Gate 0 and Gate 1 exist to answer.*
