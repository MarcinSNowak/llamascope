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
# Po angielsku: ./release.sh (ten sam skrypt, inne zdania — patrz niżej).
# Komentarze w tym pliku stoją po dwa razy: polski, a pod nim ten sam
# akapit po znaczniku `# EN:`.
#
# Wymaga raz, przed pierwszym użyciem:
#   xcrun notarytool store-credentials llamascope \
#       --apple-id <twój-apple-id> --team-id 83L8M7P67X
# (poprosi o hasło dla aplikacji z appleid.apple.com — hasło idzie prosto
# do pęku kluczy i nie zostaje w żadnym pliku)
#
# ---------------------------------------------------------------------
# EN: Building a release: Developer ID signature, notarization, .dmg.
#
# EN: Every comment in this file is given twice — Polish first, then the
# same thing after an `# EN:` marker. The comments say *why* each check
# exists, and most of them exist because something once got through; that
# reasoning is the part worth reading before changing anything here, so it
# should not be readable only in Polish.
#
# EN: Why a script rather than a list of steps in a document: there are
# eight steps, seven of them say nothing when they succeed, and one — the
# notarization — takes a few minutes. A list in a document is out of date
# by the third release, and nobody notices until a stranger receives a
# package that will not open.
#
# EN: Every check here ends the build. That is deliberate: a half-signed
# package looks exactly like a fully signed one until it reaches somebody
# else's computer.
#
# EN: Usage:
#   ./release.sh                   — build, sign, notarize, make the .dmg
#   ./release.sh --no-notarization — everything except notarization (fast)
#
# EN: Required once, before the first run:
#   xcrun notarytool store-credentials llamascope \
#       --apple-id <your-apple-id> --team-id 83L8M7P67X
# (it asks for an app-specific password from appleid.apple.com — the
# password goes straight into the keychain and is left in no file)

set -euo pipefail

TEAM_ID="83L8M7P67X"
PROFILE="llamascope"
SCHEME="LlamaScope"
APP_NAME="LlamaScope"
ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGING="$ROOT/build/dmg"
OUTPUT="$ROOT/build"

NOTARIZE="yes"
case "${1:-}" in --bez-notaryzacji|--no-notarization) NOTARIZE="no" ;; esac

# ---------------------------------------------------------------------
# Zdania, w dwóch językach.
#
# Angielska wersja tego pliku to `release.sh` i jest **jedną linijką**,
# która woła ten skrypt z LLAMASCOPE_LANG=en. Nie jest tłumaczeniem, i to
# jest cała rzecz: druga kopia tych ośmiu kroków rozjechałaby się z tą przy
# pierwszym sprawdzeniu dopisanym tylko do jednej z nich — po cichu i
# w tę stronę, która przepuszcza złe wydanie. Sprawdzenia są więc w jednym
# egzemplarzu, a zdania w dwóch.
#
# `msg` przerywa, gdy klucza brakuje w którymś języku. Bez tego brakujące
# tłumaczenie dałoby pusty komunikat — czyli krok, który wygląda, jakby
# przeszedł bez słowa. Ta sama rodzina co `truncated = 0`.
#
# EN: The sentences, in two languages.
#
# EN: The English version of this file is `release.sh`, and it is a
# **single line** that calls this script with LLAMASCOPE_LANG=en. It is not
# a translation, and that is the whole point: a second copy of these eight
# steps would drift from this one the moment a check is added to only one
# of them — quietly, and in the direction that lets a bad release through.
# So the checks exist in one copy and the sentences in two.
#
# EN: `msg` aborts when a key is missing in either language. Without that,
# a missing translation would produce an empty message — a step that looks
# as if it passed without a word. Same family as `truncated = 0`.
LANGUAGE="${LLAMASCOPE_LANG:-pl}"

