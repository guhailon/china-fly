# China Fly — local smoke build (Linux)

Toolchain: `$HOME/theos` (Theos + iOS 16.5 SDK), `gmake`, `dpkg-deb`.

```sh
BUILD=/tmp/chinafly-build
rm -rf "$BUILD"; mkdir -p "$BUILD"
rsync -a --exclude=.git ~/workspace/goals/space/files/ios-jailbreak-china-fly/ "$BUILD/"
chmod -R g-s "$BUILD"          # rsync -a carries 2770 setgid dir perms; dpkg-deb rejects them
cd "$BUILD"
umask 022
THEOS=$HOME/theos gmake package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
ls -la packages/
```

Notes:
- `chmod g-s` whole tree + `umask 022` is mandatory (old-tree lesson: dpkg-deb
  wants the 0755 tier; `chmod 0755` cannot clear setgid here, it becomes 2755).
- The smoke .deb is NOT signed for device install the way the macOS build is;
  it only proves the code compiles and packages. Real build = GitHub Actions
  (push triggers it; do not push without Lee's approval).
