# Instalacja LlamaScope 0.9.1 na macOS

Ta wersja jest **podpisana Developer ID i notaryzowana**. Pobrany obraz
otwiera się podwójnym kliknięciem, bez ostrzeżeń i bez obchodzenia
czegokolwiek.

Poprzednia wersja tego dokumentu opisywała, jak przejść obok ostrzeżenia
systemu. Tamte instrukcje są nieaktualne i zostały usunięte — a nie
zostawione „na wszelki wypadek", bo instrukcja wyłączania sprawdzania
zabezpieczeń żyje potem własnym życiem.

Zaufanie, o które ta strona prosiła wcześniej, zmieniło się tylko
częściowo. Apple potwierdza teraz, **kto** zbudował ten plik i że nikt
go po drodze nie podmienił. Nie potwierdza, **co** ten plik robi —
a LlamaScope czyta log serwera Ollamy, a po włączeniu pośrednika widzi
treść Twoich promptów (co z nich zapisuje, opisuje
[README](README.md), sekcja *Prywatność*). Droga A niżej nadal jest
jedyną, która nie wymaga wierzenia nam na słowo.

---

## Droga A: zbuduj ze źródeł

Budujesz z kodu, który możesz przeczytać. Potrzebny Xcode (nie same
narzędzia wiersza poleceń).

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

## Droga B: gotowy `.dmg`

Pobierz `LlamaScope-0.9.1.dmg` z
[wydań](https://github.com/MarcinSNowak/llamascope/releases), otwórz
i przeciągnij aplikację do `/Applications`. To wszystko.

**Tylko Apple Silicon.** Na Macu z Intelem system odmówi otwarcia
i będzie miał rację: aplikacja pokazałaby tam panel, w którym odczyty
GPU nic nie znaczą — a to jest dokładnie ten rodzaj spokojnego zera,
który LlamaScope ma łapać, a nie produkować. Skrypt `llamascope.py`
działa na Intelu dalej, bez wykresu GPU.

Jeżeli chcesz zobaczyć, co dokładnie system o tym pliku wie:

```sh
spctl --assess --type execute --verbose=2 /Applications/LlamaScope.app
```

Odpowiedź ma zawierać `Notarized Developer ID`. Samo `accepted` to za
mało — pakiet zbudowany lokalnie dostaje `accepted` **zanim** cokolwiek
zostanie notaryzowane, bo nie ma flagi kwarantanny.

---

## Skąd wiesz, że działa

LlamaScope **nie ma ikony w Docku** — to narzędzie paska menu i tak ma
być (`LSUIElement`). Po uruchomieniu szukaj ikony **u góry ekranu, po
prawej**, obok zegara i Wi-Fi.

To jest najczęstsze nieporozumienie przy pierwszym uruchomieniu:
aplikacja, która nic nie pokazuje w Docku, wygląda dokładnie tak samo
jak aplikacja, która się nie uruchomiła. Jeśli ikona jest w pasku
u góry — wszystko się udało.

## Język

Panel mówi po polsku, jeżeli masz polski wśród języków systemu
(*Ustawienia systemowe → Ogólne → Język i region*). W przeciwnym razie
po angielsku. Przełącznika w samej aplikacji nie ma — narzędzie
w pasku menu ma mieć jedno ustawienie mniej.

Log aplikacji zostaje po polsku niezależnie od tego wyboru. To jest
materiał do zgłoszenia błędu i czyta go ten, kto tę aplikację pisze.

## Pośrednik, czyli drugi program w pakiecie

W pakiecie jedzie **drugi plik wykonywalny**:
`Contents/MacOS/LlamaScopeProxy`. Jest osobnym procesem właśnie po to,
żeby „pośrednik wyłączony" znaczyło, że tego procesu nie ma —
sprawdzalnie, w Monitorze aktywności, a nie na nasze słowo.

Jest podpisany tą samą tożsamością i objęty tą samą notaryzacją co
aplikacja. Nie musisz robić z nim nic osobno.

## Czego ta wersja nie ma

- **Automatycznych aktualizacji.** Nowa wersja to nowe zbudowanie albo
  nowy plik.
- **Pakietu w Homebrew.** Dochodzi w 1.0.

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

The same document in English, in full: [INSTALL.md](INSTALL.md).

It is a translation, not a summary — deliberately, because a summary
next to a full document is the copy that goes out of date first, and
the reader of the shorter one has no way of telling.
