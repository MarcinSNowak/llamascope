#!/bin/bash
#
# Budowa wersji do rozdania: podpis Developer ID, notaryzacja, .dmg.
#
# Dlaczego skrypt, a nie lista kroków w dokumencie: kroków jest osiem,
# siedem z nich milczy, gdy się uda, a jeden — ten z notaryzacją — trwa
# kilka minut. Lista w dokumencie po trzecim wydaniu jest nieaktualna
# i nikt tego nie zauważa, dopóki ktoś obcy nie dostanie pakietu, którego
# nie da się otworzyć.
#
# Każde sprawdzenie tutaj kończy budowę. To jest celowe: pakiet podpisany
# w połowie wygląda dokładnie tak samo jak podpisany w całości, dopóki nie
# trafi na cudzy komputer.
#
# Użycie:
#   ./wydanie.sh              — buduje, podpisuje, notaryzuje, robi .dmg
#   ./wydanie.sh --bez-notaryzacji — wszystko oprócz notaryzacji (szybkie)
#
# Wymaga raz, przed pierwszym użyciem:
#   xcrun notarytool store-credentials llamascope \
#       --apple-id <twój-apple-id> --team-id 83L8M7P67X
# (poprosi o hasło dla aplikacji z appleid.apple.com — hasło idzie prosto
# do pęku kluczy i nie zostaje w żadnym pliku)

set -euo pipefail

TEAM_ID="83L8M7P67X"
PROFILE="llamascope"
SCHEME="LlamaScope"
APP_NAME="LlamaScope"
ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGING="$ROOT/build/dmg"
OUTPUT="$ROOT/build"

NOTARIZE="yes"
[ "${1:-}" = "--bez-notaryzacji" ] && NOTARIZE="no"

krok() { printf '\n\033[1m%s\033[0m\n' "$*"; }
zle()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------
krok "1/8  Testy"
# Wersja do rozdania z czerwonymi testami to nie wersja, tylko kłopot
# rozesłany szerzej.
#
# Wypisujemy podsumowania XCTest, a nie ostatnie linie wyjścia. Na końcu
# stoi podsumowanie swift-testing, które mówi „0 tests … passed”, bo ten
# pakiet używa XCTest — czyli zielone zdanie o czymś, czego nie policzono.
log="$(mktemp)"
( cd "$ROOT/app/Core" && swift test ) > "$log" 2>&1 \
    || { grep -E "error:|failed" "$log" | head -20; zle "testy nie przechodzą"; }
grep -E "^Test Suite '.*xctest' (passed|failed)" -A1 "$log" | grep -E "Executed" \
    || zle "nie widzę ani jednego podsumowania XCTest — czy test w ogóle poszedł?"
rm -f "$log"

# ---------------------------------------------------------------------
krok "2/8  Budowa od zera"
# `clean` nie jest ostrożnością. Budowa przyrostowa **nie kopiuje na nowo**
# pośrednika do pakietu, więc po zmianie ustawień podpisu w środku zostaje
# stary plik z podpisem ad-hoc — a `codesign --verify --deep` i tak mówi
# wtedy „valid on disk”. Raz już na to weszliśmy.
( cd "$ROOT/app" && xcodegen generate >/dev/null )
( cd "$ROOT/app" && xcodebuild -scheme "$SCHEME" -configuration Release \
    clean build 2>&1 | grep -E "error:|BUILD" )

APP="$(cd "$ROOT/app" && xcodebuild -scheme "$SCHEME" -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR/ {print $3}' | head -1)/$APP_NAME.app"
[ -d "$APP" ] || zle "nie widzę pakietu: $APP"
echo "pakiet: $APP"

# ---------------------------------------------------------------------
krok "3/8  Podpis — każdy plik wykonywalny z osobna"
# `--deep` tutaj nie wystarcza i nie o nim mowa: sprawdzamy **każdy**
# plik wykonywalny w pakiecie po kolei, bo notaryzacja robi dokładnie to
# samo, a chcemy się dowiedzieć teraz, a nie za dziesięć minut od Apple.
while IFS= read -r binary; do
    info="$(codesign -dv --verbose=2 "$binary" 2>&1)"
    echo "$info" | grep -q "TeamIdentifier=$TEAM_ID" \
        || zle "podpis ad-hoc albo cudzy: $binary"
    echo "$info" | grep -q "flags=.*runtime" \
        || zle "brak hardened runtime: $binary"
    # Uprawnienie do podpięcia debuggera. Xcode dokłada je przy `build`,
    # notaryzacja odrzuca zawsze. Sprawdzamy tutaj, bo dowiedzieć się
    # tego od Apple kosztuje pięć minut czekania i komunikat o CloudKicie.
    codesign -d --entitlements - --xml "$binary" 2>/dev/null \
        | grep -q "get-task-allow" \
        && zle "uprawnienie get-task-allow: $binary"
    # §12: tylko Apple Silicon. Plasterek x86_64 uruchomiłby się na
    # Intelu i pokazał odczyty GPU, które tam nic nie znaczą.
    lipo -archs "$binary" | grep -qx "arm64" \
        || zle "nie sam arm64: $binary ($(lipo -archs "$binary"))"
    echo "  ok  $(basename "$binary")"
