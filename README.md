# China Fly — TrollOpen-style splitscreen

Original Theos tweak. Target: iPhone 11 / iOS 16.5 / Dopamine (rootless).
SpringBoard-only floating-window splitscreen with a dial launcher,
modelled on TrollOpen's layout and settings (video/photo reference only —
TrollOpen is closed-source paid; no code or assets from it).

- Package: `com.guhailong.fly`, version from 1.0.0, public repo `guhailon/china-fly`.
- Prefs domain: `com.guhailong.fly` (separate from SeaDragon Split's
  `com.guhailong.splitscreen`). Master switch defaults OFF; if SeaDragon
  Split is enabled, China Fly sleeps at load time (mutual exclusion, one-way).
- Build: macOS + Xcode + Theos, or GitHub Actions (`.github/workflows/build.yml`).
  Local Linux smoke build: see BUILD_LOG.md.
- Keyboard external is NOT in 1.0.0 (deferred); no keyboard helper dylib.
- No activation, no lyric player — neither is in TrollOpen's design.