tekst_pl() {
    case "$1" in
    krok_testy)      echo '1/8  Testy' ;;
    testy_czerwone)  echo 'testy nie przechodzą' ;;
    brak_podsumowan) echo 'nie widzę ani jednego podsumowania XCTest — czy test w ogóle poszedł?' ;;
    krok_budowa)     echo '2/8  Budowa od zera' ;;
    ikona_skrypt)    echo 'skrypt ikony się wywrócił' ;;
    ikona_rozjazd)   echo 'ikona w repozytorium nie zgadza się ze skryptem — zatwierdź nową' ;;
    wersja_rozjazd)  echo 'LlamaScopeVersion.current nie zgadza się z MARKETING_VERSION (%s)' ;;
    brak_pakietu)    echo 'nie widzę pakietu: %s' ;;
    pakiet)          echo 'pakiet: %s' ;;
    krok_podpis)     echo '3/8  Podpis — każdy plik wykonywalny z osobna' ;;
    podpis_obcy)     echo 'podpis ad-hoc albo cudzy: %s' ;;
    brak_runtime)    echo 'brak hardened runtime: %s' ;;
    task_allow)      echo 'uprawnienie get-task-allow: %s' ;;
    nie_arm64)       echo 'nie sam arm64: %s (%s)' ;;
    weryfikacja)     echo 'pakiet nie przechodzi weryfikacji' ;;
    krok_obietnica)  echo '4/8  Obietnica z §9' ;;
    proxy_w_app)     echo 'ProxyCore wszedł do binarki aplikacji (%s symboli)' ;;
    ok_bez_proxy)    echo '  ok  aplikacja nie zawiera kodu pośrednika' ;;
    brak_wpisu)      echo 'brak CFBundleIconFile w Info.plist' ;;
    brak_ikony)      echo 'brak pliku ikony w pakiecie' ;;
    ok_ikona)        echo '  ok  pakiet ma ikonę' ;;
    krok_obraz)      echo '5/8  Obraz .dmg' ;;
    brak_wolumenu)   echo 'obraz nie ma ikony woluminu (atrybuty: %s)' ;;
    ok_wolumen)      echo '  ok  obraz ma ikonę woluminu' ;;
    gotowe_bez)      echo 'Gotowe (bez notaryzacji).' ;;
    tylko_tutaj)     echo 'Ten obraz otworzy się tylko na tej maszynie. Do rozdania trzeba' ;;
    tylko_tutaj2)    echo 'go przepuścić przez notaryzację — uruchom bez --bez-notaryzacji.' ;;
    krok_notaryzacja) echo '6/8  Notaryzacja (to trwa kilka minut)' ;;
    apple_odrzucilo) echo 'Apple odrzuciło pakiet. Powód:' ;;
    notaryzacja_zla) echo 'notaryzacja nieudana' ;;
    krok_przyszycie) echo '7/8  Przyszycie zaświadczenia' ;;
    krok_sprawdzenie) echo '8/8  Sprawdzenie na tym, co wyjdzie z paczki' ;;
    gatekeeper_nie)  echo 'Gatekeeper odrzuca pakiet z obrazu' ;;
    bez_zaswiadczenia) echo 'przeszło, ale nie jako notaryzowane — zaświadczenie się nie przyszyło' ;;
    gotowe)          echo 'Gotowe: %s' ;;
    do_rozdania)     echo 'Ten plik można rozdać.' ;;
    esac
}

tekst_en() {
    case "$1" in
    krok_testy)      echo '1/8  Tests' ;;
    testy_czerwone)  echo 'the tests are failing' ;;
    brak_podsumowan) echo 'not one XCTest summary in the output — did the tests run at all?' ;;
    krok_budowa)     echo '2/8  Clean build' ;;
    ikona_skrypt)    echo 'the icon script fell over' ;;
    ikona_rozjazd)   echo 'the icon in the repository does not match the script — commit the new one' ;;
    wersja_rozjazd)  echo 'LlamaScopeVersion.current does not match MARKETING_VERSION (%s)' ;;
    brak_pakietu)    echo 'no bundle here: %s' ;;
    pakiet)          echo 'bundle: %s' ;;
    krok_podpis)     echo '3/8  Signature — every executable on its own' ;;
    podpis_obcy)     echo 'ad-hoc or somebody else’s signature: %s' ;;
    brak_runtime)    echo 'no hardened runtime: %s' ;;
    task_allow)      echo 'get-task-allow entitlement: %s' ;;
    nie_arm64)       echo 'not arm64 alone: %s (%s)' ;;
    weryfikacja)     echo 'the bundle does not pass verification' ;;
    krok_obietnica)  echo '4/8  The promise from §9' ;;
    proxy_w_app)     echo 'ProxyCore got into the app binary (%s symbols)' ;;
    ok_bez_proxy)    echo '  ok  the app contains no proxy code' ;;
    brak_wpisu)      echo 'no CFBundleIconFile in Info.plist' ;;
    brak_ikony)      echo 'no icon file in the bundle' ;;
    ok_ikona)        echo '  ok  the bundle has an icon' ;;
    krok_obraz)      echo '5/8  The .dmg image' ;;
    brak_wolumenu)   echo 'the image has no volume icon (attributes: %s)' ;;
    ok_wolumen)      echo '  ok  the image has a volume icon' ;;
    gotowe_bez)      echo 'Done (without notarization).' ;;
    tylko_tutaj)     echo 'This image will only open on this machine. To hand it out, put' ;;
    tylko_tutaj2)    echo 'it through notarization — run without --no-notarization.' ;;
    krok_notaryzacja) echo '6/8  Notarization (this takes a few minutes)' ;;
    apple_odrzucilo) echo 'Apple rejected the package. Reason:' ;;
    notaryzacja_zla) echo 'notarization failed' ;;
    krok_przyszycie) echo '7/8  Stapling the ticket' ;;
    krok_sprawdzenie) echo '8/8  Checking the thing that comes out of the image' ;;
    gatekeeper_nie)  echo 'Gatekeeper rejects the app from the image' ;;
    bez_zaswiadczenia) echo 'accepted, but not as notarized — the ticket did not staple' ;;
    gotowe)          echo 'Done: %s' ;;
    do_rozdania)     echo 'This file can be handed out.' ;;
    esac
}

