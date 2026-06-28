# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Changelog rule (required)

**Every time you modify code, update [CHANGELOG.md](CHANGELOG.md) in the same change.**

- Add an entry under the `## [Unreleased]` section at the top of the file.
- Put it under the correct category heading — `Added`, `Changed`, `Deprecated`,
  `Removed`, `Fixed`, `Security`, or `Documentation` — creating the heading if it
  is not present yet.
- Write the entry from the user's perspective (what changed and why it matters),
  not as a restatement of the diff.
- Follow the existing [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
  format and CalVer release tags already used in the file.
- Documentation-only or non-code changes do **not** require a changelog entry,
  but code changes always do.

If a change does not warrant a user-facing changelog line (e.g. pure refactor
with no behavior change), still note it under `Changed` so the history stays
complete.

## Version bump & build rule (required)

**Every time you modify code, bump the app version and build the project in the
same change.**

- Bump `MARKETING_VERSION` in [ytdlmc.xcodeproj/project.pbxproj](ytdlmc.xcodeproj/project.pbxproj)
  for every code change: increment the patch component for fixes/small changes
  (e.g. `1.1` → `1.1.1`) and the minor component for new features (e.g. `1.1` →
  `1.2`). Also increment `CURRENT_PROJECT_VERSION` (the build number) by one.
  Apply the bump to all targets so the values stay consistent.
- After bumping, build the project to confirm it compiles before handing back:
  `xcodebuild -project ytdlmc.xcodeproj -scheme ytdlmc -configuration Debug build`.
- The app version is shown in **Settings → About** (read from
  `CFBundleShortVersionString` / `CFBundleVersion`), so the bumped value is
  visible to users — keep that display working.
- Documentation-only or non-code changes do **not** require a version bump.

## Git commit rule (required)

**Committing is a human's job — never `git commit` automatically.** Make and
stage changes, but leave committing to the user unless they explicitly ask you to
commit. The same applies to `git push` and to creating pull requests — only do
these when the user directly requests it.

This rule binds **every** automated actor, including subagents, background
workflows, and review/verification agents: they must not run `git commit`,
`git add`, `git push`, or any other command that changes history or the remote.
When delegating to such agents, tell them explicitly to treat the repository as
read-only for git state, and afterwards check `git status` / `git log` to confirm
no stray commit was created.
