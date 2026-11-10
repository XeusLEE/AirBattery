<p align="center">
<img src="./AirBattery/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="200" height="200" />
<h1 align="center">AirBattery</h1>
<h3 align="center">Battery levels of your Mac and every nearby device, in the menu bar, the Dock and widgets.<br>A fork of <a href="https://github.com/lihaoyun6/AirBattery">lihaoyun6/AirBattery</a> with a redesigned interface.</h3>
</p>

## What this fork adds

- **Card-based popover and Dock window.** One card per device with icon, name, status chip (Charging / Low / Getting low / Full / Plugged in), percentage, level bar, remaining-time estimate and last-seen time. Hover a card for the alert, pin, copy and hide actions.
- **Remaining-time estimate for every device.** AirBattery keeps a small local history of battery samples (`~/Library/Application Support/AirBattery/battery-history.json`, seven days, at most 300 samples per device) and estimates "~5 h left" or "~45 min to full" from the recent trend. The Mac's own estimate comes from macOS.
- **Low-device badge in the menu bar.** When a device that is not charging drops below the low threshold (20 % by default, 10 % critical), its icon and percentage appear next to the Mac battery icon.
- **A four-tab Settings window** (General · Appearance · Devices · Discovery) that sizes itself to its content. The Devices tab manages every known device in one place: show / hide, block or allow, pin to the menu bar, low and full alerts with sound, per-device history.
- **Turkish localization**, in addition to the upstream English and Chinese.

Everything else — the Nearbility discovery engine for iPhone / iPad / Apple Watch / AirPods / Magic devices / Bluetooth peripherals, Nearcast sharing between Macs on the same network, the widgets and the `abt` command line tool — is upstream's work and behaves as before.

## Installation

**Requirements:** macOS 11.0 or later.

Download the latest DMG from the [Releases](../../releases/latest) page, open it and drag AirBattery to your Applications folder.

The builds are ad-hoc signed and not notarized (this fork has no Apple Developer membership), so macOS blocks the first launch:

1. Try to open AirBattery once and dismiss the warning.
2. Open **System Settings → Privacy & Security**, scroll to the bottom and click **Open Anyway** next to the AirBattery message. On macOS 14 and earlier you can instead right-click the app in Finder and choose **Open**.
3. Allow Bluetooth access when asked; it is needed to read peripheral battery levels.

There are no in-app updates in this fork. New versions are published on the Releases page.

## Usage

- AirBattery lives in the menu bar by default; you can switch it to the Dock or both in **Settings → General**.
- Devices are discovered automatically. Click the menu bar icon to see the cards; hover a card for actions.
- **Settings → Appearance** controls the menu bar icon, the low-device badge and its thresholds, the Dock icon and the widgets.
- **Settings → Devices** lists every device AirBattery has seen. Hide one from the popover, block it from discovery entirely (or switch to allowlist mode), pin it to the menu bar, or set low / full battery alerts.
- **Settings → Discovery** holds the scanner switches (network and Bluetooth discovery of iOS devices, Bluetooth peripherals, Apple Pencil) and Nearcast.

## Q&A

**Why is my iPhone / iPad / Apple Watch not showing up?**
> The iPhone or iPad must trust this Mac (connect it with a cable once while AirBattery is running) and be on the same network, or have "Discover iOS devices via Bluetooth" enabled for cellular devices. The Apple Watch is read through its paired iPhone when the iPhone is reached over Wi-Fi or USB.

**What does the orange "min ago" text on a card mean?**
> The device has not reported its battery for more than ten minutes; it is probably off or out of range. The card keeps the last known values.

**Why is there no remaining-time estimate on a card?**
> An estimate needs at least ten minutes of history with a two-point change in the same direction (charging or discharging). Right after a device is first seen, or after it switches between charging and discharging, the estimate disappears until enough new samples exist. The estimate can be switched off in **Settings → General**.

**Why does AirBattery need Bluetooth permission?**
> It reads battery levels from Bluetooth peripherals by listening to their advertisements.

## Building

There is no need for Xcode on your machine: the GitHub Actions workflow in `.github/workflows/build.yml` builds the app on every push to `main`, uploads the DMG as an artifact, and publishes a Release when a `v*` tag is pushed. Pure-Swift estimator logic lives in `Packages/BatteryEstimator` and is tested with `swift test`. Add files to the Xcode project with `scripts/pbxproj_edit.py` instead of editing the project file by hand.

If the signing secrets `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID` exist in the repository, the workflow signs with Developer ID and notarizes the DMG instead of ad-hoc signing.

## Türkçe

Bu depo [lihaoyun6/AirBattery](https://github.com/lihaoyun6/AirBattery) uygulamasının yeniden tasarlanmış bir çatallamasıdır: kart tabanlı popover, her cihaz için kalan süre tahmini, menü çubuğunda düşük pilli cihaz eki, dört sekmeli Ayarlar penceresi ve Türkçe arayüz. Kurulum için [Releases](../../releases/latest) sayfasındaki DMG'yi indirin; uygulama noter onaylı olmadığından ilk açılışta **Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç** adımı gerekir.

## License and credits

AirBattery is released under the [GNU Affero General Public License v3.0](./LICENSE), the same license as the upstream project by [lihaoyun6](https://github.com/lihaoyun6), whose work this fork builds on.

- [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) — bundled executables and libraries compiled from version `73b6fd1` for reading iOS device batteries.
- [comptest](https://gist.github.com/nikias/ebc6e975dc908f3741af0f789c5b1088) by @nikias — bundled executable compiled from this source.
- [MultipeerKit](https://github.com/insidegui/MultipeerKit) by @insidegui — Nearcast communication between Macs.
- [Sparkle](https://sparkle-project.org) — bundled by upstream; the update feed is empty in this fork.