msg() {
    local key="$1"; shift
    local fmt
    fmt="$("tekst_$LANGUAGE" "$key")"
    [ -n "$fmt" ] || {
        printf '\033[31mbrak zdania dla klucza „%s" w języku %s\033[0m\n' \
            "$key" "$LANGUAGE" >&2
        exit 1
    }
    # shellcheck disable=SC2059 — wzorzec pochodzi z tablicy wyżej, nie z zewnątrz
    # EN: the format string comes from the table above, never from outside
    printf "$fmt" "$@"
}

krok() { printf '\n\033[1m%s\033[0m\n' "$*"; }
zle()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------
krok "$(msg krok_testy)"
# Wersja do rozdania z czerwonymi testami to nie wersja, tylko kłopot
# rozesłany szerzej.
#
# Wypisujemy podsumowania XCTest, a nie ostatnie linie wyjścia. Na końcu
# stoi podsumowanie swift-testing, które mówi „0 tests … passed”, bo ten
# pakiet używa XCTest — czyli zielone zdanie o czymś, czego nie policzono.
#
# EN: A release with failing tests is not a release, just trouble sent to
# more people.
#
# EN: We print the XCTest summaries, not the last lines of the output. The
# very last line is a swift-testing summary saying "0 tests … passed",
# because this package uses XCTest — a green sentence about something that
# was never counted.
log="$(mktemp)"
( cd "$ROOT/app/Core" && swift test ) > "$log" 2>&1 \
    || { grep -E "error:|failed" "$log" | head -20; zle "$(msg testy_czerwone)"; }
grep -E "^Test Suite '.*xctest' (passed|failed)" -A1 "$log" | grep -E "Executed" \
    || zle "$(msg brak_podsumowan)"
rm -f "$log"

# ---------------------------------------------------------------------
krok "$(msg krok_budowa)"
# `clean` nie jest ostrożnością. Budowa przyrostowa **nie kopiuje na nowo**
# pośrednika do pakietu, więc po zmianie ustawień podpisu w środku zostaje
# stary plik z podpisem ad-hoc — a `codesign --verify --deep` i tak mówi
# wtedy „valid on disk”. Raz już na to weszliśmy.
# Ikona jest rysowana skryptem, a w repozytorium leży gotowy .icns — żeby
# budowa nie wymagała uruchamiania niczego poza Xcode. Dwa źródła tego
# samego obrazka mogą się rozjechać, więc przed budową odtwarzamy plik
# i porównujemy. Plik zostaje odtworzony, ale różnica przerywa wydanie:
# znaczy, że ktoś zmienił skrypt i nie przepuścił nowej ikony przez
# repozytorium, a to jest rzecz do zauważenia teraz, nie po wydaniu.
#
# EN: `clean` is not caution here. An incremental build does **not**
# re-copy the proxy into the bundle, so after a change to the signing
# settings the old ad-hoc-signed file stays inside — and
# `codesign --verify --deep` still calls that "valid on disk". We walked
# into this once already.
# EN: The icon is drawn by a script, and a ready-made .icns sits in the
# repository so that building needs nothing beyond Xcode. Two sources of
# the same picture can drift apart, so before the build we regenerate the
# file and compare. The file is left regenerated, but a difference ends
# the release: it means somebody changed the script without putting the
# new icon through the repository, and that is a thing to notice now
# rather than after shipping.
icns="$ROOT/app/App/Resources/LlamaScope.icns"
before="$(shasum -a 256 "$icns" | cut -d' ' -f1)"
( cd "$ROOT" && swift ikona.swift >/dev/null ) || zle "$(msg ikona_skrypt)"
[ "$before" = "$(shasum -a 256 "$icns" | cut -d' ' -f1)" ] \
    || zle "$(msg ikona_rozjazd)"

