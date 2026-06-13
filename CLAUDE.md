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

## Git commit rule (required)

**Never run `git commit` automatically.** Make and stage changes, but leave
committing to the user unless they explicitly ask you to commit. The same applies
to `git push` and to creating pull requests — only do these when the user
directly requests it.
