# Settings Window Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ayarlar penceresini dört üst sekmeye (Genel · Görünüm · Cihazlar · Keşif) toplamak, içeriğe göre boyutlanan bir pencere yapmak, popover yeniden tasarımının ayarlarını ve tek yerde cihaz yönetimini eklemek.

**Architecture:** `Settings` sahnesinin kökü `TabView` olur; her sekme mevcut `GroupForm.swift` bileşenleriyle kurulur. Cihaz yönetimi `DevicesSettingsView.swift` içinde saf `KnownDeviceList.build` birleştirmesi + liste/ayrıntı görünümüyle yapılır; mevcut UserDefaults listeleri (`blackList`, `blockedDevices`, `pinnedList`, `alertList`) olduğu gibi kullanılır. `BatteryHistoryStore` sürüm 2'ye geçer (cihaz adları) ve temizleme API'leri kazanır. Pencere derlemesi yalnızca CI'da; doğrulama ekran görüntüsüyle.

**Tech Stack:** Swift 5 modu, SwiftUI + AppKit, macOS 11.0 hedef, GitHub Actions macos-15 / Xcode 16.4, `scripts/pbxproj_edit.py`. Yerelde yalnızca `swift test` (paket, değişmez).

**Spec:** `docs/superpowers/specs/2026-11-10-settings-redesign-design.md`

## Global Constraints

- Deployment target macOS 11.0: `Color(nsColor:)`, `.regularMaterial`, iki parametreli `.onChange`, `foregroundStyle`, `Text.monospacedDigit()` **kullanılmaz**; 12/13/14 API'leri `#available` ile korunur. `List(selection:)`, `TabView`, `Picker(.segmented)`, `.textCase`, `.help` macOS 11'de vardır.
- `Supports.swift`, `AirBatteryModel.swift`, `InternalBattery.swift` abt ve widget hedeflerinde de derlenir: bu dosyalara uygulama-özel tip bağımlılığı **eklenmez** (`ud` okuyan fonksiyonlar serbest).
- pbxproj yalnızca `python3 scripts/pbxproj_edit.py add-source <path> --group ViewModel` ile değişir; `plutil -lint` geçmeli.
- Mevcut 33 ayar anahtarının adı ve türü **değişmez**; her `onChange` yan etkisi (showOn etkinlik politikası, launchAtLogin, nearCast, readBLEDevice uyarısı, deviceOnWidget) aynen korunur.
- Yeni anahtarlar ve varsayılanlar (`ud.register`): `showEstimate` true, `menuBarLowSuffix` true, `menuBarCriticalThreshold` 10, `alertDefaultLow` 20, `alertDefaultFull` 80, `alertDefaultSound` true; `menuBarLowThreshold` 20 zaten kayıtlı. `settingsTab` kayıtsız gizli anahtar.
- Sabitler: pencere genişliği 560; Cihazlar listesi 8 satır × 26 pt = 208 pt; düşük eşik 5…50, kritik eşik 5…30, kritik ≤ düşük; uyarı eşikleri düşük 1…99, dolu 1…100; "görülmeyen" sınırı 7×86400 sn; geçmiş dosyası sürüm 2.
- Kullanıcıya görünen her yeni metin `"English key".local`; anahtarlar Task 6 tablosuna aynen uyar; mevcut anahtarlar (`General`, `Debug`, `Startup`, `Update`, `Menu Bar`, `Dock`, `Widget`, `Scanner`, `Others`, `Nearcast`, `Peer Info`, `Appearance`, `Allowlist Mode`, `Data Folder`, `Open`, `Cancel`, `OK`) yeniden kullanılır.
- Çalışma dalı `feature/settings-redesign` (main 50d4875 üzerinden); her görev kendi commit'i; CI `gh workflow run build.yml -R XeusLEE/AirBattery --ref feature/settings-redesign` ile başlatılır ve yeşil görülür. Kullanıcı uyuyor: çalışma zamanı doğrulamaları `/Applications/AirBattery.app`'i kapatıp sonunda yeniden açar; UserDefaults `defaults export` ile yedeklenir ve `defaults import` ile geri yüklenir.

