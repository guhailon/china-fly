# China Fly — floating-window splitscreen

Original Theos tweak. Target: iPhone 11 / iOS 16.5 / Dopamine (rootless).
SpringBoard-only floating-window splitscreen with a rotating dial launcher,
edge-swipe trigger, and a tap-to-add menu (original code throughout).

- Package: `com.chinafly.fly`, version from 1.0.4, public repo `guhailon/china-fly`.
- Prefs domain: `com.chinafly.fly` (separate from any other splitscreen's prefs
  domain; the two never share a file). Master switch defaults OFF; if the old
  splitscreen is enabled and its dylib is still installed, China Fly sleeps
  at load time (mutual exclusion, one-way).
- Activation: codes are fetched from the repo's own `license/codes-fly.json`
  (own list since 1.0.2; old splitscreen codes do not work here).
- Build: macOS + Xcode + Theos, or GitHub Actions (`.github/workflows/build.yml`).
  Local Linux smoke build: see BUILD_LOG.md.
- Keyboard external is NOT in 1.0.4 (research only); no keyboard helper dylib.
- No lyric player.
