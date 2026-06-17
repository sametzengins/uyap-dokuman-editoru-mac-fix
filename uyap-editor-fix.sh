#!/bin/bash
#
# UYAP Doküman Editörü - macOS (Apple Silicon) "Unable to load Java" düzeltmesi
# https://github.com/sametzengins/uyap-dokuman-editoru-mac-fix
#
# Kullanım:
#   ./uyap-editor-fix.sh "/Applications/Uyap Doküman Editörü.app"
#
# Yaptıkları:
#   1) Uygulamanın yedeğini alır (.app.bak)
#   2) Sistemde x86_64 (Intel) bir Java (8-14) bulup uygulamanın içine gömer
#   3) Info.plist'e JVMRuntime ekler
#   4) Hatalı native başlatıcıyı, standart java'yı çağıran shell başlatıcı ile değiştirir
#   5) Uygulamayı ad-hoc yeniden imzalar
#
set -euo pipefail

err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
info() { printf '\033[36m• %s\033[0m\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

# --- 0) Uygulama yolu ---
APP="${1:-}"
if [ -z "$APP" ]; then
  for c in "/Applications/Uyap Doküman Editörü.app" \
           "$HOME/Downloads/Uyap Doküman Editörü.app" \
           "$HOME/Desktop/Uyap Doküman Editörü.app"; do
    [ -d "$c" ] && APP="$c" && break
  done
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  err "Uygulama bulunamadı."
  echo "Kullanım: $0 \"/Applications/Uyap Doküman Editörü.app\""
  exit 1
fi
APP="${APP%/}"
info "Uygulama: $APP"

LAUNCHER="$APP/Contents/MacOS/JavaAppLauncher"
PLIST="$APP/Contents/Info.plist"
[ -f "$PLIST" ] || { err "Info.plist yok, bu geçerli bir .app değil."; exit 1; }

# --- helper: bir Java Home'un libjli yolunu ve mimarisini/sürümünü bul ---
find_libjli() {  # $1 = Home
  for p in "$1/jre/lib/jli/libjli.dylib" "$1/lib/jli/libjli.dylib" "$1/lib/libjli.dylib"; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}
major_of() {  # $1 = Home ; release dosyasından JAVA_VERSION
  local rel="$1/release" v=""
  [ -f "$rel" ] && v="$(/usr/bin/grep -m1 '^JAVA_VERSION=' "$rel" | /usr/bin/sed -E 's/.*"([^"]+)".*/\1/')"
  [ -z "$v" ] && return 1
  case "$v" in
    1.8*) echo 8 ;;
    1.7*) echo 7 ;;
    1.6*) echo 6 ;;
    *)    echo "${v%%.*}" ;;
  esac
}

# --- 1) x86_64 Java (8-14) ara ---
info "x86_64 (Intel) Java (8-14) aranıyor..."
SRC_JDK=""; SRC_MAJOR=""
CANDIDATES=()
for base in /Library/Java/JavaVirtualMachines "$HOME/Library/Java/JavaVirtualMachines"; do
  [ -d "$base" ] || continue
  while IFS= read -r home; do CANDIDATES+=("$home"); done < <(/usr/bin/find "$base" -maxdepth 2 -name Home -path '*/Contents/Home' 2>/dev/null)
done
for home in "${CANDIDATES[@]:-}"; do
  [ -d "$home" ] || continue
  jli="$(find_libjli "$home")" || continue
  /usr/bin/file "$jli" 2>/dev/null | /usr/bin/grep -q x86_64 || continue
  m="$(major_of "$home" || echo 0)"
  if [ "$m" -ge 8 ] && [ "$m" -le 14 ]; then
    # Java 8'i tercih et
    if [ -z "$SRC_JDK" ] || { [ "$m" = "8" ] && [ "$SRC_MAJOR" != "8" ]; }; then
      SRC_JDK="$home"; SRC_MAJOR="$m"
    fi
  fi
done

if [ -z "$SRC_JDK" ]; then
  err "Uygun x86_64 (Intel) Java 8-14 bulunamadı."
  echo
  echo "Lütfen ücretsiz Eclipse Temurin 8 (x64 / Intel) kurun:"
  echo "  https://adoptium.net/temurin/releases/?version=8&os=mac&arch=x64"
  echo "  (Mutlaka x64 / Intel paketi; aarch64 DEĞİL.)"
  echo "Kurduktan sonra bu scripti tekrar çalıştırın."
  exit 1
fi
# SRC_JDK = .../Contents/Home  ->  .jdk bundle kökü
SRC_BUNDLE="$(cd "$SRC_JDK/../.." >/dev/null 2>&1 && pwd)"
RT_NAME="$(basename "$SRC_BUNDLE")"
ok "Bulundu: $RT_NAME (Java $SRC_MAJOR, x86_64) -> $SRC_BUNDLE"

# --- 2) Yedek ---
if [ ! -e "$APP.bak" ]; then
  info "Yedek alınıyor: $APP.bak"
  cp -R "$APP" "$APP.bak"
  ok "Yedek alındı."
else
  info "Yedek zaten var: $APP.bak (atlanıyor)"
fi

# --- 3) JDK'yı göm ---
info "Java uygulamanın içine kopyalanıyor..."
mkdir -p "$APP/Contents/PlugIns"
rm -rf "$APP/Contents/PlugIns/$RT_NAME"
cp -R "$SRC_BUNDLE" "$APP/Contents/PlugIns/$RT_NAME"
find_libjli "$APP/Contents/PlugIns/$RT_NAME/Contents/Home" >/dev/null || { err "Gömülen JRE'de libjli bulunamadı."; exit 1; }
ok "Gömüldü: Contents/PlugIns/$RT_NAME"

# --- 4) Info.plist: JVMRuntime ---
/usr/libexec/PlistBuddy -c "Delete :JVMRuntime" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :JVMRuntime string $RT_NAME" "$PLIST"
ok "Info.plist: JVMRuntime = $RT_NAME"

# --- 5) Başlatıcıyı değiştir ---
if [ -f "$LAUNCHER" ] && ! head -1 "$LAUNCHER" 2>/dev/null | grep -q '^#!'; then
  # Hâlâ native binary ise yedekle
  mv -f "$LAUNCHER" "$APP/Contents/MacOS/JavaAppLauncher.orig-native"
  info "Orijinal native başlatıcı yedeklendi (JavaAppLauncher.orig-native)"
fi
if [ -f "$SCRIPT_DIR/JavaAppLauncher" ]; then
  cp "$SCRIPT_DIR/JavaAppLauncher" "$LAUNCHER"
else
  err "Yanındaki JavaAppLauncher dosyası bulunamadı ($SCRIPT_DIR/JavaAppLauncher)."
  exit 1
fi
chmod +x "$LAUNCHER"
ok "Shell başlatıcı yerleştirildi."

# --- 6) Yeniden imzala ---
info "Uygulama yeniden imzalanıyor (ad-hoc)..."
codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 && ok "İmza geçerli." || err "İmza doğrulanamadı (yine de çalışabilir)."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo
ok "Tamamlandı! Açmak için:  open \"$APP\""
echo "  (Sorun olursa yedek: \"$APP.bak\")"