## Review Focus

1. **Sürüm 1 geçmiş dosyasıyla açılış** (main'deki 50d4875'ten gelen kullanıcı) → `names` boş, örnekler korunur, tahminler devam eder → Task 1 doğrulama adımı.
2. **Her iki uyarı kapatılınca** → `alertList` kaydı silinir, popover'daki zil rozeti kaybolur → Task 4 davranış listesi + Task 7 `defaults read` kontrolü.
3. **Çevrimiçi cihaz engellenince** → anında listeden düşer, engelliyken tarama onu geri getirmez → Task 4 davranışı (`checkIfBlocked` mevcut) + Task 7 kontrolü.
4. **Kritik > düşük yapılmaya çalışılınca** → değerler birbirine kenetlenir, asla kritik > düşük olmaz → Task 5 davranış kuralı + Task 7 `defaults read`.
5. **Hiç cihaz yokken Cihazlar sekmesi** → `No devices yet` + `Select a device` yer tutucuları, çökme yok → Task 4 davranışı; Task 7'de boş listelerle ekran görüntüsü.

---

### Task 1: BatteryHistoryStore sürüm 2 ve temizleme API'leri

**Files:**
- Modify: `AirBattery/BatteryInfo/BatteryHistoryStore.swift`

**Interfaces:**
- Consumes: mevcut `BatteryHistoryStore.shared`, `record(_:)`, `saveIfNeeded(force:)`, `DeviceHistory`.
- Produces:
  ```swift
  // HistoryFile (private): var version: Int (2); var devices: [String: [BatterySample]]; var names: [String: String]
  func summary() -> (deviceCount: Int, bytes: Int)        // cihaz sayısı = histories.count; bytes = fileURL dosya boyutu, yoksa 0
  func names() -> [String: String]                         // deviceID → son görülen deviceName
  func lastSeen() -> [String: TimeInterval]                // deviceID → en yeni örneğin t'si (örneksiz cihaz atlanır)
  func sampleCounts() -> [String: Int]
  func clear()                                             // histories ve names boşalır, force save
  func remove(deviceID: String)                            // tek cihaz, force save
  @discardableResult func pruneUnseen(olderThan age: TimeInterval, keeping names: Set<String>) -> Int
  ```