# Sonda z wiersza poleceń nie ma Info.plist, więc numer wydania trzyma
# w kodzie. Rozjazd z `project.yml` nie wywalałby niczego — dałby paczkę
# diagnostyczną (§10) z nieprawdziwą wersją w pierwszym wierszu, czyli
# liczbę wyglądającą na odczytaną, a wziętą sprzed trzech szczebli.
#
# EN: The command-line probe has no Info.plist, so it keeps the release
# number in code. Drift from `project.yml` would break nothing — it would
# produce a diagnostic bundle (§10) with an untrue version on its first
# line: a number that looks read off the running app but was taken three
# rungs ago.
yml_version="$(awk -F'"' '/MARKETING_VERSION/ {print $2}' "$ROOT/app/project.yml")"
grep -q "\"$yml_version\"" "$ROOT/app/Core/Sources/LlamaScopeCore/LlamaScopeVersion.swift" \
    || zle "$(msg wersja_rozjazd "$yml_version")"

( cd "$ROOT/app" && xcodegen generate >/dev/null )
( cd "$ROOT/app" && xcodebuild -scheme "$SCHEME" -configuration Release \
    clean build 2>&1 | grep -E "error:|BUILD" )

APP="$(cd "$ROOT/app" && xcodebuild -scheme "$SCHEME" -configuration Release \
    -showBuildSettings 2>/dev/null \
    | awk '/ BUILT_PRODUCTS_DIR/ {print $3}' | head -1)/$APP_NAME.app"
[ -d "$APP" ] || zle "$(msg brak_pakietu "$APP")"
msg pakiet "$APP"; echo

# ---------------------------------------------------------------------
krok "$(msg krok_podpis)"
# `--deep` tutaj nie wystarcza i nie o nim mowa: sprawdzamy **każdy**
# plik wykonywalny w pakiecie po kolei, bo notaryzacja robi dokładnie to
# samo, a chcemy się dowiedzieć teraz, a nie za dziesięć minut od Apple.
#
# EN: `--deep` is not enough here and is not what this is about: we check
# **every** executable in the bundle one at a time, because notarization
# does exactly the same, and we would rather find out now than in ten
# minutes from Apple.
while IFS= read -r binary; do
    info="$(codesign -dv --verbose=2 "$binary" 2>&1)"
    echo "$info" | grep -q "TeamIdentifier=$TEAM_ID" \
        || zle "$(msg podpis_obcy "$binary")"
    echo "$info" | grep -q "flags=.*runtime" \
        || zle "$(msg brak_runtime "$binary")"
    # Uprawnienie do podpięcia debuggera. Xcode dokłada je przy `build`,
    # notaryzacja odrzuca zawsze. Sprawdzamy tutaj, bo dowiedzieć się
    # tego od Apple kosztuje pięć minut czekania i komunikat o CloudKicie.
    #
    # EN: the entitlement that lets a debugger attach. Xcode adds it on
    # `build`; notarization rejects it every time. We check here because
    # learning it from Apple costs five minutes of waiting and an error
    # message about CloudKit that says nothing about the cause.
    codesign -d --entitlements - --xml "$binary" 2>/dev/null \
        | grep -q "get-task-allow" \
        && zle "$(msg task_allow "$binary")"
    # §12: tylko Apple Silicon. Plasterek x86_64 uruchomiłby się na
    # Intelu i pokazał odczyty GPU, które tam nic nie znaczą.
    #
    # EN: §12, Apple Silicon only. An x86_64 slice would launch on an
    # Intel Mac and show GPU readings that mean nothing there.
    lipo -archs "$binary" | grep -qx "arm64" \
        || zle "$(msg nie_arm64 "$binary" "$(lipo -archs "$binary")")"
    echo "  ok  $(basename "$binary")"