done < <(find "$APP/Contents/MacOS" -type f -perm +111)

codesign --verify --deep --strict "$APP" || zle "pakiet nie przechodzi weryfikacji"

# ---------------------------------------------------------------------
krok "4/8  Obietnica z §9"
# Pośrednik jedzie w pakiecie jako osobny program i nie wchodzi do binarki
# aplikacji. To jest zdanie ze specyfikacji, które ktoś obcy może sprawdzić
# sam, więc musi być prawdziwe w każdym wydaniu, nie tylko w tym pierwszym.
count="$(nm "$APP/Contents/MacOS/$APP_NAME" | grep -c ProxyCore || true)"
[ "$count" = "0" ] || zle "ProxyCore wszedł do binarki aplikacji ($count symboli)"
echo "  ok  aplikacja nie zawiera kodu pośrednika"

# ---------------------------------------------------------------------
krok "5/8  Obraz .dmg"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist")"
DMG="$OUTPUT/$APP_NAME-$VERSION.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "  $DMG"

# Obraz też się podpisuje. Bez tego kwarantanna zostaje na nim samym
# i pierwsze kliknięcie wygląda na awarię.
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [ "$NOTARIZE" = "no" ]; then
    krok "Gotowe (bez notaryzacji)."
    echo "Ten obraz otworzy się tylko na tej maszynie. Do rozdania trzeba"
    echo "go przepuścić przez notaryzację — uruchom bez --bez-notaryzacji."
    exit 0
fi

# ---------------------------------------------------------------------
krok "6/8  Notaryzacja (to trwa kilka minut)"
# `notarytool submit --wait` kończy się **zerem także wtedy, gdy status
# to Invalid** — zero znaczy tu „rozmowa z Apple się udała”, a nie
# „pakiet przeszedł”. Bez tego sprawdzenia skrypt szedł dalej z pakietem
# odrzuconym i przewracał się dopiero na przyszywaniu, z komunikatem
# o CloudKicie, który nie mówi nic o przyczynie. Trzecia taka pułapka
# w tym pliku, wszystkie tej samej rodziny co `truncated = 0`.
out="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1)"
echo "$out"
id="$(echo "$out" | awk '/^ *id:/ {print $2; exit}')"
echo "$out" | grep -q "status: Accepted" || {
    printf '\n\033[31mApple odrzuciło pakiet. Powód:\033[0m\n'
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" 2>&1 \
        | grep -E '"(message|path)"' | sort -u
    zle "notaryzacja nieudana"
}

# ---------------------------------------------------------------------
krok "7/8  Przyszycie zaświadczenia"
# Bez tego kroku pakiet wymaga internetu przy pierwszym uruchomieniu.
# Zaświadczenie przyszyte do obrazu działa też bez sieci.
xcrun stapler staple "$DMG"

# ---------------------------------------------------------------------
krok "8/8  Sprawdzenie na tym, co wyjdzie z paczki"
# Najważniejsze sprawdzenie w tym pliku i jedyne, które mówi o cudzym
# komputerze: montujemy obraz i pytamy Gatekeepera o pakiet w środku.
# Pakiet zbudowany lokalnie nie ma flagi kwarantanny, więc `spctl` na nim
# przechodzi **zanim** cokolwiek zostanie notaryzowane — i właśnie dlatego
# nie wolno się nim zadowolić.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MOUNT"
verdict="$(spctl --assess --type execute --verbose=2 "$MOUNT/$APP_NAME.app" 2>&1 || true)"
hdiutil detach "$MOUNT" -quiet
rm -rf "$MOUNT"
echo "$verdict"
echo "$verdict" | grep -q "accepted" || zle "Gatekeeper odrzuca pakiet z obrazu"
echo "$verdict" | grep -q "Notarized Developer ID" \
    || zle "przeszło, ale nie jako notaryzowane — zaświadczenie się nie przyszyło"

krok "Gotowe: $DMG"
echo "Ten plik można rozdać."
