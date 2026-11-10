# Ayarlar Penceresi Yeniden Tasarımı — Tasarım Belgesi

Tarih: 2026-11-10 · Dal: `feature/settings-redesign` · Önceki iş: `docs/superpowers/specs/2026-11-09-popover-redesign-design.md` (main'de, 50d4875)

## 1. Amaç

Ayarlar penceresinin düzenini sadeleştirmek, popover yeniden tasarımıyla gelen özelliklerin ayarlarını eklemek, cihaz yönetimini tek yere toplamak ve pencerenin içeriğe göre boyutlanmasını sağlamak. Görünüm dili değişmez (mevcut `SForm`/`SGroupBox`/`SToggle`… bileşenleri kullanılır); değişen şey yapı, işlev ve pencere davranışıdır.

## 2. Kararlar

Kullanıcıyla konuşarak alınanlar:

- Rahatsızlıklar: düzen karışık, işlevler eksik, pencere davranışı. Görünümün eski olması sorun **değil**.
- İstenen işlevler: düşük cihaz eşiği ayarları, tahmin ayarları, cihaz yönetimi tek yerde, uyarı merkezi.
- Pencere: içeriğe göre yükseklik, açılış konumu (ortada / son konum, her zaman önde).
- Yapı: 4 bölüm — Genel · Görünüm · Cihazlar · Keşif; Debug gizli kalır.
- Gezinme: üst sekmeler (klasik Tercihler penceresi). Gerekçe: macOS, `Settings` sahnesindeki `TabView`'ı sekme başına içeriğe göre kendisi animasyonla boyutlar.
- Pencere, Genel ve Görünüm bölümleri onaylandı ("Uygun, devam").

Kullanıcı uyurken verilen kararlar (sabah raporunda listelenir, dal main'e birleştirilmez):

- **K1 — Cihazlar düzeni: B, liste + ayrıntı paneli.** Satır içi kontroller 560 pt genişlikte uzun adlarla sıkışır ve uyarı eşikleri için ayrı bir popover gerektirir; ayrıntı paneli tüm cihaz ayarlarını ve cihaz başına geçmiş silmeyi yazıyla gösterir, Sistem Ayarları diliyle uyumludur. Bedeli: bir cihazın durumunu görmek için onu seçmek gerekir.
- **K2 — Kimlik.** Mevcut listeler (`blackList`, `blockedDevices`, `pinnedList`, `alertList`) cihaz **adıyla** çalışır; geçmiş deposu **deviceID** ile. Cihazlar sekmesi her ikisini birleştirir; geçmiş dosyasına `names` sözlüğü eklenir (sürüm 2) ki çevrimdışı cihazlar adıyla listelenebilsin.
- **K3 — Engelleme izin listesi modunda.** Görünürlük denetimi yalnızca Göster/Gizle (`blackList`); engelleme ayrı bir satırdır: normal modda "Engelli" anahtarı (`blockedDevices`'ta olmak), izin listesi modunda aynı satır "İzinli" olur (yine `blockedDevices`'ta olmak). Veri semantiği mevcut `checkIfBlocked(name:)` ile birebir aynı kalır.
- **K4 — Kritik eşik ayarlanabilir olur.** `menuBarCriticalThreshold` sabiti UserDefaults'tan okunan fonksiyona dönüşür (varsayılan 10); ek ayrıca tamamen kapatılabilir (`menuBarLowSuffix`, varsayılan açık).
- **K5 — Geçmiş temizliği.** "Geçmişi temizle" tüm örnekleri siler (onaylı); "Görülmeyenleri temizle" 7 günden uzun süredir görülmeyen ve hiçbir listede olmayan cihazların geçmiş kayıtlarını siler. Cihaz başına silme ayrıntı panelindedir.
- **K6 — Pencere genişliği 560 pt**, her sekme kendi doğal yüksekliğinde; Cihazlar sekmesinde liste en çok 8 satır gösterir ve kendi içinde kayar, pencere yüksekliği bu sekmede sabittir.

## 3. Kapsam dışı

Popover, Dock penceresi, widget'lar, uyarı penceresi (`AlertWindowController`) ve tarama kodu değişmez. Ayar anahtarlarının adları ve türleri değişmez; eski sürümden gelen kullanıcı hiçbir ayarını kaybetmez. Yeni görsel bileşen yazılmaz; mevcut `GroupForm.swift` bileşenleri kullanılır.

## 4. Mimari ve dosyalar

- `AirBattery/ViewModel/SettingsView.swift` — yeniden yazılır: `SettingsView` (TabView kökü) + sekme görünümleri `GeneralTab`, `AppearanceTab`, `DiscoveryTab`, `DebugTab` (Debug içeriği mevcut `DebugView`'dan "Data Folder" düğmesi çıkarılarak taşınır).
- `AirBattery/ViewModel/DevicesSettingsView.swift` — yeni: `DevicesTab`, `DeviceDetailView`, `KnownDevice` modeli ve `KnownDeviceList.build(...)` saf birleştirme fonksiyonu.
- `AirBattery/BatteryInfo/BatteryHistoryStore.swift` — dosya sürümü 2 (`names`), yeni API: `summary() -> (deviceCount: Int, bytes: Int)`, `names() -> [String: String]`, `lastSeen() -> [String: TimeInterval]`, `clear()`, `remove(deviceID:)`, `pruneUnseen(olderThan: TimeInterval, keeping names: Set<String>) -> Int`.
- `AirBattery/Supports/Supports.swift` — `menuBarCriticalThreshold` sabiti → `func menuBarCriticalThreshold() -> Int`; `func menuBarLowSuffixEnabled() -> Bool`.
- `AirBattery/ViewModel/BatteryView.swift` — ek kapatılabilir; kritik eşik fonksiyonu kullanılır.
- `AirBattery/ViewModel/ContentView.swift` — `showEstimate` kapalıyken kart tahmini `.none`; `openSettingPanel()` pencere konumu.
- `AirBattery/Supports/AirBatteryApp.swift` — `ud.register` yeni varsayılanlar; `updateHook` kaydına ad kaydı.
- `AirBattery.xcodeproj/project.pbxproj` — yalnızca `scripts/pbxproj_edit.py add-source AirBattery/ViewModel/DevicesSettingsView.swift --group ViewModel`.
- Yerelleştirme: `zh-Hans`, `zh-Hant`, `tr` dosyalarına yeni anahtarlar (bölüm 10).

## 5. Pencere

- Kök: `TabView(selection: $tab)`; sekmeler `General` (`gearshape`), `Appearance` (`paintbrush`), `Devices` (`laptopcomputer.and.iphone`), `Discovery` (`antenna.radiowaves.left.and.right`); `showDebug` ise `Debug` (`ladybug`). Tüm semboller macOS 11'de vardır.
- Her sekme kökü `.frame(width: 560)`; yükseklik içeriğe göre. `SForm` üst/alt dolgusu korunur. `.navigationTitle` kaldırılır (sekme başlığı pencere başlığı olur).
- `openSettingPanel()` mevcut menü eylemini çağırmaya devam eder; ardından ana kuyrukta ayarlar penceresini bulur (`NSApp.windows` içinde `identifier?.rawValue` "Settings" içeren ya da `title` sekme adlarından biri olan pencere), `setFrameAutosaveName("AirBatterySettingsWindow")` uygular, kayıtlı çerçeve yoksa `center()`, sonra `makeKeyAndOrderFront(nil)` ve `orderFrontRegardless()`. Pencere bulunamazsa sessizce vazgeçilir (mevcut davranış).
- Gizli yardımcılar (ekran görüntüsü doğrulaması için, belgelenmez): `airbattery://showsettings` URL komutu `openSettingPanel()` çağırır (`handleURLEvent`'e `case "showsettings"`); `SettingsView` açılışta `ud.string(forKey: "settingsTab")` okur ve değer `general|appearance|devices|discovery|debug` ise o sekmeyle başlar (anahtar yoksa `general`).

## 6. Genel sekmesi

Gruplar ve içerik (anahtar adları mevcut):

1. **Startup** — `Launch at Login` (`launchAtLogin`, `SMLoginItemSetEnabled` onChange aynen), `Show AirBattery` (`showOn`; onChange gövdesi — etkinlik politikası, status item görünürlüğü, Dock uyarısı — aynen), `Command Line Tool` kur/kaldır.
2. **Estimate & Data** (yeni) — `Show remaining time estimate` (`showEstimate`, varsayılan `true`); bilgi satırı `History: %d devices, %@` (`BatteryHistoryStore.shared.summary()`, boyut `ByteCountFormatter`); `Clear History` düğmesi → `createAlert(title: "Clear battery history?", message: "This removes the collected samples for all devices. Estimates start over.", button1: "Clear", button2: "Cancel")`, onayda `clear()`; `Data Folder` → `Open` (Debug'dan taşınır).
3. **Update** — `UpdaterSettingsView`, `CheckForUpdatesView`, sürüm etiketi (10 tıklama → `showDebug`), aynen.

## 7. Görünüm sekmesi

1. **Menu Bar** — mevcut altı denetim aynen (`intBattOnStatusBar`, `colorfulBattery`, `iosBatteryStyle`, `batteryPercent`, `disappearTime`, `hideLevel`; `disabled` koşulları aynen).
2. **Low Device Badge** (yeni grup) — `Show low devices in the menu bar` (`menuBarLowSuffix`, varsayılan `true`); `Low threshold` `SSteper` 5…50 (`menuBarLowThreshold`, varsayılan 20); `Critical threshold` `SSteper` 5…30 (`menuBarCriticalThreshold`, varsayılan 10). Kural: kritik, düşükten büyük olamaz — düşük azaltılıp kritiğin altına inerse kritik ona eşitlenir; kritik artırılıp düşüğü geçerse düşük ona eşitlenir. Anahtar kapalıyken iki stepper `disabled`.
3. **Dock** — `appearance`, `showThisMac`, `carouselMode` aynen.
4. **Widget** — `revListOnWidget`, `widgetInterval`, `deviceOnWidget` (`#unavailable(macOS 14)`), `Reload All Widgets` aynen; `onAppear`/`dockTimer` cihaz listesi güncellemesi aynen.

Menü çubuğu eki davranışı: `BatteryView.swift`'te `lowDevice = menuBarLowSuffixEnabled() ? lowestLowDevice(in: AirBatteryModel.getAll()) : nil`; renk `d.batteryLevel <= menuBarCriticalThreshold()`.

## 8. Cihazlar sekmesi

### 8.1 Veri modeli

```swift
struct KnownDevice: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let deviceID: String?        // model veya geçmişten; yalnızca listede olan ad için nil
    let deviceType: String?      // simge için; nil → "generic" simgesi
    let isOnline: Bool           // şu an AirBatteryModel'de ve isHidden değil ya da gizli
    let batteryLevel: Int?       // çevrimiçi ise
    let isCharging: Bool
    let lastSeen: TimeInterval?  // çevrimdışı ise (geçmişteki en yeni örnek), hiç görülmemişse nil
    var isHidden: Bool           // blackList
    var isListed: Bool           // blockedDevices (normal: engelli; izin modunda: izinli)
    var isPinned: Bool           // pinnedList
    var alert: btAlert?          // alertList
    let sampleCount: Int         // geçmiş örnek sayısı
}
```

`KnownDeviceList.build(current: [Device], historyNames: [String: String], lastSeen: [String: TimeInterval], sampleCounts: [String: Int], blackList: [String], blocked: [String], pinned: [String], alerts: [btAlert]) -> [KnownDevice]` saf fonksiyondur:

1. `current` içinden `deviceID != "@MacInternalBattery"` olanlar (gizliler dahil, `noFilter: true`) → çevrimiçi kayıtlar (ad çakışırsa ilk).
2. `historyNames` içinde olup (1)'de adı geçmeyen deviceID'ler → çevrimdışı kayıtlar, `lastSeen` ile.
3. Dört listedeki adlardan (1) ve (2)'de olmayanlar → "hiç görülmemiş" kayıtlar (`deviceID = nil`).
4. Sıralama: çevrimiçi (ada göre), sonra çevrimdışı (`lastSeen` yeniden eskiye), sonra hiç görülmemiş (ada göre).

### 8.2 Görünüm

- Sol: `List(selection:)`, satır = simge (`getDeviceIcon` için `Device` yoksa `"generic"`) + ad (tek satır, kuyruk kesme) + ikincil ek: `· hidden` / `· blocked` (izin modunda `· not allowed` = listede olmayan) / `· offline`. Yükseklik 8 satır (~8×26 pt), fazlası kayar. Liste boşsa ortada `No devices yet` metni.
- Sağ, `DeviceDetailView(device:)`:
  - Başlık: simge, ad; alt satır çevrimiçi ise `"\(level)%"` + şarjda ise `bolt.fill`, değilse `Last seen %@` (`lastSeenText`) ya da `Never seen`.
  - `Visibility`: segmented `Show` / `Hide` → `blackList` ekle/çıkar + `AirBatteryModel.hideDevice/unhideDevice(name)` + popover'daki gizli satırla aynı veri.
  - `Blocked` (normal mod) / `Allowed` (izin modu) anahtarı → `blockedDevices` ekle/çıkar; engellenince cihaz `AirBatteryModel.Devices`'tan hemen çıkarılır (`removeAll { $0.deviceName == name }`), engel kalkınca bir sonraki taramada döner.
  - `Pin to menu bar` anahtarı → `pinnedList` güncelle; açılınca `refeshPinnedBar()`, kapanınca `refeshPinnedBar(unpin: name)`. Çevrimdışı/hiç görülmemiş cihazlar için `disabled`.
  - `Low battery alert` anahtar + `SSteper` 1…99; `Full battery alert` anahtar + `SSteper` 1…100; `Play sound` anahtarı (hem `lowSound` hem `fullSound`). Değişiklikler `alertList`'teki `btAlert`'i günceller; kayıt yoksa `New device alert defaults` değerleriyle (`alertDefaultLow` 20, `alertDefaultFull` 80, `alertDefaultSound` true — yeni anahtarlar) oluşturulur; iki uyarı da kapalıysa kayıt silinir. Yazma: `ud.set(object: alertList, forKey: "alertList")` (mevcut yardımcı).
  - `Delete history for this device` düğmesi (`deviceID` varsa) → `remove(deviceID:)`; `sampleCount` 0 ise `disabled`.
- Alt şerit: `Block by name…` (metin alanı + `Add`; boş/çift ad reddedilir) · `Remove unseen devices` (`pruneUnseen(olderThan: 7*86400, keeping: tüm listelerdeki adlar)`, sonuç `createAlert` ile "Removed %d devices") · sağda `Allowlist mode` anahtarı (`whitelistMode`; açılınca mevcut davranış aynen — ek uyarı yok).
- Üst bilgi satırı: `New device alert defaults: low %d%%, full %d%%` ve bir `Edit` düğmesi → küçük popover'da iki stepper + ses anahtarı.
- Yenileme: `dockTimer` (5 sn) ile `KnownDeviceList.build` yeniden çalışır; seçim ada göre korunur.

### 8.3 Geçmiş deposu değişiklikleri

- `HistoryFile { version: Int = 2; devices: [String: [BatterySample]]; names: [String: String] }`. `load()`: sürüm 1 dosya kabul edilir (`names` boş); sürüm 2 normal; başka sürüm → mevcut bozuk dosya yolu.
- `record(_:)`: `names[deviceID] = deviceName` (değiştiyse `dirty`).
- `clear()`: tüm `histories` ve `names` boşaltılır, `saveIfNeeded(force: true)`.
- `remove(deviceID:)`: tek cihaz, zorunlu kayıt.
- `pruneUnseen(olderThan:keeping:)`: `lastSeen < now - olderThan` ve adı `keeping` içinde olmayan deviceID'leri siler; sayı döner; zorunlu kayıt.
- `summary()`: cihaz sayısı ve dosya boyutu (`fileURL` attributes; dosya yoksa 0).
- Tümü kilit altında; `Estimator` çağrısı dışarıda (mevcut).

## 9. Keşif sekmesi

1. **Scanner** — altı tarama anahtarı, turuncu renk ve `createAlert` uyarıları aynen.
2. **Others** — `Refresh Interval (min)` stepper + "Relaunch…" notu, `Earbud Merging Threshold`, aynen.
3. **Nearcast** — `Enable Nearcast` (onChange aynen), `Group ID` alanı + üret/kopyala düğmeleri, iki dipnot, aynen.
4. **Peer Info** — `Local ID`, aynen.

## 10. Yerelleştirme

Yeni anahtarlar (İngilizce metin = anahtar): `Appearance` (sekme; mevcut Dock anahtarıyla aynı, yeniden kullanılır), `Devices`, `Discovery`, `Estimate & Data`, `Show remaining time estimate`, `History: %d devices, %@`, `Clear History`, `Clear battery history?`, `This removes the collected samples for all devices. Estimates start over.`, `Clear`, `Low Device Badge`, `Show low devices in the menu bar`, `Low threshold`, `Critical threshold`, `No devices yet`, `Select a device`, `Visibility`, `Show`, `Hide`, `Blocked`, `Allowed`, `hidden`, `blocked`, `not allowed`, `offline`, `Pin to menu bar`, `Low battery alert`, `Full battery alert`, `Play sound`, `Delete history for this device`, `Block by name…`, `Add`, `Remove unseen devices`, `Removed %d devices`, `Allowlist Mode` (mevcut anahtar), `Last seen %@`, `Never seen`, `New device alert defaults: low %d%%, full %d%%`, `Edit`, `Default low`, `Default full`. Her biri `zh-Hans`, `zh-Hant` ve `tr` dosyalarına değerle eklenir; `tr` anahtar kümesi `zh-Hans`'ı kapsamaya devam eder.

## 11. Hata yönetimi

- Ayarlar penceresi bulunamazsa konumlandırma atlanır.
- Geçmiş dosyası yazılamazsa mevcut `print` yolu; `clear()`/`remove`/`prune` bellek durumunu yine günceller.
- `alertList`/`pinnedList`/`blackList`/`blockedDevices` okumaları mevcut `as! [String]` kalıplarını değil güvenli `as? ?? []` biçimini kullanır (yeni kodda).
- Cihaz listesi boşken ayrıntı paneli `Select a device` yer tutucusunu gösterir.

## 12. Test ve doğrulama

- Paket testleri (25) değişmez; `BatteryHistoryStore` uygulama hedefinde olduğundan birim testi yok.
- CI derlemesi her görevde; macOS 11 API kuralı aynen (`.textCase`, `Picker(.segmented)`, `List(selection:)` 11'de var).
- Çalışma zamanı: kullanıcının `/Applications` kopyası kapatılır, test derlemesi açılır; ayarlar penceresi `open "airbattery://showsettings"` (yeni gizli komut) ile açılır; her sekme `defaults write com.lihaoyun6.AirBattery settingsTab <ad>` ile seçilebilir (yeni gizli anahtar, pencere açılışında okunur); dört sekme + Debug ekran görüntüsü alınır. Cihazlar sekmesi, `defaults export` ile yedeklenen kullanıcı ayarları üzerine `blackList`/`pinnedList`/`alertList` örnek değerleri yazılarak doldurulur; sonunda `defaults import` ile yedek geri yüklenir ve kullanıcı kopyası yeniden açılır.

## 13. Riskler

- `TabView` içeriğe göre boyutlama: SwiftUI `Settings` sahnesinde pencere yüksekliği sekmeye göre otomatik değişir; bir sekmede `ScrollView`/`List` esnek yükseklik verirse pencere büyümez — Cihazlar listesine sabit yükseklik verilir.
- `blockedDevices` adla çalışır; aynı adlı iki cihaz birlikte engellenir (mevcut davranış).
- Geçmiş dosyası sürüm 2'ye geçer; eski sürüm uygulamalar (main'deki 50d4875) `names` alanını yok sayar ve sürüm 2 dosyayı "unreadable" sayıp sıfırlar — kullanıcı eski DMG'ye dönerse geçmiş silinir. Kabul edilir.
