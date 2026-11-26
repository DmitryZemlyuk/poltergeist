# Poltergeist

A small personal macOS utility that finds and removes junk: caches, logs, developer leftovers, old downloads,
device backups and data left behind by apps that are already gone. It also draws a disk map, lists large files and
uninstalls apps together with their files.

Not for the App Store – built for one Mac.

## Sections

- **Overview** – disk ring, everything found, one button to clean the selection.
- **Caches and logs** – app caches (Apple's own are left unticked, running apps are skipped), logs, crash reports, saved window state.
- **Development** – Xcode DerivedData, unused simulators, Device Support, Archives, npm / Yarn / pnpm / Homebrew / pip caches, old Node versions in nvm, Gradle, Android emulators, `node_modules` of projects untouched for a while.
- **Trash and Downloads** – the Trash, installers (.dmg, .pkg) and old downloads.
- **Backups and Mail** – iPhone/iPad backups, .ipsw files, opened Mail attachments.
- **Disk map** – squarified treemap of any folder; click to inspect, double-click to go inside.
- **Large files** – from the same scan as the map.
- **Apps** – size, last use, uninstall with related files.
- **Leftovers** – folders, preferences and containers whose app is no longer installed.

## Safety

- Caches, logs and build products are deleted right away (they are recreated). Everything else goes to the Trash.
- A guard refuses to touch anything outside the home folder (except apps in `/Applications`, Trash only), the key folders
  themselves (`~/Library`, `~/Library/Caches`, `~/Documents`…), and private places (Keychains, iCloud Drive, Mail, Messages, Photos).
- Without Full Disk Access other apps' containers are never opened, so macOS doesn't ask about each of them.

## Full Disk Access

System Settings → Privacy & Security → Full Disk Access → turn on Poltergeist. The app is signed ad hoc,
so macOS may ask again after an update.

## Building

```
swift test
tools/bundle.sh          # dist/Poltergeist.app + zip (universal)
python3 tools/strings.py # regenerate Localizable.strings (en, ru, uk)
python3 tools/make_icon.py   # needs pillow, numpy, cairosvg
```

GitHub Actions builds every push on macOS 26 and publishes a release for the version in `VERSION`
(only the three newest releases are kept).

## Credits

The broom in the app icon is the flat "Broom" emoji from [Microsoft Fluent UI Emoji](https://github.com/microsoft/fluentui-emoji),
used under the MIT License (`tools/assets/LICENSE-fluentui-emoji.txt`).
