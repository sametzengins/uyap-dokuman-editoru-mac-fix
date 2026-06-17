# UYAP Doküman Editörü — macOS (Apple Silicon) "Unable to load Java" Çözümü

UYAP Doküman Editörü'nü (`Uyap Doküman Editörü.app`) Apple Silicon (M1/M2/M3/M4) Mac'lerde
açmaya çalışınca alınan **"Unable to load Java Runtime Environment"** hatasının kalıcı çözümü.

> Bilgisayarınıza Java/JDK kurmanıza rağmen uygulama açılmıyorsa, sorun büyük ihtimalle
> kurduğunuz Java'nın **yanlış mimaride (arm64)** olması ve uygulamanın **eski başlatıcısının**
> modern macOS'ta düzgün çalışmamasıdır. Bu depo iki sorunu da çözer.

---

## 🔴 Sorun neydi?

Uygulamayı incelediğimizde iki ayrı kök neden tespit edildi:

### 1) Mimari uyumsuzluğu (asıl "Unable to load Java" hatası)
- Uygulamanın `Contents/MacOS/JavaAppLauncher` başlatıcısı **x86_64 (Intel)** bir programdır;
  Apple Silicon'da **Rosetta** altında çalışır ve **yalnızca x86_64 bir Java** yükleyebilir.
- Apple Silicon Mac'lere kurulan modern JDK'ler (Oracle JDK, Corretto, vb.) genelde **arm64**'tür.
- x86_64 bir süreç, arm64 bir `libjli.dylib`'i yükleyemez → **"Unable to load Java Runtime Environment"**.
- Yani kurduğunuz arm64 JDK, başlatıcı tarafından **yüklenemez**; üstelik kullanılsa bile
  uygulamanın kendi kodu **Java 6–14** sürüm aralığını şart koşar (daha yenisini reddeder).

### 2) Erken kapanma (race condition)
- Doğru mimaride bir Java verilse bile, eski Oracle "appbundler" başlatıcısı JVM'i **ikincil bir
  thread'de** çalıştırıp Java `main()` metodu döner dönmez JVM'i yok eder. Modern macOS / Apple
  Silicon'da bu, AWT pencere thread'i daha pencereyi açamadan uygulamanın **~3 saniyede
  kapanmasına** yol açar (uygulama bir an açılıp hemen kapanır).

---

## 🟢 Çözüm

1. **Uygulamanın içine x86_64 bir Java 8 (Eclipse Temurin) gömülür** → uygulama kendi kendine
   yeterli hâle gelir, sisteme ayrı Java kurmaya gerek kalmaz. `Info.plist`'e `JVMRuntime`
   anahtarı eklenir.
2. **Hatalı native başlatıcı, standart `java` komutunu doğrudan çağıran bir shell başlatıcı ile
   değiştirilir** → AWT olay döngüsü düzgün yaşar, editör penceresi açık kalır.
3. **Uygulama yeniden imzalanır** (ad-hoc), çünkü dosya değişiklikleri orijinal imzayı bozar.

Bu depodaki [`JavaAppLauncher`](JavaAppLauncher) dosyası, uygulamanın içine konan yeni başlatıcıdır.

---

## 🚀 Otomatik kurulum (önerilen)

[`uyap-editor-fix.sh`](uyap-editor-fix.sh) scripti tüm adımları sizin için yapar.

```bash
# 1) Bu depoyu indirin
git clone https://github.com/<KULLANICI>/uyap-dokuman-editoru-mac-fix.git
cd uyap-dokuman-editoru-mac-fix

# 2) Scripti uygulamanızın yolu ile çalıştırın
chmod +x uyap-editor-fix.sh
./uyap-editor-fix.sh "/Applications/Uyap Doküman Editörü.app"
```

> Uygulama nerede ise o yolu verin (ör. `~/Downloads/Uyap Doküman Editörü.app`).
> Script çalışmadan önce uygulamanın bir yedeğini (`.app.bak`) alır.

### Java 8 gereksinimi
Script, sistemde **x86_64** mimaride bir Java (8–14) arar ve uygulamanın içine kopyalar.
Bulamazsa, ücretsiz **Eclipse Temurin 8 (x64 / Intel)** kurmanızı ister:

- https://adoptium.net/temurin/releases/?version=8&os=mac&arch=x64

> ⚠️ Mutlaka **x64 (Intel)** paketini seçin, aarch64 (Apple Silicon) değil.

---

## 🛠️ Elle (manuel) çözüm

Scripti kullanmak istemezseniz adımlar şunlardır (Terminal'de). `APP` değişkenini kendi yolunuza göre ayarlayın:

```bash
APP="/Applications/Uyap Doküman Editörü.app"
JDK="/Library/Java/JavaVirtualMachines/temurin-8.jdk"   # x86_64 Java 8

# 0) Yedek
cp -R "$APP" "$APP.bak"

# 1) x86_64 Java'yı uygulamaya göm
mkdir -p "$APP/Contents/PlugIns"
cp -R "$JDK" "$APP/Contents/PlugIns/temurin-8.jdk"

# 2) Info.plist'e JVMRuntime ekle
/usr/libexec/PlistBuddy -c "Add :JVMRuntime string temurin-8.jdk" "$APP/Contents/Info.plist"

# 3) Native başlatıcıyı shell başlatıcı ile değiştir
mv "$APP/Contents/MacOS/JavaAppLauncher" "$APP/Contents/MacOS/JavaAppLauncher.orig-native"
cp JavaAppLauncher "$APP/Contents/MacOS/JavaAppLauncher"
chmod +x "$APP/Contents/MacOS/JavaAppLauncher"

# 4) Yeniden imzala (ad-hoc)
codesign --remove-signature "$APP" 2>/dev/null
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null

# 5) Aç
open "$APP"
```

---

## ❓ İnternette dolaşan diğer "çözümler"
- **"Oracle Java 8 kurun"**: Doğru sürüm (Java 8) ama Apple Silicon'da **x64 (Intel)** paketini
  kurmazsanız yine açılmaz. Bu depodaki yöntem Java'yı uygulamanın içine gömdüğü için ayrıca
  sistem kurulumuna gerek bırakmaz.
- **"`~/.uki` içindeki `acilisDegerleri.xml`, `lastOpened.xml`, `tercihler.xml` dosyalarını silin"**:
  Bozuk ayar dosyaları için zararsız bir sıfırlamadır, ancak Apple Silicon'daki "Unable to load Java"
  sorununun **asıl nedeni bu değildir**.

---

## ⚠️ Notlar / Sorumluluk Reddi
- Bu depo **yalnızca düzeltme scripti, yeni başlatıcı ve açıklama** içerir. UYAP Doküman Editörü'nün
  kendisi (telifli yazılım) burada **dağıtılmaz**; düzeltmeyi kendi yasal kurulumunuza uygularsınız.
- UYAP Doküman Editörü, T.C. Adalet Bakanlığı / HAVELSAN'a aittir. Resmî indirme adresinden temin edin.
- Eclipse Temurin, Eclipse Adoptium projesinin ücretsiz ve yeniden dağıtılabilir bir OpenJDK dağıtımıdır.
- Bu içerik bağımsız bir topluluk çözümüdür; UYAP, Adalet Bakanlığı veya HAVELSAN ile bir bağlantısı yoktur.
- Kendi sorumluluğunuzda kullanın. Script, işlem öncesi yedek alır.

## Lisans
Bu depodaki scriptler ve başlatıcı [MIT Lisansı](LICENSE) ile sunulur.