done < <(find "$APP/Contents/MacOS" -type f -perm +111)

codesign --verify --deep --strict "$APP" || zle "$(msg weryfikacja)"

# ---------------------------------------------------------------------
krok "$(msg krok_obietnica)"
# Pośrednik jedzie w pakiecie jako osobny program i nie wchodzi do binarki
# aplikacji. To jest zdanie ze specyfikacji, które ktoś obcy może sprawdzić
# sam, więc musi być prawdziwe w każdym wydaniu, nie tylko w tym pierwszym.
#
# EN: the proxy travels in the bundle as a separate program and does not
# enter the app binary. That is a sentence from the specification which a
# stranger can check for themselves, so it has to be true in every
# release, not only the first one.
count="$(nm "$APP/Contents/MacOS/$APP_NAME" | grep -c ProxyCore || true)"
[ "$count" = "0" ] || zle "$(msg proxy_w_app "$count")"
msg ok_bez_proxy; echo

# Ikona w pakiecie. Dwie osobne rzeczy, bo każda z nich potrafi zniknąć
# sama: wpis w Info.plist (zmiana w project.yml bez `xcodegen generate`)
# i sam plik (kopiowanie zasobów, które cicho się nie wykonało). Pakiet
# z wpisem bez pliku wygląda w Finderze tak samo jak pakiet bez ikony.
#
# EN: the icon in the bundle. Two separate things, because each can
# vanish on its own: the Info.plist entry (a change in project.yml
# without `xcodegen generate`) and the file itself (a resource copy that
# quietly did not run). A bundle with the entry but no file looks in
# Finder exactly like a bundle with no icon at all.
/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP/Contents/Info.plist" \
    >/dev/null 2>&1 || zle "$(msg brak_wpisu)"
[ -s "$APP/Contents/Resources/LlamaScope.icns" ] \
    || zle "$(msg brak_ikony)"
msg ok_ikona; echo

# ---------------------------------------------------------------------
krok "$(msg krok_obraz)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist")"
DMG="$OUTPUT/$APP_NAME-$VERSION.dmg"
RW="$OUTPUT/$APP_NAME-$VERSION-rw.dmg"
MOUNT="$OUTPUT/mnt"
rm -rf "$STAGING" "$DMG" "$RW" "$MOUNT"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Obraz powstaje w dwóch krokach, a nie w jednym, i to nie jest komplikacja
# dla ozdoby. Ikona woluminu — ta, którą widać po zamontowaniu — wymaga
# **flagi** własnej ikony na katalogu głównym woluminu, a nie tylko pliku
# `.VolumeIcon.icns`. Flaga postawiona na katalogu montażowym nie przechodzi
# przez `hdiutil create -srcfolder`: plik ląduje w obrazie, flagi nie ma,
# a Finder pokazuje zwykły szary dysk. Sprawdzone, nie wywnioskowane.
# Więc: obraz zapisywalny, zamontować, postawić flagę, odmontować, dopiero
# potem skompresować do postaci do rozdania.
#
# EN: the image is made in two steps rather than one, and that is not
# complication for its own sake. The volume icon — the one you see after
# mounting — needs the custom-icon **flag** on the volume's root
# directory, not just a `.VolumeIcon.icns` file. A flag set on the
# staging directory does not survive `hdiutil create -srcfolder`: the
# file lands in the image, the flag does not, and Finder shows an
# ordinary grey disk. Measured, not deduced. So: a writable image, mount
# it, set the flag, unmount, and only then compress it into the form we
# hand out.
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
    -ov -format UDRW "$RW" >/dev/null 2>&1
rm -rf "$STAGING"

mkdir -p "$MOUNT"
hdiutil attach "$RW" -nobrowse -quiet -mountpoint "$MOUNT"
cp "$ROOT/app/App/Resources/LlamaScope.icns" "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -c icnC "$MOUNT/.VolumeIcon.icns"
xcrun SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT"

hdiutil convert "$RW" -format UDZO -o "$DMG" >/dev/null 2>&1
rm -f "$RW"
echo "  $DMG"

# Obraz też się podpisuje. Bez tego kwarantanna zostaje na nim samym
# i pierwsze kliknięcie wygląda na awarię.
#
# EN: the image gets signed too. Without that, the quarantine flag stays
# on the image itself and the first double click looks like a failure.
codesign --sign "Developer ID Application" --timestamp "$DMG"

