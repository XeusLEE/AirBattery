# Popover Redesign, Remaining-Time Estimate, Menu Bar Low-Device Suffix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kart tabanlı popover, her cihaz için yerel geçmişten kalan süre tahmini ve menü çubuğu ikonuna düşük cihaz eki.

**Architecture:** Saf Swift tahmin motoru `Packages/BatteryEstimator` altında SwiftPM paketi olarak yazılır ve `swift test` ile yerelde test edilir; aynı kaynak dosyalar Xcode uygulama hedefine doğrudan eklenir (paket bağlanmaz). Uygulama tarafında `BatteryHistoryStore` örnekleri toplar ve JSON'a yazar; `AirBatteryModel.updateHook` closure'ı ile beslenir. Arayüz `DeviceCardView` etrafında yeniden kurulur; Dock penceresi yüksekliği `PopoverLayout.height(...)` tek fonksiyonundan gelir.

**Tech Stack:** Swift 5 dil modu, SwiftUI + AppKit, macOS 11.0 hedef, XCTest (SwiftPM), GitHub Actions macos-15 / Xcode 16.4. Yerelde Xcode yok: yalnızca `swift test`; uygulama derlemesi CI'da.

**Spec:** `docs/superpowers/specs/2026-11-09-popover-redesign-design.md`

## Global Constraints

- Deployment target macOS 11.0: `Color(nsColor:)`, `.regularMaterial`, iki parametreli `.onChange` **kullanılmaz**; 12/13/14 API'leri `#available` ile korunur. Mevcut `Color(NSColor)` ve `Color.blackWhite/.myGreen/.myYellow/.myRed/.darkMyRed` (asset sembolleri) kullanılır.
- `AirBatteryModel.swift`, `InternalBattery.swift`, `Supports.swift` abt ve widget hedeflerinde de derlenir: bu üç dosyaya yeni tip bağımlılığı **eklenmez**.
- Yeni SPM bağımlılığı yok. pbxproj yalnızca `scripts/pbxproj_edit.py` ile değiştirilir; her değişiklikten sonra `plutil -lint` geçmeli.
- Kullanıcıya görünen her yeni metin `"English key".local` ile geçer; anahtarlar Task 9'daki tabloya aynen uyar.
- Sabitler: popover genişliği 352; kart yüksekliği 68, kart aralığı 5, yatay kenar 10, başlık 26, bölüm başlığı 18, gizli satır 34, dikey dolgu 8, azami yükseklik 640; menü çubuğu eki +40 pt; eşikler 20 (düşük) / 10 (kritik); eski veri uyarısı 10 dk.
- Tahmin sabitleri: kalp atışı 30 dk, saklama 7 gün, en fazla 300 örnek, en az 10 dk ve 2 puan, yükselme toleransı 3, aykırı değer 25 puan/10 dk, azami tahmin 30 gün.
- Çalışma dalı `feature/popover-redesign`; her görev kendi commit'i; CI gerektiren görevler push edilir ve `gh run watch` ile yeşil görülür.

## Review Focus

