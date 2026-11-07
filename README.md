<p align="center"><img src="Resources/wasevo-logo.png" width="96" alt="Wasevo"></p>

<h1 align="center">Wasevo Cleaner</h1>
<p align="center"><b>The safe disk cleaner for developers.</b><br>Free, open source, native macOS. Built by <a href="https://wasevo.com">Wasevo</a>.</p>

---

Most Mac cleaners were built for browser caches and "junk files". On a developer's Mac the space goes somewhere else: Rust `target/` folders, `node_modules` in dozens of old projects, Docker build cache, package-manager caches, and AI-tool models. Wasevo Cleaner finds those, and more importantly, it knows what **not** to touch.

> We built it after a "cleaner" offered to delete `Docker.raw` (all Docker data), MySQL `.ibd` table files and Android emulators as "clutter". Wasevo Cleaner will never do that.

## Features

- **Smart Scan.** One click finds everything safe to clean, grouped into categories you can tick on and off.
- **Project-aware.** Walks your project folders and finds `node_modules`, Rust `target`, `.next`, `.nuxt`, `.turbo` and `.svelte-kit`. Old projects (14+ days, configurable) are pre-selected.
- **Rebuild guard.** `node_modules` is only offered when a lockfile can reinstall it exactly, and `target` only when `Cargo.toml` exists.
- **Knows what's in use.** Skips projects with a running dev server or open terminal, apps running from a build folder, and caches whose tool is running. Everything is re-checked right before deleting.
- **Real sizes.** Measures allocated blocks, so sparse files show their true size. `Docker.raw` "465 GB" is really ~30 GB.
- **Tool-native cleanups.** Docker build cache, `pnpm store prune`, `brew cleanup`, MySQL `PURGE BINARY LOGS`, dead Xcode simulators. Each runs through the tool's own command and never wipes Docker volumes.
- **Protected list.** Docker data, databases, Android emulators, `.git`, credentials and AI-tool logins are hard-blocked.
- **Delete or Trash.** You choose. The real space freed is measured from the disk.
- **Large files (view only).** Your biggest files, with 🔒 warnings on ones you must keep.
- **History log.** Every deletion is written to `~/Library/Logs/WasevoCleaner.log`.
- **Menu-bar monitor.** Free space is always visible, with a warning when it gets low.

### What it cleans

| Category | Items |
|---|---|
| System & app caches | `~/Library/Caches` (Apple caches skipped), Chrome on-device AI model, Google Updater downloads, VS Code installer cache, Chrome/Brave leftover update copies |
| Developer caches | npm, uv, Bun, Composer, Yarn, Cargo registry, shared Rust targets, Playwright/Puppeteer, Gradle, Xcode DerivedData, Arduino archives |
| Project build files | `node_modules`, `target`, `.next`, `.nuxt`, `.turbo`, `.svelte-kit` |
| Downloads & logs | Crash reports older than 7 days, old `.dmg`/`.pkg` installers (opt-in) |
| Tool cleanups | Docker build cache, pnpm, Homebrew, MySQL binlogs (opt-in), Xcode simulators (opt-in) |

## Install

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/wasevo/wasevo-cleaner.git
cd wasevo-cleaner
scripts/build-app.sh --install     # builds and opens ~/Applications/Wasevo Cleaner.app
```

## Safety model

1. **Allow-list, not block-list.** Only paths in the rule registry (`Sources/WasevoCleaner/Engine/Rules.swift`) or verified build folders are ever candidates.
2. **Hard protections.** `isSafeTarget()` refuses home/Documents/Desktop roots, `.git`, and everything matched by `protectedReason()`, even if a rule is wrong.
3. **In-use detection** from `ps` and `lsof`, re-checked immediately before each deletion.
4. **Tools clean themselves.** Docker, MySQL, pnpm and brew are never cleaned by deleting their files.

## Contributing

New cache locations are one entry in `CACHE_RULES`. PRs are welcome, especially for AI tools (Ollama, HuggingFace, Cursor, Windsurf). Please include where the cache lives, what regenerates it, and which process uses it.

```
Sources/WasevoCleaner/
  Engine/   Rules.swift (registry + protections) · Scanner.swift · Cleaner.swift
  App/      WasevoCleanerApp.swift · Store.swift · Theme.swift
  Views/    RootView · ScanView · OtherViews
```

## Roadmap

- App uninstaller with leftover finder
- Duplicate-file finder
- Disk treemap
- AI-tool sessions (Claude, Codex, Gemini) with auth-file protection
- Scheduled auto-clean of safe caches
- Signed and notarized releases, Homebrew cask

## License

MIT © Wasevo