# Ikona woluminu sprawdzona na gotowym obrazie, a nie na katalogu, z którego
# powstał. Flaga ginie po drodze cicho — tak właśnie zginęła za pierwszym
# razem — a obraz bez niej wygląda w Finderze dokładnie jak każdy inny.
#
# EN: the volume icon is checked on the finished image, not on the
# directory it was built from. The flag goes missing quietly along the
# way — that is exactly how it went missing the first time — and an image
# without it looks in Finder exactly like any other.
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -quiet -readonly -mountpoint "$MOUNT"
attrs="$(xcrun GetFileInfo -a "$MOUNT")"
icon_ok=yes
[ -s "$MOUNT/.VolumeIcon.icns" ] || icon_ok=no
case "$attrs" in *C*) ;; *) icon_ok=no ;; esac
hdiutil detach "$MOUNT" -quiet
rmdir "$MOUNT"
[ "$icon_ok" = "yes" ] || zle "$(msg brak_wolumenu "$attrs")"
msg ok_wolumen; echo

if [ "$NOTARIZE" = "no" ]; then
    krok "$(msg gotowe_bez)"
    msg tylko_tutaj;  echo
    msg tylko_tutaj2; echo
    exit 0
fi

# ---------------------------------------------------------------------
krok "$(msg krok_notaryzacja)"
# `notarytool submit --wait` kończy się **zerem także wtedy, gdy status
# to Invalid** — zero znaczy tu „rozmowa z Apple się udała”, a nie
# „pakiet przeszedł”. Bez tego sprawdzenia skrypt szedł dalej z pakietem
# odrzuconym i przewracał się dopiero na przyszywaniu, z komunikatem
# o CloudKicie, który nie mówi nic o przyczynie. Trzecia taka pułapka
# w tym pliku, wszystkie tej samej rodziny co `truncated = 0`.
#
# EN: `notarytool submit --wait` exits **zero even when the status is
# Invalid** — zero here means "the conversation with Apple worked", not
# "the package passed". Without this check the script used to carry on
# with a rejected package and fall over only at the stapling step, with
# an error about CloudKit that says nothing about the cause. The third
# trap of this kind in this file, all of them the same family as
# `truncated = 0`.
out="$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1)"
echo "$out"
id="$(echo "$out" | awk '/^ *id:/ {print $2; exit}')"
echo "$out" | grep -q "status: Accepted" || {
    printf '\n\033[31m%s\033[0m\n' "$(msg apple_odrzucilo)"
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" 2>&1 \
        | grep -E '"(message|path)"' | sort -u
    zle "$(msg notaryzacja_zla)"
}

# ---------------------------------------------------------------------
krok "$(msg krok_przyszycie)"
# Bez tego kroku pakiet wymaga internetu przy pierwszym uruchomieniu.
# Zaświadczenie przyszyte do obrazu działa też bez sieci.
#
# EN: without this step the package needs an internet connection on its
# first launch. A ticket stapled into the image works offline too.
xcrun stapler staple "$DMG"

# ---------------------------------------------------------------------
krok "$(msg krok_sprawdzenie)"
# Najważniejsze sprawdzenie w tym pliku i jedyne, które mówi o cudzym
# komputerze: montujemy obraz i pytamy Gatekeepera o pakiet w środku.
# Pakiet zbudowany lokalnie nie ma flagi kwarantanny, więc `spctl` na nim
# przechodzi **zanim** cokolwiek zostanie notaryzowane — i właśnie dlatego
# nie wolno się nim zadowolić.
#
# EN: the most important check in this file and the only one that speaks
# about somebody else's computer: we mount the image and ask Gatekeeper
# about the app inside it. A locally built bundle carries no quarantine
# flag, so `spctl` on it passes **before** anything has been notarized —
# which is precisely why that answer must not satisfy us.
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MOUNT"
verdict="$(spctl --assess --type execute --verbose=2 "$MOUNT/$APP_NAME.app" 2>&1 || true)"
hdiutil detach "$MOUNT" -quiet
rm -rf "$MOUNT"
echo "$verdict"
echo "$verdict" | grep -q "accepted" || zle "$(msg gatekeeper_nie)"
echo "$verdict" | grep -q "Notarized Developer ID" \
    || zle "$(msg bez_zaswiadczenia)"

krok "$(msg gotowe "$DMG")"
msg do_rozdania; echo
