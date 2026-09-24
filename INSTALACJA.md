# Instalacja LlamaScope 0.5 na macOS

## Najpierw uczciwie: dlaczego macOS będzie ostrzegał

**Ta wersja nie jest podpisana ani notaryzowana.** To nie jest błąd
systemu ani fałszywy alarm — to prawda o tym pliku. macOS nie ma jak
sprawdzić, kto go zbudował i czy nikt go po drodze nie podmienił,
więc mówi dokładnie to, co wie.

Obchodząc to ostrzeżenie, **bierzesz nas na słowo**. Warto wiedzieć, na
co konkretnie: LlamaScope czyta log serwera Ollamy, a po włączeniu
pośrednika przepuszcza przez siebie ruch do modelu — czyli widzi treść
Twoich promptów (co z nich zapisuje, opisuje [README](README.md),
sekcja *Prywatność*). To nie jest program, przy którym „a, jakoś to
będzie" jest rozsądną postawą.

Dlatego niżej są **dwie drogi, a nie jedna**. Pierwsza nie wymaga
zaufania do nas w ogóle i jest tą zalecaną na szczeblu 0.5.

Podpis Developer ID i notaryzacja dochodzą w wersji 0.9 — wtedy ten
dokument przestanie być potrzebny i zniknie.

---

## Droga A: zbuduj ze źródeł (zalecana)

Budujesz z kodu, który możesz przeczytać, więc nie musisz wierzyć
w nic, czego nie widzisz. Aplikacja zbudowana lokalnie **nie trafia do
kwarantanny** i po prostu się uruchamia — żadnych okienek po drodze.

Potrzebny Xcode (nie same narzędzia wiersza poleceń).

```sh
git clone https://github.com/MarcinSNowak/llamascope.git
cd llamascope/app
xcodebuild -scheme LlamaScope -configuration Release build
```

Gotowy pakiet leży w katalogu, który `xcodebuild` wypisze na końcu —
ścieżka kończy się na `Build/Products/Release/LlamaScope.app`.
Przeciągnij go do `/Applications` i uruchom.

Jeżeli chcesz sam sprawdzić obietnicę z README o pośredniku — że
aplikacja nie zawiera ani grama jego kodu — to jest moment:

```sh
nm LlamaScope.app/Contents/MacOS/LlamaScope | grep -c ProxyCore   # ma dać 0
nm LlamaScope.app/Contents/MacOS/LlamaScopeProxy | grep -c ProxyCore
```

---

## Droga B: gotowy pakiet `.app`

Jeżeli dostałeś gotowy pakiet (skopiowany, przesłany, pobrany), macOS
oznaczy go kwarantanną i **nie pozwoli go otworzyć podwójnym
kliknięciem**. Zobaczysz komunikat, że Apple nie może sprawdzić, czy
plik jest wolny od złośliwego oprogramowania.

**Kliknięcie prawym przyciskiem i „Otwórz" już nie działa** — Apple
usunęło tę furtkę w macOS 15. Jedyna droga prowadzi przez ustawienia:

1. Przenieś `LlamaScope.app` do `/Applications`.
2. Kliknij go dwukrotnie. Pojawi się ostrzeżenie — zamknij je.
3. Otwórz **Ustawienia systemowe → Prywatność i ochrona**.
4. Przewiń do sekcji *Ochrona*. Będzie tam zdanie o zablokowanym
   LlamaScope i przycisk **„Otwórz mimo to"**.
5. Kliknij go i potwierdź hasłem albo Touch ID.

Krok 2 jest konieczny: dopóki system nie zablokuje próby otwarcia,
w ustawieniach **nie ma czego odblokowywać** i przycisk się nie
pojawi.

### Wariant z wierszem poleceń

To samo, jedną komendą — zdejmuje kwarantannę z całego pakietu:

```sh
xattr -d -r com.apple.quarantine /Applications/LlamaScope.app
```

Nie jest ani lepszy, ani gorszy od klikania. Jest za to szczerszy:
widać w nim wprost, że wyłączasz sprawdzanie, zamiast po prostu
klikać „dalej".

---

## Skąd wiesz, że działa

LlamaScope **nie ma ikony w Docku** — to narzędzie paska menu i tak ma
być (`LSUIElement`). Po uruchomieniu szukaj ikony **u góry ekranu, po
prawej**, obok zegara i Wi-Fi.

To jest najczęstsze nieporozumienie przy pierwszym uruchomieniu:
niepodpisana aplikacja, która nic nie pokazuje w Docku, wygląda
dokładnie tak samo jak aplikacja zablokowana przez system. Jeśli ikona
jest w pasku u góry — wszystko się udało.

## Pośrednik, czyli drugi plik do odblokowania

W pakiecie jedzie **drugi program**: `Contents/MacOS/LlamaScopeProxy`.
Jest osobnym procesem właśnie po to, żeby „pośrednik wyłączony"
znaczyło, że tego procesu nie ma — sprawdzalnie, w Monitorze
aktywności, a nie na nasze słowo.

Kwarantanna obejmuje także jego. **Nie musisz robić z tym nic
osobno** — sprawdzone na macOS 27.0: aplikacja uruchamia go
bezpośrednio, nie przez Launch Services, więc drugie okienko się nie
pojawia i pośrednik startuje normalnie. Obie drogi wyżej załatwiają
sprawę w całości.

## Czego ta wersja nie ma

- **Podpisu i notaryzacji** — powód na górze tej strony.
- **Automatycznych aktualizacji.** Nowa wersja to nowe zbudowanie albo
  nowy plik.
- **Instalatora `.dmg`.** Dochodzi razem z podpisem w 0.9.

## Jak to odinstalować

Wyrzuć `LlamaScope.app` do kosza. Zostaną jeszcze dwa miejsca, w których
program coś u siebie zapisał — oba możesz skasować ręcznie:

```sh
rm -rf ~/Library/Logs/LlamaScope                 # log aplikacji, log i obserwacje pośrednika
rm -rf ~/Library/Application\ Support/LlamaScope # punkt odniesienia zużycia swapu
```

To wszystko. LlamaScope nie instaluje usług w tle, nie dopisuje się do
autostartu i nie zostawia niczego poza tymi dwoma katalogami.

---

## In short (English)

**LlamaScope 0.5 is unsigned and un-notarized.** macOS will warn you,
and the warning is telling the truth — there is no way for the system
to verify who built this. Bypassing it means taking our word for it,
and this program reads your Ollama server log and (optionally) proxies
your prompts, so that is not a small thing to hand over.

**Preferred route: build it yourself.** Locally built apps are never
quarantined and just run:

```sh
git clone https://github.com/MarcinSNowak/llamascope.git
cd llamascope/app && xcodebuild -scheme LlamaScope -configuration Release build
```

**If you got a prebuilt `.app`:** double-click it, dismiss the warning,
then go to **System Settings → Privacy & Security** and press **Open
Anyway**. Right-click → Open no longer works; Apple removed that in
macOS 15. The command-line equivalent is
`xattr -d -r com.apple.quarantine /Applications/LlamaScope.app`.

LlamaScope has **no Dock icon** by design — look for it in the menu bar
at the top right. Signing and notarization arrive in 0.9, and this
document goes away with them.
