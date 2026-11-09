# AirBattery: popover yeniden tasarımı, kalan süre tahmini, menü çubuğu uyarısı

Tarih: 2026-11-09 · Durum: onay bekliyor

## 1. Amaç

Popover'ı (ve aynı görünümü kullanan Dock penceresini) bir bakışta daha fazla şey söyleyen, güncel macOS hissi veren bir yapıya dönüştürmek; her cihaz için kalan süre tahmini göstermek; menü çubuğu ikonunun tıklanmadan "bir cihaz şarj istiyor mu" sorusunu cevaplamasını sağlamak.

Alınmış kararlar (beyin fırtınası, 2026-11-09):

- Popover düzeni: **B · çubuklu kartlar**. Her cihaz bir kart, altında tam genişlikte seviye çubuğu, şarj/düşük durumu renkli etiket, altta kalan süre ve son görülme.
- Menü çubuğu: **Mac pili + düşük cihaz eki**. İkon her zaman Mac'in pilini gösterir; bir cihaz düşüğe inince yanına o cihazın simgesi ve kırmızı yüzdesi eklenir.
- Kalan süre: **yerel örnek geçmişi + eğim tahmini** (yaklaşım 1). Dış servis, ön bilgi tablosu, yeni izin yok.

## 2. Kapsam

Kapsamda:

1. Kalan süre tahmin motoru (`BatteryEstimator`, Swift paketi, testli).
2. Cihaz geçmişi deposu ve `AirBatteryModel` kancası.
3. Popover/Dock penceresi: kart tabanlı yeni satır görünümü, başlık, Nearcast bölümleri, gizli cihaz satırı, pencere boyutlandırması.
4. Menü çubuğu ana ikonuna düşük cihaz eki.
5. Ekran görüntüsü doğrulaması için gizli `airbattery://showpopover` komutu.
6. Yeni metinlerin yerelleştirilmesi (en, zh-Hans, zh-Hant) ve yeni bir **Türkçe** dil dosyası (tüm uygulama).

Kapsam dışı: widget'lar, ayarlar penceresi, bildirim/uyarı pencereleri, Nearcast protokolü, AirPods satırlarının birleştirilmesi (bugün kılıf ve kulaklıklar ayrı satırsa öyle kalır), yeni ayar seçenekleri.

## 3. Mimari ve dosyalar

```
Packages/BatteryEstimator/
  Package.swift                       swift-tools 5.5, macOS 11, library + test target
  Sources/BatteryEstimator/
    BatterySample.swift               örnek, geçmiş, kayıt kuralları
    Estimator.swift                   faz çıkarma, eğim, tahmin
    DurationParts.swift               süreyi gün/saat/dakikaya yuvarlama
  Tests/BatteryEstimatorTests/...     XCTest
AirBattery/BatteryInfo/BatteryHistoryStore.swift   uygulama tarafı depo (kalıcılık + kilit)
AirBattery/ViewModel/DeviceCardView.swift          kart, etiket, çubuk, meta satırı
AirBattery/ViewModel/ContentView.swift             popover: kartları kullanır, başlık/Nearcast/gizli satır restile
AirBattery/ViewModel/BatteryView.swift             mainBatteryView: düşük cihaz eki
AirBattery/Supports/AirBatteryApp.swift            Dock penceresi boyutu, URL komutları, depo yükleme/kaydetme
AirBattery/BatteryInfo/AirBatteryModel.swift       static updateHook
AirBattery/BatteryInfo/InternalBattery.swift       iBattery.timeRemaining (dakika)
AirBattery/tr.lproj/Localizable.strings            yeni
.github/workflows/build.yml                        swift test adımı
```