1. **Tek bozuk okuma** (100 → 3 bir dakika içinde) saçma bir "~5 dk" tahmini üretmemeli → Task 1 `testIgnoresOutlierJump`.
2. **Saat geriye gitti / uyku** → negatif süre yok, faz kesilir → Task 3 `testPhaseCutsOnBackwardTime`, `testGapDoesNotCutWhenTrendHolds`.
3. **Geçmiş dosyası bozuk veya yazılamıyor** → uygulama açılır, tahmin `.none` → Task 5 doğrulama adımı (çöp dosya ile açılış).
4. **`hasBattery == false` cihaz** (Nearcast'teki masaüstü Mac) → kartta çubuk/yüzde/etiket yok, sadece ad ve son görülme → Task 6 davranış listesi + Task 7 Nearcast doğrulaması.
5. **Çok uzun ad / çok cihaz** → tek satır üç nokta; yükseklik 640'ı aşınca kaydırma → Task 6 `lineLimit(1)`, Task 7 `PopoverLayout` ve `ScrollView` doğrulaması.

---

### Task 0: Dal ve push

**Files:** yok

- [ ] **Step 1:** `git push origin main` (spec commit'i `de8f48c` GitHub'a gitsin), ardından `git switch -c feature/popover-redesign`.
- [ ] **Step 2:** `git status --short` boş, `git branch --show-current` → `feature/popover-redesign`.

---

### Task 1: BatteryEstimator paketi ve DeviceHistory.record

**Files:**
- Create: `Packages/BatteryEstimator/Package.swift`
- Create: `Packages/BatteryEstimator/Sources/BatteryEstimator/BatterySample.swift`
- Test: `Packages/BatteryEstimator/Tests/BatteryEstimatorTests/DeviceHistoryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct BatterySample: Codable, Equatable { public let t: TimeInterval; public let l: Int; public let c: Bool; public init(t:l:c:) }
  public struct DeviceHistory: Codable, Equatable {
      public static let heartbeatInterval: TimeInterval = 1800
      public static let retention: TimeInterval = 7 * 86400
      public static let maxSamples = 300
      public static let outlierDelta = 25
      public static let outlierWindow: TimeInterval = 600
      public private(set) var samples: [BatterySample]
      public init(samples: [BatterySample] = [])
      @discardableResult public mutating func record(level: Int, charging: Bool, at time: TimeInterval) -> Bool
  }
  ```

- [ ] **Step 1: Package.swift** — `// swift-tools-version:5.9`, platforms `[.macOS(.v11)]`, library product `BatteryEstimator`, target `BatteryEstimator`, test target `BatteryEstimatorTests` (depends on it), `swiftLanguageVersions: [.v5]`.

- [ ] **Step 2: Başarısız testleri yaz** (`DeviceHistoryTests.swift`):

```swift
final class DeviceHistoryTests: XCTestCase {
    func testFirstSampleIsRecorded() {
        var h = DeviceHistory()
        XCTAssertTrue(h.record(level: 80, charging: false, at: 1000))
        XCTAssertEqual(h.samples, [BatterySample(t: 1000, l: 80, c: false)])
    }
    func testUnchangedReadingWithinHeartbeatIsDropped() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        XCTAssertFalse(h.record(level: 80, charging: false, at: 1000 + 1799))
        XCTAssertEqual(h.samples.count, 1)
    }
    func testUnchangedReadingAfterHeartbeatIsRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        XCTAssertTrue(h.record(level: 80, charging: false, at: 1000 + 1800))
        XCTAssertEqual(h.samples.count, 2)
    }
    func testLevelChangeIsRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        XCTAssertTrue(h.record(level: 79, charging: false, at: 1060))
    }
    func testChargingChangeIsRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 80, c: false)])
        XCTAssertTrue(h.record(level: 80, charging: true, at: 1060))
    }
    func testIgnoresOutlierJump() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 100, c: false)])
        XCTAssertFalse(h.record(level: 3, charging: false, at: 1060))      // 97 puan, 1 dk: aykırı
        XCTAssertTrue(h.record(level: 3, charging: false, at: 1000 + 600)) // 10 dk sonra kabul
    }
    func testOutlierAllowedWhenChargingStateChanges() {
        var h = DeviceHistory(samples: [BatterySample(t: 1000, l: 100, c: true)])
        XCTAssertTrue(h.record(level: 3, charging: false, at: 1060))
    }
    func testPrunesOlderThanRetention() {
        var h = DeviceHistory(samples: [BatterySample(t: 0, l: 90, c: false)])
        h.record(level: 89, charging: false, at: 7 * 86400 + 1)
        XCTAssertEqual(h.samples.map { $0.l }, [89])
    }
    func testCapsAtMaxSamples() {
        var h = DeviceHistory()
        for i in 0..<305 { h.record(level: 50, charging: false, at: TimeInterval(i * 1800)) }   // her 30 dk kalp atışı
        XCTAssertEqual(h.samples.count, 300)
        XCTAssertEqual(h.samples.first?.t, TimeInterval(5 * 1800))
    }
    func testBackwardTimeIsStillRecorded() {
        var h = DeviceHistory(samples: [BatterySample(t: 5000, l: 80, c: false)])
        XCTAssertTrue(h.record(level: 80, charging: false, at: 4000))
    }
}
```

- [ ] **Step 3: Çalıştır, başarısız olduğunu gör** — `cd Packages/BatteryEstimator && swift test 2>&1 | tail -5` → derleme hatası (`DeviceHistory` yok).

- [ ] **Step 4: `BatterySample.swift` içinde tipleri yaz.** `record` kuralları sırayla: geçmiş boşsa kaydet; `time < last.t` ise kaydet; `charging != last.c` ise kaydet; `abs(level - last.l) >= outlierDelta && time - last.t < outlierWindow` ise **kaydetme** (false); `level != last.l` ise kaydet; `time - last.t >= heartbeatInterval` ise kaydet; aksi halde false. Kaydettikten sonra `t < time - retention` olanları ve sayı 300'ü aşınca en eskileri at.

- [ ] **Step 5: Testler geçsin** — `swift test 2>&1 | tail -3` → `Executed 10 tests, with 0 failures`.

- [ ] **Step 6: Commit** — `git add Packages && git commit -m "feat(estimator): add BatteryEstimator package with DeviceHistory sampling rules"`.

---

### Task 2: DurationParts yuvarlama

**Files:**
- Create: `Packages/BatteryEstimator/Sources/BatteryEstimator/DurationParts.swift`
- Test: `Packages/BatteryEstimator/Tests/BatteryEstimatorTests/DurationPartsTests.swift`

**Interfaces:**
- Produces: `public struct DurationParts: Equatable { public let days: Int; public let hours: Int; public let minutes: Int; public static func from(seconds: TimeInterval) -> DurationParts }`

- [ ] **Step 1: Başarısız testleri yaz:**

```swift
final class DurationPartsTests: XCTestCase {
    func testUnderAnHourRoundsToFiveMinutes() {
        XCTAssertEqual(DurationParts.from(seconds: 53 * 60), DurationParts(days: 0, hours: 0, minutes: 55))
        XCTAssertEqual(DurationParts.from(seconds: 90), DurationParts(days: 0, hours: 0, minutes: 5))      // en az 5
        XCTAssertEqual(DurationParts.from(seconds: 58 * 60), DurationParts(days: 0, hours: 1, minutes: 0)) // 60 → 1 sa
    }
    func testUnderADayGivesHoursAndRoundedMinutes() {
        XCTAssertEqual(DurationParts.from(seconds: 3 * 3600 + 12 * 60), DurationParts(days: 0, hours: 3, minutes: 10))
        XCTAssertEqual(DurationParts.from(seconds: 3 * 3600 + 2 * 60), DurationParts(days: 0, hours: 3, minutes: 0))
        XCTAssertEqual(DurationParts.from(seconds: 23 * 3600 + 59 * 60), DurationParts(days: 1, hours: 0, minutes: 0))
    }
    func testDayOrMoreGivesWholeDays() {
        XCTAssertEqual(DurationParts.from(seconds: 6.4 * 86400), DurationParts(days: 6, hours: 0, minutes: 0))
        XCTAssertEqual(DurationParts.from(seconds: 86400), DurationParts(days: 1, hours: 0, minutes: 0))
    }
}
```

- [ ] **Step 2: Çalıştır, başarısız** — `swift test --filter DurationPartsTests 2>&1 | tail -3`.
- [ ] **Step 3: `from(seconds:)` yaz.** `s < 3600`: `m = max(5, Int((s/60/5).rounded()) * 5)`, 60 ise `(0,1,0)`. `s < 86400`: `tm = Int((s/60/5).rounded()) * 5`, `(0, tm/60, tm%60)`, saat 24 olursa `(1,0,0)`. Aksi: `(max(1, Int((s/86400).rounded())), 0, 0)`.
- [ ] **Step 4: Geçsin** — `swift test 2>&1 | tail -3` → 0 failures.
- [ ] **Step 5: Commit** — `git commit -am "feat(estimator): add DurationParts rounding"`.

---

### Task 3: Estimator — faz çıkarma ve tahmin

**Files:**
- Create: `Packages/BatteryEstimator/Sources/BatteryEstimator/Estimator.swift`
- Test: `Packages/BatteryEstimator/Tests/BatteryEstimatorTests/EstimatorTests.swift`

**Interfaces:**
- Consumes: `BatterySample`, `DeviceHistory` (Task 1).
- Produces:
  ```swift
  public enum Estimate: Equatable { case none; case timeToEmpty(TimeInterval); case timeToFull(TimeInterval) }
  public enum Estimator {
      public static let minimumSpan: TimeInterval = 600
      public static let minimumLevelDelta = 2
      public static let riseTolerance = 3
      public static let maximumEstimate: TimeInterval = 30 * 86400
      public static func phase(of samples: [BatterySample]) -> [BatterySample]   // kronolojik, en yeni faz
      public static func estimate(_ history: DeviceHistory) -> Estimate
  }
  ```

- [ ] **Step 1: Başarısız testleri yaz:**

```swift
final class EstimatorTests: XCTestCase {
    private func s(_ t: TimeInterval, _ l: Int, _ c: Bool = false) -> BatterySample { BatterySample(t: t, l: l, c: c) }

    func testPhaseCutsOnChargingChange() {
        let p = Estimator.phase(of: [s(0, 50, true), s(600, 52, true), s(1200, 51), s(1800, 50)])
        XCTAssertEqual(p, [s(1200, 51), s(1800, 50)])
    }
    func testPhaseCutsOnRiseOfThreeWhileDischarging() {
        let p = Estimator.phase(of: [s(0, 60), s(600, 59), s(1200, 62), s(1800, 61)])
        XCTAssertEqual(p, [s(1200, 62), s(1800, 61)])
    }
    func testSmallRiseIsToleratedWhileDischarging() {
        let p = Estimator.phase(of: [s(0, 60), s(600, 59), s(1200, 61), s(1800, 58)])
        XCTAssertEqual(p.count, 4)
    }
    func testPhaseCutsOnDropWhileCharging() {
        let p = Estimator.phase(of: [s(0, 40, true), s(600, 45, true), s(1200, 44, true), s(1800, 46, true)])
        XCTAssertEqual(p, [s(1200, 44, true), s(1800, 46, true)])
    }
    func testPhaseCutsOnBackwardTime() {
        let p = Estimator.phase(of: [s(5000, 60), s(4000, 59), s(4600, 58)])
        XCTAssertEqual(p, [s(4000, 59), s(4600, 58)])
    }
    func testGapDoesNotCutWhenTrendHolds() {
        let p = Estimator.phase(of: [s(0, 98), s(8 * 3600, 98), s(16 * 3600, 97)])   // 8 saat uyku
        XCTAssertEqual(p.count, 3)
    }
    func testInsufficientDataGivesNone() {
        XCTAssertEqual(Estimator.estimate(DeviceHistory(samples: [s(0, 80)])), .none)
        XCTAssertEqual(Estimator.estimate(DeviceHistory(samples: [s(0, 80), s(300, 78)])), .none)   // 5 dk < 10 dk
        XCTAssertEqual(Estimator.estimate(DeviceHistory(samples: [s(0, 80), s(1200, 79)])), .none)  // 1 puan < 2
    }
    func testDischargeEstimate() {
        // 10 puan / 1 saat, şu an 50 → 5 saat
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 60), s(1800, 55), s(3600, 50)]))
        XCTAssertEqual(e, .timeToEmpty(5 * 3600))
    }
    func testChargeEstimate() {
        // 20 puan / 1 saat, şu an 60 → 40 puan = 2 saat
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 40, true), s(3600, 60, true)]))
        XCTAssertEqual(e, .timeToFull(2 * 3600))
    }
    func testEstimateUsesOnlyNewestPhase() {
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 90), s(3600, 80), s(7200, 80, true), s(10800, 85, true)]))
        XCTAssertEqual(e, .timeToFull(3 * 3600))
    }
    func testAbsurdlyLongEstimateGivesNone() {
        // 2 puan / 7 gün, şu an 98 → 343 gün > 30 gün
        let e = Estimator.estimate(DeviceHistory(samples: [s(0, 100), s(7 * 86400, 98)]))
        XCTAssertEqual(e, .none)
    }
    func testZeroOrFullGivesNone() {
        XCTAssertEqual(Estimator.estimate(DeviceHistory(samples: [s(0, 5), s(3600, 0)])), .none)
        XCTAssertEqual(Estimator.estimate(DeviceHistory(samples: [s(0, 90, true), s(3600, 100, true)])), .none)
    }
}
```

- [ ] **Step 2: Çalıştır, başarısız** — `swift test --filter EstimatorTests 2>&1 | tail -3`.
- [ ] **Step 3: `Estimator.swift` yaz.** `phase`: sondan geriye, `older` dahil edilir ancak `older.c == newest.c`, `older.t <= newer.t`, boşalmada `newer.l - older.l < riseTolerance`, şarjda `newer.l >= older.l`; ilk ihlalde dur. `estimate`: `ph.count >= 2`, `span >= minimumSpan`, `delta >= minimumLevelDelta` (boşalma `first.l - last.l`, şarj `last.l - first.l`); `remaining = last.l` (boşalma) veya `100 - last.l` (şarj); sonuç **`Double(remaining) * span / Double(delta)`** (önce çarpma: testlerdeki tam sayı örneklerinde kayan nokta hatası olmaz); sonuç `<= 0` veya `> maximumEstimate` ise `.none`.
- [ ] **Step 4: Geçsin** — `swift test 2>&1 | tail -3` → `Executed 25 tests, with 0 failures`.
- [ ] **Step 5: Commit** — `git commit -am "feat(estimator): phase extraction and slope-based estimate"`.

---

### Task 4: pbxproj betiği, estimator kaynaklarını uygulama hedefine ekleme, CI test adımı

**Files:**
- Create: `scripts/pbxproj_edit.py`
- Modify: `AirBattery.xcodeproj/project.pbxproj` (betikle)
- Modify: `.github/workflows/build.yml:52-55` (Build adımından önce)

**Interfaces:**
- Produces (CLI):
  - `python3 scripts/pbxproj_edit.py add-source <repo-relative .swift path> --group <GroupName>` — grup yoksa `AirBattery` grubu (`1841D44D2AA6071C0022A1BE`) altında `name = <GroupName>` ile PBXGroup oluşturur; `PBXFileReference` (`lastKnownFileType = sourcecode.swift`, `sourceTree = SOURCE_ROOT`, `path = <repo-relative path>`), `PBXBuildFile`, AirBattery hedefi Sources fazı (`1841D4472AA6071C0022A1BE`) ekler. `ViewModel` (`18F615F72B763FC900873AA4`) ve `BatteryInfo` (`18F615F62B763FAB00873AA4`) gruplarına eklerken `sourceTree = "<group>"` ve `path = <dosya adı>` kullanır.
  - `python3 scripts/pbxproj_edit.py add-localization <lang> --variant Localizable.strings|InfoPlist.strings` — `PBXFileReference` (`lastKnownFileType = text.plist.strings; name = "<lang>"; path = "<lang>.lproj/<variant>"`), ilgili `PBXVariantGroup` (`1841D47A2AA8DEF20022A1BE` / `189BD5EB2BDE69660056D06C`) children'a ekler, `knownRegions` listesine `<lang>` ekler (yoksa).
  - Her iki komut 24 büyük-hex karakterlik benzersiz ID üretir (`secrets.token_hex(12).upper()`, dosyada varsa yeniden), idempotenttir (aynı path varsa hiçbir şey yapmaz, çıkış 0), sonunda `plutil -lint` çalıştırır ve hata varsa dosyayı geri alıp çıkış 1 verir.

- [ ] **Step 1: Betiği yaz** (regex tabanlı satır ekleme; pbxproj'un `/* Begin PBXBuildFile section */` … `/* End … */` bloklarına satır ekler; sıralama önemli değil).
- [ ] **Step 2: Üç estimator dosyasını ekle:**
  ```bash
  for f in BatterySample DurationParts Estimator; do python3 scripts/pbxproj_edit.py add-source Packages/BatteryEstimator/Sources/BatteryEstimator/$f.swift --group Estimator; done
  plutil -lint AirBattery.xcodeproj/project.pbxproj
  ```
  Beklenen: `project.pbxproj: OK`; `grep -c 'Estimator.swift' project.pbxproj` → 3 (fileRef, buildFile, Sources satırı… en az 3).
- [ ] **Step 3: CI adımı** — `build.yml`'de `Build (Release)` adımından hemen önce:
  ```yaml
        - name: Estimator unit tests
          run: swift test --package-path Packages/BatteryEstimator 2>&1 | tail -20
  ```
  `set -o pipefail` gerektiğinden `run: |` bloğuna `set -o pipefail` ilk satır olarak eklenir.
- [ ] **Step 4: Commit + push + CI** — `git add -A && git commit -m "build: compile BatteryEstimator sources into the app; run package tests in CI" && git push -u origin feature/popover-redesign`; `gh run list --branch feature/popover-redesign --limit 1` ile run id, `gh run watch <id> --exit-status` → success. Başarısızsa derleme logundaki ilk `error:` satırı düzeltilir (tipik: `public` erişim uyumsuzluğu değil, dosya yolu hatası).

---

### Task 5: Geçmiş deposu, model kancası, Mac kalan süresi, URL komutları

**Files:**
- Modify: `AirBattery/BatteryInfo/InternalBattery.swift:10-17` (`iBattery`)
- Modify: `AirBattery/Supports/Supports.swift:339-351` (`getPowerState`), ayrıca üst kısma sabitler
- Modify: `AirBattery/BatteryInfo/AirBatteryModel.swift:56-75` (`updateDevice`)
- Create: `AirBattery/BatteryInfo/BatteryHistoryStore.swift`
- Modify: `AirBattery/Supports/AirBatteryApp.swift` (`applicationWillFinishLaunching` 176-285, `applicationWillTerminate` 306-310, `handleURLEvent` 410-426)
- Modify: `AirBattery.xcodeproj/project.pbxproj` (betikle: `BatteryHistoryStore.swift` → `BatteryInfo`)

**Interfaces:**
- Consumes: `DeviceHistory`, `Estimator`, `Estimate`, `BatterySample` (Task 1–3).
- Produces:
  ```swift
  // InternalBattery.swift
  struct iBattery { ...; var lowPower: Bool = false; var timeRemaining: Int? = nil }   // dakika
  // Supports.swift
  let staleAfterMinutes: Double = 10
  let menuBarCriticalThreshold = 10
  func menuBarLowThreshold() -> Int   // ud.integer(forKey: "menuBarLowThreshold"), register default 20
  // AirBatteryModel.swift
  static var updateHook: ((Device) -> Void)?   // kilit dışında, updateDevice sonunda çağrılır
  // BatteryHistoryStore.swift
  final class BatteryHistoryStore {
      static let shared: BatteryHistoryStore
      static let fileURL: URL   // ~/Library/Application Support/AirBattery/battery-history.json
      func load()
      func record(_ device: Device)
      func estimate(for device: Device) -> Estimate
      func saveIfNeeded(force: Bool = false)   // kirli ve son yazımdan ≥60 sn geçtiyse, force ile hemen
  }
  ```

- [ ] **Step 1: `iBattery.timeRemaining`** ekle; `getPowerState` içinde `ib.timeRemaining = internalBattery.timeRemaining` (ib oluşturulduktan sonra). Mevcut `iBattery(...)` çağrıları değişmez.
- [ ] **Step 2: Sabitler ve `menuBarLowThreshold()`** Supports.swift'e; `AirBatteryApp.applicationWillFinishLaunching` içindeki `ud.register(defaults:)` sözlüğüne `"menuBarLowThreshold": 20`.
- [ ] **Step 3: `updateHook`** — `updateDevice` gövdesi: `devicesLock.lock()` … listeyi güncelle … `devicesLock.unlock()` (defer kaldırılır), ardından `updateHook?(device)`.
- [ ] **Step 4: `BatteryHistoryStore`** — `private let lock = NSLock()`, `private var histories: [String: DeviceHistory]`, `private var dirty = false`, `private var lastSave: TimeInterval = 0`. Dosya biçimi `struct HistoryFile: Codable { var version: Int; var devices: [String: [BatterySample]] }` (version 1). `record`: `device.hasBattery` değilse veya `deviceID == "@MacInternalBattery"` ise dön; `histories[id, default: DeviceHistory()].record(level: batteryLevel, charging: isCharging != 0, at: Date().timeIntervalSince1970)` true ise `dirty = true`; sonunda `saveIfNeeded()`. `estimate(for:)`: kilit altında kopya al, dışarıda `Estimator.estimate`. `load`: dosya yoksa boş; decode hatası → `print("⚠️ battery history unreadable: \(error)")`, boş. `saveIfNeeded`: dizin `createDirectory(withIntermediateDirectories: true)`, `JSONEncoder` → `write(to:options: .atomic)`, hata → print.
- [ ] **Step 5: Uygulama kablolaması** — `applicationWillFinishLaunching`'de `bleBattery.startScan()`'den önce: `BatteryHistoryStore.shared.load()` ve `AirBatteryModel.updateHook = { BatteryHistoryStore.shared.record($0) }`. `applicationWillTerminate` başına `BatteryHistoryStore.shared.saveIfNeeded(force: true)`. `handleURLEvent` switch'ine `case "showpopover": DispatchQueue.main.async { if !menuPopover.isShown { self.togglePopover(nil) } }` ve `case "hidepopover": DispatchQueue.main.async { menuPopover.performClose(nil) }`.
- [ ] **Step 6: pbxproj** — `python3 scripts/pbxproj_edit.py add-source AirBattery/BatteryInfo/BatteryHistoryStore.swift --group BatteryInfo && plutil -lint AirBattery.xcodeproj/project.pbxproj`.
- [ ] **Step 7: Commit + push + CI** — `git commit -am "feat: battery history store, model hook, internal time remaining, popover URL commands"`, push, `gh run watch` → success.
- [ ] **Step 8: Çalışma zamanı doğrulaması** — CI DMG'sini indir (`gh run download <id>`), mount et, `.app`'i scratchpad'e kopyala, `open` ile başlat, 3 dk bekle (arka plan komutu), `cat ~/Library/Application\ Support/AirBattery/battery-history.json | head -c 400` → `"version":1` ve en az bir deviceID; `open "airbattery://showpopover"` → `pgrep` ile uygulama hâlâ çalışıyor. Sonra uygulamayı kapat, dosyaya `echo garbage >` yazıp yeniden başlat: uygulama açık kalmalı (crash raporu yok), 1 dk sonra dosya yeniden geçerli JSON olmalı.

---

### Task 6: DeviceCardView, DeviceRowActions, PopoverLayout, biçimlendiriciler

**Files:**
- Create: `AirBattery/ViewModel/DeviceCardView.swift`
- Modify: `AirBattery.xcodeproj/project.pbxproj` (betikle: → `ViewModel`)

**Interfaces:**
- Consumes: `Estimate`, `DurationParts` (paket), `getPowerColor(_:) -> String`, `getDeviceIcon(_:) -> String`, `btAlert`, `AlertWindowController`, `refeshPinnedBar`, `copyToClipboard`, `createAlert` (mevcut).
- Produces:
  ```swift
  enum PopoverLayout {
      static let width: CGFloat = 352, cardHeight: CGFloat = 68, cardSpacing: CGFloat = 5, horizontalInset: CGFloat = 10
      static let headerHeight: CGFloat = 26, sectionCaptionHeight: CGFloat = 18, hiddenRowHeight: CGFloat = 34
      static let verticalPadding: CGFloat = 8, maxHeight: CGFloat = 640
      static func contentHeight(cardCount: Int, sectionCount: Int, hiddenRow: Bool) -> CGFloat
      // = headerHeight + verticalPadding*2 + cardCount*cardHeight + max(cardCount-1,0)*cardSpacing + sectionCount*(sectionCaptionHeight+cardSpacing) + (hiddenRow ? hiddenRowHeight+cardSpacing : 0)
      static func height(cardCount: Int, sectionCount: Int, hiddenRow: Bool) -> CGFloat   // min(contentHeight, maxHeight)
  }
  func estimateText(_ e: Estimate) -> String?            // "~%@ left" / "~%@ to full"; .none → nil
  func durationText(_ p: DurationParts) -> String        // "%d d" | "%d h" [+ " " + "%d min"] | "%d min"
  func lastSeenText(sinceSeconds s: TimeInterval) -> String   // <60 "just now"; <3600 "%d min ago"; else "%d h ago"
  func internalEstimate(_ ib: iBattery) -> Estimate      // isCharged → .none; timeRemaining>0: charging→timeToFull(min*60) else timeToEmpty
  struct DeviceRowActions: View {
      let device: Device; let allowPin: Bool; let allowHide: Bool
      @Binding var alertList: [btAlert]; @Binding var pinnedList: [String]
      var onHide: (() -> Void)? = nil
  }
  struct DeviceCardView<Actions: View>: View {
      let device: Device; let estimate: Estimate; let isHovered: Bool
      let hasAlert: Bool; let isPinned: Bool
      @ViewBuilder let actions: () -> Actions
  }
  ```

- [ ] **Step 1: `PopoverLayout` ve üç biçimlendirici** yaz (`contentHeight` formülü yukarıda sabit).
- [ ] **Step 2: `DeviceRowActions`** — ContentView.swift 506-616 satırlarındaki dört düğme (zil / zil dolu, raptiye / raptiye dolu [allowPin], kopyala [`#available(macOS 14, *)`], gizle [allowHide]) aynı simge adları, aynı eylem gövdeleri ve hover renkleriyle buraya taşınır; gizle düğmesi `onHide?()` çağırır ve ardından mevcut blackList/pinnedList güncellemesini yapar. Yatay `HStack(spacing: 3)`, simge 18×18.
- [ ] **Step 3: `DeviceCardView`** davranışı:
  - Dış: `.frame(height: PopoverLayout.cardHeight)`, `.padding(.horizontal, 10)`, arka plan `Color(NSColor.controlBackgroundColor)` + `isHovered ? Color.blackWhite.opacity(0.06) : .clear` üstüne, `RoundedRectangle(cornerRadius: 9, style: .continuous)` ile kırp ve `.strokeBorder(Color.blackWhite.opacity(0.04))`.
  - Üst satır `HStack(spacing: 9)`: `Image(getDeviceIcon(device))` 22×22 `.foregroundColor(.blackWhite)`; `Text(device.deviceName)` 12.5 medium `.lineLimit(1).truncationMode(.tail)`; `hasAlert` ise `bell.fill` 10pt, `isPinned` ise `pin.fill` 10pt; `Spacer()`; etiket (aşağıda); `device.hasBattery` ise `Text("\(device.batteryLevel)%")` 14 semibold `.monospacedDigit()`, `batteryLevel <= 10` ise `Color.darkMyRed`.
  - Etiket (`StatusChip` private view: metin 10 semibold, dolgu 2×7, `Capsule()` arka plan renk `.opacity(0.16)`): `device.hasBattery` değilse yok; sırayla ilk eşleşen: **`isCharging != 0 && isCharging != 5 && !isCharged` → yeşil "Charging" + `bolt.fill`**; `batteryLevel <= 10` → kırmızı "Low"; `batteryLevel <= 20` → sarı "Getting low"; `isCharged` → gri "Full"; `acPowered || isCharging == 5` → gri "Plugged in" + `powerplug.portrait.fill`; aksi yok. Renkler `Color.myGreen/.myRed/.myYellow`, gri `.secondary`.
  - Çubuk: `hasBattery` ise `GeometryReader` içinde zemin `Capsule().fill(Color.blackWhite.opacity(0.08))` 5pt, dolu `Capsule().fill(Color(getPowerColor(device)))` genişlik `width * level/100` (en az 3pt, level 0'da 0).
  - Meta satırı (10.5pt `.secondary`): sol `estimateText(estimate)`, yoksa etiket metni dolu/fişte ise aynı metin, aksi halde boş `Text("")`; sağ: `isHovered` ise `actions()`, değilse son görülme: `seconds = now - (device.realUpdate != 0 ? device.realUpdate : device.lastUpdate)`; `seconds/60 > staleAfterMinutes` ise `exclamationmark.triangle.fill` 9pt + metin, ikisi `.orange`; aksi `.secondary`. Kalan süre yalnızca `hasBattery` ise.
- [ ] **Step 4: pbxproj** — `python3 scripts/pbxproj_edit.py add-source AirBattery/ViewModel/DeviceCardView.swift --group ViewModel && plutil -lint ...`.
- [ ] **Step 5: Commit + push + CI** — `git commit -am "feat(ui): DeviceCardView, row actions and PopoverLayout"` → `gh run watch` success (görünüm henüz kullanılmıyor; derleme kontrolü).

---

### Task 7: Popover ve Dock penceresini kartlara geçirme

**Files:**
- Modify: `AirBattery/ViewModel/ContentView.swift:282-830` (`popover`), `:832-980` (`nearcastView`)
- Modify: `AirBattery/Supports/AirBatteryApp.swift:103-174` (`applicationShouldHandleReopen`)

**Interfaces:**
- Consumes: Task 6'nın tümü, `BatteryHistoryStore.shared.estimate(for:)`, `internalEstimate(_:)`.

- [ ] **Step 1: `popover` başlığı** — `HStack(spacing: 4)` başına `Text("AirBattery").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)` + `Spacer()`; mevcut dört düğme sağda, sıraları ve eylemleri aynı; `.frame(height: PopoverLayout.headerHeight)`, `.padding(.horizontal, 12)`; `.offset(y: -3.5)` kaldırılır.
- [ ] **Step 2: Kart listesi** — `ForEach(allDevices.indices)` gövdesi: `if !hidden.contains(index) { DeviceCardView(device:, estimate:, isHovered: overStack == index, hasAlert:, isPinned:) { DeviceRowActions(device:, allowPin: id != "@MacInternalBattery", allowHide: id != "@MacInternalBattery", alertList: $alertList, pinnedList: $pinnedList, onHide: { hidden.append(index) }) }.onHover { … mevcut overStack ataması … } }`. `estimate`: `deviceID == "@MacInternalBattery"` ise `internalEstimate(InternalBattery.status)`, değilse `BatteryHistoryStore.shared.estimate(for:)`. Satır `Divider()`'ları, `.clipShape(RoundedCornersShape…)`, `.overlay(RoundedRectangle…)`, `.offset(y: 2.5)` kaldırılır; `VStack(alignment: .leading, spacing: PopoverLayout.cardSpacing)`, `.padding(.horizontal, PopoverLayout.horizontalInset)`.
- [ ] **Step 3: Boş durum** — `allDevices.count < 1 && hiddenDevices.count < 1` dalı: Mac için tek `DeviceCardView(device: ib2ab(InternalBattery.status), estimate: internalEstimate(...), isHovered: false, hasAlert: false, isPinned: false) { EmptyView() }`.
- [ ] **Step 4: Gizli satır** — mevcut HStack korunur, önüne `Text("Hidden".local.uppercased())` 9.5 bold `.secondary` `.tracking(0.8)` `.frame(height: PopoverLayout.sectionCaptionHeight)`; satır `.frame(height: PopoverLayout.hiddenRowHeight)`.
- [ ] **Step 5: Nearcast** — `nearcastView.body`: `Spacer().frame(height: 8)` yerine `Text(("Nearcast".local + " · " + (devices.first?.deviceName ?? "")).uppercased())` 9.5 bold `.secondary`, `.frame(height: PopoverLayout.sectionCaptionHeight)`; satırlar `DeviceCardView(device:, estimate: .none, isHovered: overStackNC == mainIndex && overStack == index, …) { DeviceRowActions(device:, allowPin: true, allowHide: false, alertList: $alertList, pinnedList: $pinnedList) }`; kenarlık/overlay/offset/Divider kaldırılır.
- [ ] **Step 6: Yükseklik ve kaydırma** — `popover` kök görünümü: tüm içerik `VStack` → `ScrollView(.vertical, showsIndicators: false)` içine alınır ve kök `.frame(width: PopoverLayout.width, height: PopoverLayout.height(cardCount:, sectionCount:, hiddenRow:))`; `cardCount` = `allDevices.count` (boş durumda 1) + Nearcast kart sayıları toplamı, `sectionCount` = boş olmayan Nearcast grupları. `mainTimer` tetiklemesinde bu değerler zaten `allDevices/allNearcast` ile güncelleniyor.
- [ ] **Step 7: Dock penceresi** — `applicationShouldHandleReopen` içinde `hiddenRow/ncCount/ncDeviceCount/menuHeight` hesabı (115-128) silinir; `contentView` oluşturulduktan sonra `let menuHeight = min(contentView.fittingSize.height, (NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.visibleFrame.height ?? 800) - 40)`; geri kalan konum hesabı `menuHeight` ile aynen devam eder.
- [ ] **Step 8: Commit + push + CI** — `git commit -am "feat(ui): card-based popover and dock window, measured height"`, push, `gh run watch` → success.
- [ ] **Step 9: Görsel doğrulama** — DMG indir, uygulamayı scratchpad'den `open` ile başlat, `open "airbattery://showpopover"`, `screencapture -x /tmp-yerine-scratchpad/popover-light.png`, Read ile incele: kartlar, etiketler, yüzde, çubuk, son görülme, başlık. Kalan süre için: `battery-history.json`'dan bir gerçek `deviceID` al, uygulamayı kapat, o kimliğe `[{t: now-7200,l:70,c:false},{t: now-3600,l:60,c:false},{t: now,l:50,c:false}]` yaz, yeniden başlat → o kartta "~5 h left". Koyu mod: `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'` dene; izin reddedilirse kullanıcıdan görünümü değiştirmesini iste, tekrar ekran görüntüsü. Dock penceresi: Ayarlar'da "Show AirBattery → Both" yerine `defaults write com.lihaoyun6.AirBattery showOn both`, yeniden başlat, Dock simgesine tıkla (Accessibility gerekebilir; olmazsa kullanıcı kontrol eder), ekran görüntüsü.

---

### Task 8: Menü çubuğu düşük cihaz eki

**Files:**
- Modify: `AirBattery/ViewModel/BatteryView.swift:48-215` (`mainBatteryView`)

**Interfaces:**
- Consumes: `menuBarLowThreshold()`, `menuBarCriticalThreshold`, `getDeviceIcon`, `setStatusBar(width:)`.
- Produces: `func lowestLowDevice(in devices: [Device]) -> Device?` (dosya düzeyinde, BatteryView.swift) — `hasBattery && deviceID != "@MacInternalBattery" && isCharging == 0 && batteryLevel <= menuBarLowThreshold()` filtresi, `min(by: batteryLevel)`.

- [ ] **Step 1: Durum ve hesap** — `@State var lowDevice: Device? = nil`; `.onAppear { lowDevice = lowestLowDevice(in: AirBatteryModel.getAll()) }`; `mainTimer` kapanışının başında aynı atama.
- [ ] **Step 2: Genişlik** — timer kapanışındaki `setStatusBar` dallanması şöyle sadeleşir: `let base: Double = (item.hasBattery && intBattOnStatusBar) ? (batteryPercent != "outside" || item.batteryLevel > hideLevel ? 42 : 76) : 36`; `let target = base + (lowDevice == nil ? 0 : 40)`; `if width != target { setStatusBar(width: target) }`. `test_debug` dalları aynı `base` mantığını kullanır.
- [ ] **Step 3: Görünüm** — kök `HStack` sonuna: `if let d = lowDevice { Rectangle().fill(Color.primary.opacity(0.3)).frame(width: 1, height: 12); Image(getDeviceIcon(d)).resizable().scaledToFit().frame(width: 13, height: 13); Text("\(d.batteryLevel)%").font(.system(size: 11, weight: .semibold)).foregroundColor(d.batteryLevel <= menuBarCriticalThreshold ? .red : .orange) }` (`HStack` spacing 4 → ek içinde 3; ek öncesinde 4pt boşluk).
- [ ] **Step 4: Commit + push + CI** — `git commit -am "feat(menubar): low-device suffix next to the Mac battery"`, push, watch → success.
- [ ] **Step 5: Doğrulama** — DMG'den çalıştır; `defaults write com.lihaoyun6.AirBattery menuBarLowThreshold 100` → en düşük şarjda olmayan cihaz eki görünmeli (menü çubuğu ekran görüntüsü, `screencapture -x -R0,0,1800,30`), `defaults delete com.lihaoyun6.AirBattery menuBarLowThreshold` → ek kaybolur ve genişlik daralır.

---

### Task 9: Yerelleştirme (en/zh ekleri, Türkçe)

**Files:**
- Modify: `AirBattery/zh-Hans.lproj/Localizable.strings`, `AirBattery/zh-Hant.lproj/Localizable.strings`
- Create: `AirBattery/tr.lproj/Localizable.strings`, `AirBattery/tr.lproj/InfoPlist.strings`
- Modify: `AirBattery.xcodeproj/project.pbxproj` (betikle)

- [ ] **Step 1: Yeni anahtarlar** — aşağıdaki 15 satır zh-Hans / zh-Hant dosyalarının sonuna (tr dosyasına üçüncü sütun):

| Key | zh-Hans | zh-Hant | tr |
|---|---|---|---|
| `Charging` | 充电中 | 充電中 | Şarj oluyor |
| `Plugged in` | 已接通电源 | 已接通電源 | Fişte |
| `Full` | 已充满 | 已充滿 | Dolu |
| `Low` | 电量低 | 電量低 | Düşük |
| `Getting low` | 电量偏低 | 電量偏低 | Azalıyor |
| `Hidden` | 已隐藏 | 已隱藏 | Gizli |
| `Nearcast` | Nearcast | Nearcast | Nearcast |
| `just now` | 刚刚 | 剛剛 | şimdi |
| `%d min ago` | %d 分钟前 | %d 分鐘前 | %d dk önce |
| `%d h ago` | %d 小时前 | %d 小時前 | %d sa önce |
| `~%@ left` | 约剩 %@ | 約剩 %@ | ~%@ kaldı |
| `~%@ to full` | 约 %@ 充满 | 約 %@ 充滿 | dolmasına ~%@ |
| `%d min` | %d 分钟 | %d 分鐘 | %d dk |
| `%d h` | %d 小时 | %d 小時 | %d sa |
| `%d d` | %d 天 | %d 天 | %d gün |

- [ ] **Step 2: `tr.lproj/Localizable.strings`** — `zh-Hans.lproj/Localizable.strings` içindeki **her** anahtar (148 + yukarıdaki 15) Türkçe değerle; `tr.lproj/InfoPlist.strings` — `zh-Hans.lproj/InfoPlist.strings` anahtarlarının Türkçesi.
- [ ] **Step 3: Anahtar seti doğrulaması** — `python3 -I -c` ile iki dosyadan `"key" = ` regex'iyle anahtar kümeleri çıkarılır: `set(tr) == set(zh-Hans)` → `True`; `plutil -lint AirBattery/tr.lproj/Localizable.strings` → OK.
- [ ] **Step 4: pbxproj** — `python3 scripts/pbxproj_edit.py add-localization tr --variant Localizable.strings && python3 scripts/pbxproj_edit.py add-localization tr --variant InfoPlist.strings && plutil -lint ...`; `grep -n 'knownRegions' -A 6` içinde `tr` görünür.
- [ ] **Step 5: Commit + push + CI** — `git commit -am "l10n: Turkish localization; new popover strings for zh"`, push, watch → success.
- [ ] **Step 6: Doğrulama** — `open -n <app> --args -AppleLanguages "(tr)"`, `open "airbattery://showpopover"`, ekran görüntüsünde "Şarj oluyor / şimdi / ~… kaldı" Türkçe.

---

### Task 10: Kapanış

- [ ] **Step 1:** `superpowers:finishing-a-development-branch` ile dalı sonuçlandır: kullanıcı DMG'yi denedikten sonra `main`'e merge (fast-forward veya PR), `.superpowers/` ve `docs/superpowers/` kalır.
- [ ] **Step 2:** Hafıza notunu güncelle (`project-airbattery-fork`): yeni dosyalar, `scripts/pbxproj_edit.py`, gizli `menuBarLowThreshold` default'u, `airbattery://showpopover`.