- [ ] **Step 1: `HistoryFile`'a `names`** — `var names: [String: String] = [:]` (Codable varsayılanıyla; sürüm 1 dosyada alan yok → `decodeIfPresent` ile boş). `load()`: `version == 1 || version == 2` kabul; aksi mevcut "unreadable" yolu. Kayıtta `version: 2` yazılır.
- [ ] **Step 2: `record(_:)`** — mevcut kayıt kuralından bağımsız olarak `if names[device.deviceID] != device.deviceName { names[device.deviceID] = device.deviceName; dirty = true }` (kilit altında, `hasBattery`/Mac filtresinden sonra).
- [ ] **Step 3: Yeni API'ler** — hepsi `lock` altında kopya alır; `pruneUnseen`: `now - (lastSeen[id] ?? 0) > age` **ve** `!names.contains(names[id] ?? "")` koşulunu sağlayan id'leri `histories` ve `names`'ten siler, silinen sayıyı döner; `clear/remove/pruneUnseen` sonunda kilit dışında `saveIfNeeded(force: true)`.
- [ ] **Step 4: Commit + push + CI** — `git commit -am "feat(history): file version 2 with device names; clear/remove/prune APIs"`, push, `gh workflow run … --ref feature/settings-redesign`, `gh run watch <id> -R XeusLEE/AirBattery --exit-status` → success.
- [ ] **Step 5: Çalışma zamanı doğrulaması** — CI DMG'sini indir; `defaults export com.lihaoyun6.AirBattery "$SCRATCH/t1/defaults-backup.plist"`; `cp ~/Library/Application\ Support/AirBattery/battery-history.json "$SCRATCH/t1/history-v1-backup.json"` (sürüm 1 dosya); kullanıcı uygulamasını kapat, test derlemesini `open`, 90 sn bekle; `python3 -I` ile dosyayı oku: `version == 2`, `names` en az bir giriş, örnek sayıları yedektekinden az değil. Test derlemesini kapat, `/Applications/AirBattery.app`'i aç. (Yedek plist Task 7'ye kadar saklanır.)

---

### Task 2: Ayar fonksiyonları, varsayılanlar, tahmin anahtarı, URL komutu, pencere konumu

**Files:**
- Modify: `AirBattery/Supports/Supports.swift` (`let menuBarCriticalThreshold = 10` satırı)
- Modify: `AirBattery/ViewModel/BatteryView.swift` (`lowDevice` atamaları, ek rengi)
- Modify: `AirBattery/ViewModel/ContentView.swift` (`cardEstimate`, `openSettingPanel`)
- Modify: `AirBattery/Supports/AirBatteryApp.swift` (`ud.register`, `handleURLEvent`)

**Interfaces:**
- Produces: `func menuBarCriticalThreshold() -> Int` (ud, kayıtlı varsayılan 10) — eski `let` kaldırılır; `func menuBarLowSuffixEnabled() -> Bool` (`ud.bool(forKey: "menuBarLowSuffix")`); `func showEstimateEnabled() -> Bool` (`ud.bool(forKey: "showEstimate")`) — üçü Supports.swift'te, `staleAfterMinutes` yanında.

- [ ] **Step 1: Supports.swift** — üç fonksiyon; `menuBarCriticalThreshold` referansları (BatteryView.swift) çağrıya dönüşür.
- [ ] **Step 2: Varsayılanlar** — `applicationWillFinishLaunching` `ud.register` sözlüğüne: `"showEstimate": true, "menuBarLowSuffix": true, "menuBarCriticalThreshold": 10, "alertDefaultLow": 20, "alertDefaultFull": 80, "alertDefaultSound": true`.
- [ ] **Step 3: BatteryView.swift** — `onAppear` ve timer başındaki iki atama `lowDevice = menuBarLowSuffixEnabled() ? lowestLowDevice(in: AirBatteryModel.getAll()) : nil`; ek rengi `d.batteryLevel <= menuBarCriticalThreshold()`.
- [ ] **Step 4: ContentView.swift** — `cardEstimate(for:)` (veya eşdeğer) başına `guard showEstimateEnabled() else { return .none }`; `openSettingPanel()` sonuna:
  ```swift
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
      guard let w = NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "").contains("Settings") || $0.contentView?.className.contains("SettingsView") == true }) ?? NSApp.keyWindow else { return }
      w.setFrameAutosaveName("AirBatterySettingsWindow")
      if !w.setFrameUsingName("AirBatterySettingsWindow") { w.center() }
      w.makeKeyAndOrderFront(nil); w.orderFrontRegardless()
  }
  ```
- [ ] **Step 5: URL** — `handleURLEvent` switch'ine `case "showsettings": DispatchQueue.main.async { openSettingPanel() }`.
- [ ] **Step 6: Commit + push + CI** — `git commit -am "feat(settings): adjustable critical threshold, badge and estimate switches, showsettings URL, window placement"` → CI success. Çalışma zamanı kontrolü yok (Task 7).

---

### Task 3: KnownDevice modeli ve birleştirme

**Files:**
- Create: `AirBattery/ViewModel/DevicesSettingsView.swift`
- Modify: `AirBattery.xcodeproj/project.pbxproj` (betikle, `--group ViewModel`)

**Interfaces:**
- Consumes: `Device`, `btAlert`, `BatteryHistoryStore` API (Task 1).
- Produces:
  ```swift
  struct KnownDevice: Identifiable, Equatable {
      var id: String { name }
      let name: String; let deviceID: String?; let deviceType: String?
      let isOnline: Bool; let batteryLevel: Int?; let isCharging: Bool
      let lastSeen: TimeInterval?
      var isHidden: Bool; var isListed: Bool; var isPinned: Bool; var alert: btAlert?
      let sampleCount: Int
  }
  enum KnownDeviceList {
      static func build(current: [Device], historyNames: [String: String], lastSeen: [String: TimeInterval],
                        sampleCounts: [String: Int], blackList: [String], blocked: [String],
                        pinned: [String], alerts: [btAlert]) -> [KnownDevice]
      static func load() -> [KnownDevice]   // yukarıdakini AirBatteryModel.getAll(noFilter: true), store ve ud'den besler
  }
  ```

- [ ] **Step 1: Dosyayı yaz** — `build` spec §8.1'in dört kuralını uygular: (1) `current` içinde `deviceID != "@MacInternalBattery"` olanlar (ad çakışırsa ilk) → `isOnline: true`, `batteryLevel: hasBattery ? level : nil`, `isCharging: isCharging != 0`, `lastSeen: nil`; (2) `historyNames` içinde (1)'de adı geçmeyen id'ler → `isOnline: false`, `lastSeen: lastSeen[id]`, `deviceType: nil`; (3) dört listedeki adlardan kalanlar → `deviceID: nil`, `lastSeen: nil`, `sampleCount: 0`; bayraklar: `isHidden = blackList.contains(name)`, `isListed = blocked.contains(name)`, `isPinned = pinned.contains(name)`, `alert = alerts.first { $0.name == name }`; `sampleCount = sampleCounts[deviceID] ?? 0`; sıralama (4): çevrimiçi ada göre (`localizedCaseInsensitiveCompare`), çevrimdışı `lastSeen` azalan, hiç görülmemiş ada göre. `load()` ud okumaları `as? [String] ?? []` ve `ud.get(objectType: [btAlert].self, forKey: "alertList") ?? []`.
- [ ] **Step 2: Traces** — rapor dosyasına üç el izi: (a) çevrimiçi "A" + geçmişte "B"(id b, 3 gün önce) + blackList ["C"] → [A, B, C] sıralı; (b) geçmişte adı "A" olan id ile çevrimiçi "A" → tek kayıt, `sampleCount` geçmişten; (c) Mac `@MacInternalBattery` dışlanır.
- [ ] **Step 3: pbxproj** — `python3 scripts/pbxproj_edit.py add-source AirBattery/ViewModel/DevicesSettingsView.swift --group ViewModel && plutil -lint AirBattery.xcodeproj/project.pbxproj`.
- [ ] **Step 4: Commit + push + CI** — `git add -A && git commit -m "feat(settings): KnownDevice model and list builder"` → CI success.

---

### Task 4: Cihazlar sekmesi görünümü

**Files:**
- Modify: `AirBattery/ViewModel/DevicesSettingsView.swift`

**Interfaces:**
- Consumes: Task 3, `getDeviceIcon(_:)` (bir `Device` kurmak için `Device(deviceID:deviceType:deviceName:batteryLevel:isCharging:lastUpdate:)` yeterli; `deviceType` nil ise `"generic"` görseli… mevcut varlık adı yoksa `Image(systemName: "questionmark.circle")`), `refeshPinnedBar(unpin:)`, `AirBatteryModel.hideDevice/unhideDevice/Devices`, `createAlert`, `lastSeenText(sinceSeconds:)`, `SSteper`, `SToggle`, `SPicker`, `SButton`, `SGroupBox`, `SForm`.
- Produces: `struct DevicesTab: View` (560 pt genişlik, `.frame(width: 560)`), `struct DeviceDetailView: View { let device: KnownDevice; let allowlistMode: Bool; let onChange: () -> Void }`.

- [ ] **Step 1: `DevicesTab`** — `@State devices: [KnownDevice]`, `@State selection: String?`, `@AppStorage("whitelistMode")`, `@AppStorage("alertDefaultLow")`, `("alertDefaultFull")`, `("alertDefaultSound")`. Üst satır: `Text(String(format: "New device alert defaults: low %d%%, full %d%%".local, low, full))` 11 pt `.secondary` + `Edit` düğmesi → `.popover` içinde `SSteper("Default low", 1…99)`, `SSteper("Default full", 1…100)`, `SToggle("Play sound")`. Orta: `HStack(spacing: 10)`: sol `List(devices, selection: $selection)` `.frame(width: 210, height: 208)`; satır = simge 16 pt + `Text(name)` `.lineLimit(1)` + ek (`hidden`/`blocked`/`not allowed`/`offline`) 10.5 pt `.secondary`; boşsa `Text("No devices yet".local)` `.secondary` ortada; sağ `DeviceDetailView` seçili ise, değilse `Text("Select a device".local)` `.secondary`. Alt şerit: `TextField("Block by name…".local)` + `Add` düğmesi (boş ya da `blockedDevices` içinde varsa `disabled`); `Remove unseen devices` düğmesi → `pruneUnseen(olderThan: 7*86400, keeping: Set(blackList+blocked+pinned+alert adları))` → `createAlert(title: "Remove unseen devices".local, message: String(format: "Removed %d devices".local, n), button1: "OK".local).runModal()`; sağda `SToggle("Allowlist Mode", isOn: $whitelistMode)`. `onAppear` ve `.onReceive(dockTimer)` → `devices = KnownDeviceList.load()`; `onChange` kapanışı da aynı. Seçim ada göre korunur (ad listede yoksa `nil`).
- [ ] **Step 2: `DeviceDetailView`** — `SForm(spacing: 10, noSpacer: true)` içinde: başlık `HStack` (simge 24, ad 13 semibold, altında çevrimiçi ise `"\(level)%"` + şarjda `bolt.fill`, değilse `lastSeen` varsa (`now - lastSeen < 86400` ise `lastSeenText`, değilse `DateFormatter` `.short/.short`) `String(format: "Last seen %@".local, …)`, yoksa `"Never seen".local`; hepsi `.secondary` 11 pt); `SGroupBox`: `SPicker("Visibility", selection: visibilityBinding, style: .segmented) { Text("Show").tag(false); Text("Hide").tag(true) }` → `blackList` ekle/çıkar + `AirBatteryModel.hideDevice/unhideDevice(name)`; `SToggle(allowlistMode ? "Allowed" : "Blocked", isOn: listedBinding)` → `blockedDevices` ekle/çıkar; engellenince (`!allowlistMode && isOn`) ya da izin kaldırılınca (`allowlistMode && !isOn`) `AirBatteryModel.Devices.removeAll { $0.deviceName == device.name }`; `SToggle("Pin to menu bar", isOn: pinnedBinding).disabled(!device.isOnline)` → `pinnedList` güncelle, açılınca `refeshPinnedBar()`, kapanınca `refeshPinnedBar(unpin: name)`; `SGroupBox`: `SToggle("Low battery alert", isOn: lowOnBinding)` + `SSteper("", value: lowBinding, min: 1, max: 99).disabled(!lowOn)`; `SToggle("Full battery alert", …)` + `SSteper(min: 1, max: 100)`; `SToggle("Play sound", isOn: soundBinding)` (`lowSound == fullSound == value`); `SButton("Delete history for this device", buttonTitle: "Clear") { remove(deviceID:) }` `.disabled(device.deviceID == nil || device.sampleCount == 0)`. Uyarı yazımı: `alertList` okunur, `name` kaydı yoksa `btAlert(name:, full: alertDefaultFull, fullOn: false, fullSound: alertDefaultSound, low: alertDefaultLow, lowOn: false, lowSound: alertDefaultSound)` ile başlanır, alan güncellenir; sonuçta `lowOn == false && fullOn == false` ise kayıt silinir; `ud.set(object:forKey: "alertList")`; her yazımdan sonra `onChange()`.
- [ ] **Step 3: Commit + push + CI** — `git commit -am "feat(settings): Devices tab with list, detail panel, alerts and blocklist"` → CI success.

---

### Task 5: SettingsView yeniden yazımı (TabView, Genel, Görünüm, Keşif, Debug)

**Files:**
- Modify: `AirBattery/ViewModel/SettingsView.swift` (tamamı; `GeneralView/NearbilityView/NearcastView/DisplayView/WidgetView/BlacklistView/DebugView` kaldırılır, içerikleri taşınır)

**Interfaces:**
- Consumes: `DevicesTab` (Task 4), `BatteryHistoryStore.summary()/clear()` (Task 1), mevcut `UpdaterSettingsView`, `CheckForUpdatesView`, `CommandLineTool`, `netcastService`, `SForm/SGroupBox/SToggle/SPicker/SSteper/SField/SButton`.
- Produces: `enum SettingsTab: String, CaseIterable { case general, appearance, devices, discovery, debug }`; `struct SettingsView: View`; `struct GeneralTab`, `AppearanceTab`, `DiscoveryTab`, `DebugTab`.

- [ ] **Step 1: Kök** — `@State tab: SettingsTab` başlangıcı `SettingsTab(rawValue: ud.string(forKey: "settingsTab") ?? "") ?? .general` (`.debug` yalnızca `showDebug` ise, değilse `.general`); `TabView(selection: $tab)`; her sekme `.tabItem { Label("General", systemImage: "gearshape") }` / `"Appearance"`–`"paintbrush"` / `"Devices"`–`"laptopcomputer.and.iphone"` / `"Discovery"`–`"antenna.radiowaves.left.and.right"` / `showDebug` ise `"Debug"`–`"ladybug"`; `.tag(SettingsTab.x)`; her sekme kökü `.frame(width: 560)`; `navigationTitle` yok; eski `.frame(width: 600, height: 440)` yok.
- [ ] **Step 2: `GeneralTab`** — `SForm` içinde `SGroupBox("Startup")` (mevcut üç denetim ve `onChange` gövdeleri aynen), `SGroupBox("Estimate & Data")`: `SToggle("Show remaining time estimate", isOn: $showEstimate)` (`@AppStorage("showEstimate")`), `SItem(label: "…")` yerine `HStack { Text(String(format: "History: %d devices, %@".local, count, ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))).foregroundColor(.secondary); Spacer(); Button("Clear History".local) { … } }` (onay: `createAlert(title: "Clear battery history?".local, message: "This removes the collected samples for all devices. Estimates start over.".local, button1: "Clear".local, button2: "Cancel".local).runModal() == .alertFirstButtonReturn` → `clear()`, sayaç yenilenir), `SButton("Data Folder", buttonTitle: "Open") { NSWorkspace.shared.open(ncFolder.deletingLastPathComponent()) }`; `SGroupBox("Update")` + sürüm etiketi / 10 tıklama aynen.
- [ ] **Step 3: `AppearanceTab`** — `SGroupBox("Menu Bar")` altı denetim aynen; `SGroupBox("Low Device Badge")`: `SToggle("Show low devices in the menu bar", isOn: $menuBarLowSuffix)`, `SSteper("Low threshold", value: $lowThreshold, min: 5, max: 50)`, `SSteper("Critical threshold", value: $criticalThreshold, min: 5, max: 30)`; kenetleme `.onChange(of: lowThreshold) { v in if criticalThreshold > v { criticalThreshold = v } }` ve `.onChange(of: criticalThreshold) { v in if v > lowThreshold { lowThreshold = v } }`; anahtar kapalıyken iki stepper `.disabled(true)`; `SGroupBox("Dock")` ve `SGroupBox("Widget")` aynen (Widget'ın `onAppear`/`dockTimer` dahil).
- [ ] **Step 4: `DiscoveryTab`** — `SGroupBox("Scanner")`, `SGroupBox("Others")`, `SGroupBox("Nearcast")`, `SGroupBox("Peer Info")` mevcut gövdeleriyle aynen (uyarı `createAlert` çağrıları dahil).
- [ ] **Step 5: `DebugTab`** — mevcut `DebugView` gövdesi, `Data Folder` düğmesi çıkarılmış; `Hide Debug Menu` düğmesi `showDebug = false` ve `tab = .general`.
- [ ] **Step 6: Commit + push + CI** — `git commit -am "feat(settings): four-tab settings window with content-sized height"` → CI success.

---

### Task 6: Yerelleştirme

**Files:**
- Modify: `AirBattery/zh-Hans.lproj/Localizable.strings`, `AirBattery/zh-Hant.lproj/Localizable.strings`, `AirBattery/tr.lproj/Localizable.strings`

- [ ] **Step 1: Anahtarlar** — aşağıdaki satırlar üç dosyanın sonuna (zaten var olan anahtar eklenmez; `grep -c '^"<key>" = '` ile kontrol):

| Key | zh-Hans | zh-Hant | tr |
|---|---|---|---|
| `Devices` | 设备 | 裝置 | Cihazlar |
| `Discovery` | 发现 | 探索 | Keşif |
| `Estimate & Data` | 估算与数据 | 估算與資料 | Tahmin ve Veri |
| `Show remaining time estimate` | 显示剩余时间估算 | 顯示剩餘時間估算 | Kalan süre tahminini göster |
| `History: %d devices, %@` | 历史记录：%d 台设备，%@ | 歷史記錄：%d 台裝置，%@ | Geçmiş: %d cihaz, %@ |
| `Clear History` | 清除历史记录 | 清除歷史記錄 | Geçmişi Temizle |
| `Clear battery history?` | 要清除电池历史记录吗？ | 要清除電池歷史記錄嗎？ | Pil geçmişi temizlensin mi? |
| `This removes the collected samples for all devices. Estimates start over.` | 这将删除所有设备已收集的样本，估算将重新开始。 | 這將刪除所有裝置已收集的樣本，估算將重新開始。 | Tüm cihazlar için toplanan örnekler silinir. Tahminler sıfırdan başlar. |
| `Clear` | 清除 | 清除 | Temizle |
| `Low Device Badge` | 低电量设备标记 | 低電量裝置標記 | Düşük Cihaz Eki |
| `Show low devices in the menu bar` | 在菜单栏显示低电量设备 | 在選單列顯示低電量裝置 | Düşük cihazları menü çubuğunda göster |
| `Low threshold` | 低电量阈值 | 低電量閾值 | Düşük eşiği |
| `Critical threshold` | 严重低电量阈值 | 嚴重低電量閾值 | Kritik eşik |
| `No devices yet` | 尚无设备 | 尚無裝置 | Henüz cihaz yok |
| `Select a device` | 请选择一台设备 | 請選擇一台裝置 | Bir cihaz seç |
| `Visibility` | 显示方式 | 顯示方式 | Görünürlük |
| `Show` | 显示 | 顯示 | Göster |
| `Hide` | 隐藏 | 隱藏 | Gizle |
| `Blocked` | 已屏蔽 | 已封鎖 | Engelli |
| `Allowed` | 已允许 | 已允許 | İzinli |
| `hidden` | 已隐藏 | 已隱藏 | gizli |
| `blocked` | 已屏蔽 | 已封鎖 | engelli |
| `not allowed` | 未允许 | 未允許 | izinsiz |
| `offline` | 离线 | 離線 | çevrimdışı |
| `Pin to menu bar` | 固定到菜单栏 | 釘選到選單列 | Menü çubuğuna raptiyele |
| `Low battery alert` | 低电量提醒 | 低電量提醒 | Düşük pil uyarısı |
| `Full battery alert` | 充满提醒 | 充滿提醒 | Dolu pil uyarısı |
| `Play sound` | 播放声音 | 播放聲音 | Ses çal |
| `Delete history for this device` | 删除此设备的历史记录 | 刪除此裝置的歷史記錄 | Bu cihazın geçmişini sil |
| `Block by name…` | 按名称屏蔽… | 依名稱封鎖… | Ada göre engelle… |
| `Add` | 添加 | 加入 | Ekle |
| `Remove unseen devices` | 移除长期未见的设备 | 移除長期未見的裝置 | Görülmeyen cihazları kaldır |
| `Removed %d devices` | 已移除 %d 台设备 | 已移除 %d 台裝置 | %d cihaz kaldırıldı |
| `Last seen %@` | 最后出现：%@ | 最後出現：%@ | Son görülme: %@ |
| `Never seen` | 从未出现 | 從未出現 | Hiç görülmedi |
| `New device alert defaults: low %d%%, full %d%%` | 新设备提醒默认值：低 %d%%，满 %d%% | 新裝置提醒預設值：低 %d%%，滿 %d%% | Yeni cihaz uyarı varsayılanları: düşük %%%d, dolu %%%d |
| `Edit` | 编辑 | 編輯 | Düzenle |
| `Default low` | 默认低电量 | 預設低電量 | Varsayılan düşük |
| `Default full` | 默认充满 | 預設充滿 | Varsayılan dolu |

- [ ] **Step 2: Doğrulama** — `plutil -lint` üç dosya → OK; `python3 -I` ile: dosya içi çift anahtar yok; `set(tr) ⊇ set(zhHans)`; her yeni tr değerindeki `%` belirteç dizisi anahtarınkiyle aynı (yalnızca `%%`'nin yeri değişebilir).
- [ ] **Step 3: Commit + push + CI** — `git commit -am "l10n: settings redesign strings for zh and tr"` → CI success (`Copy strings` adımı dahil).

---

### Task 7: Çalışma zamanı doğrulaması ve ekran görüntüleri

**Files:** yok (yalnızca rapor ve PNG'ler)

- [ ] **Step 1: Hazırlık** — son yeşil CI DMG'sini indir, `.app`'i scratchpad'e kopyala, karantinayı kaldır. `defaults export com.lihaoyun6.AirBattery "$SCRATCH/t7/defaults-backup.plist"` (Task 1 yedeği varsa onu da koru). Kullanıcı uygulamasını kapat.
- [ ] **Step 2: Sekmeler** — her sekme için: `defaults write com.lihaoyun6.AirBattery settingsTab <general|appearance|discovery|devices>`, test derlemesini `open`, 15 sn, `open -a <app> "airbattery://showsettings"`, 2 sn, `screencapture -x "$SCRATCH/t7/settings-<tab>.png"`, uygulamayı kapat. Kontrol: pencere genişliği 560, yükseklik sekmeye göre farklı (dört PNG'de pencere yüksekliklerini ölç ve raporla), alt boşluk ya da kesik içerik yok.
- [ ] **Step 3: Cihazlar sekmesi dolu** — `defaults write com.lihaoyun6.AirBattery blackList -array "Magic Mouse"`, `pinnedList -array "<gerçek bir cihaz adı>"`, `blockedDevices -array "Komsunun kulakligi"`, `alertList` (mevcut yardımcı biçimi: `ud.set(object:)` JSON Data kullanır — bu yüzden bunun yerine uygulamayı açıp ekran görüntüsünde yalnızca gizli/raptiye/engelli durumlarını doğrula); `settingsTab devices`; ekran görüntüsü: liste satırlarında `· hidden`, `· blocked` ekleri, seçili cihaz ayrıntısı (başlık, görünürlük, engel, raptiye, uyarı satırları, geçmiş silme düğmesi).
- [ ] **Step 4: Davranış kontrolleri (defaults ile)** — Görünüm sekmesi: `menuBarLowThreshold 8` yazıp `settingsTab appearance` ile açılınca `menuBarCriticalThreshold` değerinin otomatik 8'e kenetlendiğini `defaults read` ile doğrula (kenetleme `onChange`'de olduğundan uygulama içi değişiklik gerekir — bunun yerine kodu oku ve raporla; CI derlemesi yeterli). Review Focus 3 için: `blockedDevices` içindeki ad çevrimiçi bir cihazsa `airbattery://showpopover` ekran görüntüsünde görünmemeli.
- [ ] **Step 5: Boş durum** — `defaults delete` ile dört listeyi temizle, Bluetooth cihazları zaten çevrimiçi olduğu için liste boş olmaz; `No devices yet`/`Select a device` yer tutucuları kod okumasıyla doğrulanır ve raporda belirtilir.
- [ ] **Step 6: Geri yükleme** — `defaults delete com.lihaoyun6.AirBattery settingsTab`; `defaults import com.lihaoyun6.AirBattery "$SCRATCH/t7/defaults-backup.plist"`; `defaults read … pinnedList` yedekle aynı; `/Applications/AirBattery.app`'i aç ve `ps` ile doğrula. Zorunlu.

---

### Task 8: Kapanış

- [ ] **Step 1:** Tam dal incelemesi (subagent-driven-development kapanışı), düzeltme dalgası, DMG'yi oturum klasörüne koy.
- [ ] **Step 2:** `superpowers:finishing-a-development-branch`: dal **main'e birleştirilmez**; kullanıcı sabah karar verir. Hafıza notu güncellenir.
