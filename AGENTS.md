# Contributor Guidelines

This repository is the AI Markdown fork of [PhraseHQ/SwaTex](https://github.com/PhraseHQ/SwaTex). It provides the default math formula renderer for the optional `AIMarkdownMath` product of [ai-markdown-swift](https://github.com/ai-markdown/ai-markdown-swift).

## Branches and baseline

- Maintain AI Markdown changes on the `ai-markdown` branch, which is the default branch of this fork.
- Preserve the upstream `main` branch as a mirror of upstream. Never commit AI Markdown changes to it or rewrite its history.
- The `ai-markdown` branch starts from upstream release `0.5.0` (`2b38d0b9b9b9466ac1302ab93b37f3b90b8c74fc`), the version evaluated for AI Markdown. Do not combine maintenance changes with an upstream upgrade; adopting a newer upstream revision is a separate, explicitly reviewed change that must be revalidated.

## Consumption by ai-markdown-swift

- ai-markdown-swift declares this package as a remote SwiftPM dependency pinned by an exact `revision:` and records the same commit as the `Dependencies/swatex` development submodule (`update = none`). Branch names never replace revision pins.
- Push commits to this fork first. Then update the parent repository's gitlink, `Package.swift` revision, `Package.resolved`, and `scripts/package-split/manifest.json` together.
- For co-development, run `bash scripts/dependencies.sh local` in ai-markdown-swift. It overrides the `swatex` package with `swift package edit --path Dependencies/swatex`, so uncommitted changes here are built directly. Switch back with `bash scripts/dependencies.sh remote` before committing the parent lock file.
- Only the optional `AIMarkdownMath` target of ai-markdown-swift may depend on this package. Its Engine, Core, and UI targets must not. Keep existing product and module names stable unless the parent repository is updated in the same release sequence.

## Repository constraints

- Preserve upstream licenses, copyright notices, and meaningful source data, including multilingual fixtures.
- Preserve `THIRD_PARTY_NOTICES.md` and the KaTeX font licenses (`OFL.txt`, `FONT_NOTICE.txt`) next to the bundled fonts.
- Layout parity reference is RaTeX v0.1.15 (`5f7dc48`); KaTeX 0.16.47 is the behavioral reference. Golden fixtures are regenerated with `scripts/regenerate_golden.py`, and `DifferentialLayoutTests` compares full display lists over the AI Markdown corpus (`scripts/differential/`). Every intentional deviation from RaTeX must be listed with a reason in the corresponding script and justified against KaTeX; validate layout fixes against both references and add regression tests.
- Write all new or modified development text in English, including documentation, code comments, diagnostics, log messages, test descriptions, and commit messages.
- Keep the package buildable with Swift 6 language mode for iOS 26 and macOS 26 consumers, and keep ordinary builds independent of the AI Markdown workspace or external generators.
- Keep upstream tests and add regression tests for each fix. Run checks appropriate to each change, and do not present historical results as new validation.

## Commit messages

- Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) using `<type>[optional scope][!]: <description>`.
- Use `feat` for new functionality, `fix` for bug fixes, and other types such as `docs`, `test`, or `refactor` as appropriate.
- Describe what the commit changes. Add a body when needed to explain the behavior or reasoning, separated from the subject by a blank line.
- Mark breaking changes with `!` after the type or scope, or with a `BREAKING CHANGE: <description>` footer.