Paket, Xcode projesine SPM bağımlılığı olarak **bağlanmaz**. `Sources/BatteryEstimator/*.swift` dosyaları doğrudan AirBattery uygulama hedefine kaynak olarak eklenir (pbxproj'a dosya referansı). Aynı dosyalar paket üzerinden `swift test` ile test edilir. Gerekçe: makinede Xcode yok, pbxproj elle düzenleniyor; dosya referansı eklemek paket bağlamaktan çok daha az kırılgan.

`AirBatteryModel.swift`, `InternalBattery.swift` ve `Supports.swift` dosyaları `abt` ve widget hedeflerinde de derleniyor. Bu üç dosyaya yeni tipe bağımlılık **eklenmez**; model kancası isteğe bağlı bir closure'dır (`static var updateHook: ((Device) -> Void)?`), uygulama açılışta atar, abt ve widget'ta nil kalır.

## 4. Veri akışı

1. Bir tarayıcı (`BLEBattery`, `MagicBattery`, `IDeviceBattery`, `LogReader`, `BTDBattery`) `AirBatteryModel.updateDevice(device)` çağırır.
2. `updateDevice` listeyi kilit altında günceller, kilidi bırakır, sonra `updateHook?(device)` çağırır.
3. `BatteryHistoryStore.shared.record(device)`: `hasBattery == false` veya `deviceID == "@MacInternalBattery"` ise çıkar; aksi halde `deviceID` anahtarıyla `DeviceHistory.append(...)` uygular, değişiklik olduysa kaydetmeyi planlar (en fazla dakikada bir), uygulama kapanırken de kaydeder.
4. Popover her çizimde (`mainTimer`, 1 sn) her cihaz için `BatteryHistoryStore.shared.estimate(for: device)` sorar; depo paket fonksiyonunu çağırır. Mac'in kendi pili için depo kullanılmaz, `InternalBattery.status.timeRemaining` (dakika) aynı biçimlendiriciden geçer.
5. Nearcast ile başka Mac'lerden gelen cihazlar `updateDevice`'tan geçmediği için tahmin almaz; satırda sadece son görülme gösterilir.

Kalıcılık: `~/Library/Application Support/AirBattery/battery-history.json`

```json
{ "version": 1, "devices": { "<deviceID>": [ { "t": 1794180000, "l": 87, "c": false } ] } }
```

## 5. Tahmin algoritması (`BatteryEstimator`)

Örnek: `(t: TimeInterval, l: Int 0...100, c: Bool)`; `c` = `device.isCharging != 0` (şarjda veya fişte; "boşalmıyor" fazı).

Kayıt kuralları (`DeviceHistory.append`):

- Geçmiş boşsa kaydet.
- `l` veya `c` son örnekten farklıysa kaydet.
- Aynı olsa bile son örnekten bu yana **30 dakika** geçtiyse kaydet (kalp atışı; uzun düz dönemlerin de zaman damgası olsun).
- Saklama: en eski örnekler düşer; 7 günden eski olanlar ve 300'ü aşanlar silinir.

Faz çıkarma (en yeniden geriye yürü, aşağıdakilerden biri olunca dur):

- `c` değişti.
- Boşalma fazında seviye bir önceki örneğe göre **3 puan veya daha fazla yükseldi** (başka yerde şarj edilmiş). 1–2 puanlık sıçramalar BLE gürültüsü sayılır, faz kesilmez.
- Şarj fazında seviye düştü.
- Zaman damgası geriye gitti (saat değişti).

Uyku gibi uzun gözlem boşlukları tek başına fazı kesmez; eğilim monoton kaldığı sürece devam eder. Böylece günlerce %1 düşen klavye için de tahmin oluşur.

Tahmin (`Estimator.estimate(history, now)`):

- Fazda en az 2 örnek, uçlar arasında en az **10 dakika** ve en az **2 puan** fark yoksa `.none`.
- `rate = Δlevel / Δtime` (puan/saniye), uç noktalardan. Boşalma: `timeToEmpty = level_son / rate`. Şarj: `timeToFull = (100 - level_son) / rate`.
- Sonuç 30 günden büyükse `.none`.
- Sonuç: `enum Estimate { case none, timeToEmpty(TimeInterval), timeToFull(TimeInterval) }`.

Süre yuvarlama (`DurationParts.from(seconds)`):

- 60 dakikadan az: en yakın 5 dakikaya, en az 5 → "~55 dk".
- 24 saatten az: saat + dakikayı 5'e yuvarla; dakika 0 ise sadece saat → "~3 sa 10 dk", "~3 sa".
- 24 saat ve üzeri: en yakın tam güne, en az 1 → "~6 gün".

Metin birleştirme uygulama tarafında `.local` anahtarlarıyla yapılır: `"~%@ left"`, `"~%@ to full"`, `"%d min"`, `"%d h"`, `"%d d"`.

## 6. Popover ve Dock penceresi

Genişlik 352 pt sabit kalır. Arka plan bugünkü gibi (NSPopover kendi malzemesi; Dock penceresinde mevcut `BlurView`).

Başlık satırı (26 pt): solda "AirBattery" 11 pt semibold, ikincil renk; sağda bugünkü simgeler aynı sırayla ve aynı işlevle (çıkış/küçült, bilgi, ayarlar, Nearcast yenile).

Kart (`DeviceCardView`), kartlar arası 5 pt boşluk, yatay kenar 10 pt, iç dolgu 8 pt dikey 10 pt yatay, köşe 9 pt, arka plan `Color(NSColor.controlBackgroundColor)` üstüne %4 siyah/beyaz çerçeve:

- Üst satır: cihaz simgesi 22 pt (`getDeviceIcon`, bugünkü) · ad 12.5 pt medium, tek satır, sona üç nokta · etiket (varsa) · yüzde 14 pt semibold, tabular rakam.
- Çubuk: 5 pt yüksek, 3 pt köşe, zemin %8 opak; dolu kısım `getPowerColor(device)` rengi (mevcut eşikler: ≤10 kırmızı, ≤20 sarı, `lowPower` sarı, diğer yeşil).
- Meta satırı 10.5 pt ikincil renk: solda tahmin metni ("~3 sa 10 dk kaldı", "dolmasına ~1 sa 05 dk"); tahmin yoksa durum metni ("Dolu", "Fişte") ya da boş. Sağda son görülme: `realUpdate` (0 ise `lastUpdate`) ile şimdi arasındaki fark; 60 sn altı "şimdi", 60 dk altı "N dk önce", üstü "N sa önce". 10 dakikayı aşınca sağ metin turuncu ve önüne `exclamationmark.triangle` gelir; addaki "⚠︎ " öneki kaldırılır.
- Etiket (`StatusChip`, 10 pt semibold, 2×7 pt dolgu, tam yuvarlak): öncelik sırasıyla şarjda → yeşil "Charging" (bolt); ≤10 → kırmızı "Low"; ≤20 → sarı "Getting low"; dolu/fişte (`isCharged` veya `acPowered` veya `isCharging == 5`) → gri "Full"/"Plugged in"; aksi halde etiket yok.
- Hover: kart arka planına %6 ek koyuluk; meta satırının sağındaki son görülme metni yerine bugünkü eylem simgeleri gelir (zil/uyarı, raptiye, kopyala [macOS 14+], gizle [Mac'in pili hariç]). Simgeler, hedefler ve davranışlar bugünkü koddan taşınır; sağ tık menüsü eklenmez.
- Yükseklik hover ile değişmez (eylem şeridi meta satırıyla aynı yüksekliktedir).

Nearcast bölümleri: her peer için 9.5 pt büyük harf başlık ("NEARCAST · <peer adı>") ve aynı kartlar; eylemler bugünkü gibi (zil, raptiye, kopyala). Gizli cihazlar satırı korunur: 20 pt simgeler, tıklayınca geri gelir, üstünde 9.5 pt "HIDDEN" başlığı.

Satırlar bugünkü cihaz listesiyle bire bir aynıdır; sıralama, filtreler, AirPods'un ayrı satırları değişmez.

Boyutlandırma:

- Popover (NSPopover): içerik sabit genişlik 352 pt, yükseklik içeriğin doğal yüksekliği (`.frame(width: 352)` ve sabit yükseklik yok). İçerik 640 pt'yi aşarsa kart listesi `ScrollView` içine alınır ve yükseklik 640 pt'de kalır.
- Dock penceresi: `AirBatteryApp.applicationShouldHandleReopen` içindeki `37 * satır + 30 + 7 * grup` formülü kaldırılır; yükseklik `NSHostingView.fittingSize.height` ile ölçülür, üst sınır ekranın görünür yüksekliği eksi 40 pt (aşarsa aynı `ScrollView`). Konumlandırma mantığı (Dock yönüne göre x/y) aynen kalır, sadece `menuHeight` ölçülen değerden gelir.

Karanlık mod: yalnızca semantik renkler ve opaklıklar; etiket renkleri `my_green/my_yellow/my_red` varlıkları üstüne %16 opaklık zemin. Animasyon eklenmez.

## 7. Menü çubuğu eki (`mainBatteryView`)

- Aday cihazlar: `AirBatteryModel.getAll()` (gizli, engelli ve süresi dolmuş cihazlar zaten elenmiş), Mac'in kendi pili hariç, `isCharging == 0` olanlar, `batteryLevel <= 20`.
- Aday varsa en düşük seviyeli olan seçilir. İkonun sağına 4 pt boşluk, 1 pt dikey ayırıcı (%30 opak), 4 pt boşluk, cihaz simgesi 13 pt template (`getDeviceIcon`), 3 pt boşluk, "N%" 11 pt semibold: ≤10 kırmızı, 11–20 turuncu.
- Aday yoksa ek görünmez, ikon bugünkü genişliğine döner.
- Genişlik: bugünkü taban genişliğe (36/42/76) ek için +40 pt; değişiklikte mevcut `setStatusBar(width:)` çağrılır. Hesap `mainTimer` tetiklemesinde yapılır, bir önceki genişlikle aynıysa yeniden kurulmaz.
- Eşik (20) ve renk eşiği (10) `Supports.swift`'te sabit; yeni ayar eklenmez.
- Mac'in pil gösterimi kapalıyken (`intBattOnStatusBar == false`) ya da masaüstü Mac'te de ek aynı şekilde çalışır.

## 8. Gizli URL komutları

`handleURLEvent` içine `airbattery://showpopover` (menü çubuğu popover'ını açar; `togglePopover`) ve `airbattery://hidepopover` eklenir. Kullanıcıya görünmez; ekran görüntüsüyle doğrulama için.

## 9. Yerelleştirme

- Tüm yeni metinler `"İngilizce anahtar".local` ile geçer; anahtarlar en, zh-Hans, zh-Hant dosyalarına (Çince karşılıklarıyla) eklenir.
- `tr.lproj/Localizable.strings` ve `InfoPlist.strings` oluşturulur; mevcut tüm anahtarlar Türkçeye çevrilir. Bu iş son aşamadır ve tek başına geri alınabilir.

## 10. Hata yönetimi

- Geçmiş dosyası okunamıyor/bozuk → boş geçmişle devam, log satırı. Yazma hatası → log, kullanıcıya bir şey gösterilmez.
- Tahmin hiçbir koşulda çökmez: sıfıra bölme, negatif süre, boş faz hepsi `.none`.
- `_Left/_Right/_All` gibi türetilmiş kimlikler ayrı geçmiş tutar; sorun değil.
- Depo erişimi `NSLock` ile korunur; `updateHook` kilit dışında çağrıldığı için model kilidiyle iç içe kilit olmaz.

## 11. Test ve doğrulama

- Paket: `swift test` (Command Line Tools yeter). Testler: kayıt kuralları (dedupe, kalp atışı, saklama), faz kesme (şarj değişimi, 3 puan yükselme, saat geri gitmesi), yetersiz veri → none, boşalma ve şarj hesabı, 30 gün sınırı, yuvarlama tabloları.
- CI: `build.yml`'e xcodebuild'den önce `swift test --package-path Packages/BatteryEstimator` adımı.
- Arayüz: her aşama sonunda CI DMG'si indirilir, uygulama oturum klasöründen `open` ile başlatılır, `open airbattery://showpopover` ve `screencapture` ile popover görüntüsü alınıp incelenir (açık/koyu). Kalan süre satırları için geçici bir geçmiş dosyası yerleştirilerek "dolu" durum da görüntülenir.
- Yerelde xcodebuild yok; olası derleme hataları için değişen dosyalarda `swiftc -typecheck` denenir, kesin hakem CI'dır.

## 12. Aşamalar

Her aşama kendi commit'i, her biri CI'da yeşil, 3 ve 4 ekran görüntüsüyle doğrulanır. Çalışma `feature/popover-redesign` dalında ilerler; DMG denenip beğenildikten sonra `main`'e alınır.

1. `BatteryEstimator` paketi + testler + CI test adımı.
2. `BatteryHistoryStore` + model kancası + `iBattery.timeRemaining` + URL komutları + pbxproj dosya ekleri.
3. `DeviceCardView` + popover/Dock restile + boyutlandırma.
4. Menü çubuğu eki.
5. Yerelleştirme (en/zh ekleri, tr dosyaları).

## 13. Riskler

- pbxproj elle düzenleniyor; hatalı referans CI'da anında görünür, yerelde değil. Değişiklikler küçük ve betikle yapılır.
- NSPopover'ın içerik yüksekliğini doğal boyuttan alması macOS 11'de de çalışır, ancak ScrollView eşiği (640 pt) yalnızca çok cihazlı kurulumlarda devreye girer; test için geçici cihaz listesi kullanılacak.
- Tahminler ilk saatlerde çoğu cihazda görünmez; bu beklenen davranıştır, meta satırı bu durumda boş kalmaz (durum metni veya son görülme vardır).
