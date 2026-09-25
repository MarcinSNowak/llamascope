# LlamaScope

**Lampka kontrolna lokalnego modelu.** Jeden ekran, który odpowiada na
pytanie, jakiego nie zadaje żadne inne narzędzie: *czy odpowiedź, którą
przed chwilą dostałem od modelu, jest w ogóle wiarygodna?*

```text
LlamaScope — Ollama na żywo                                   13:41:07

  qwen2.5-coder:14b            9,0 GB   100% GPU
  okno 8192   zwolni pamięć za 4:12

  GPU  ████████████████░░░░  84 %
       ▁▁▂▅▇███▇▅▃▂▁▁▁▂▄▆███

  swap 17,9 GB użyte, 1,1 GB wolne  ⚠ model nie mieści się obok reszty

  ostatnie: prompt 258 tok (611 tok/s)   odpowiedź 214 tok (31,4 tok/s)

  ⚠ 13:40:52  PROMPT ZOSTAŁ UCIĘTY
    wysłane 7260 tokenów, model przeczytał 258 — 97% przepadło
    podnieś num_ctx albo skróć prompt
```

Ta ostatnia sekcja jest powodem, dla którego program powstał. Ollama
**nie zgłasza ucięcia promptu w API** — odpowiedź wygląda normalnie,
tylko model nie widział większości tego, co mu wysłałeś. Informacja o tym
istnieje wyłącznie w logu serwera, w jednej linii `WARN`:

```text
level=WARN source=llama_server.go:317 msg="truncating input prompt"
limit=258 prompt=7260 keep=4 new=258
```

LlamaScope czyta tę linię i pokazuje ją po ludzku.

## Dwie postacie

W tym repozytorium są **dwa programy**, robiące to samo na dwa sposoby:

| | skrypt Pythona | aplikacja macOS |
|---|---|---|
| plik | `llamascope.py` | katalog [`app/`](app/) |
| gdzie mieszka | terminal albo [SwiftBar](https://swiftbar.app) | własna ikona w pasku menu |
| stan | używany codziennie od 2026-09-06 | **0.9, podpisana i notaryzowana** — [INSTALACJA.md](INSTALACJA.md) |
| pośrednik (niżej) | nie ma | jest, domyślnie wyłączony |

Skrypt nie jest etapem przejściowym do skasowania — jest wersją bez
instalacji, która działa wszędzie tam, gdzie jest Python. Aplikacja
dokłada sześć stanów, przycisk „Zwolnij teraz" i pośrednika.

## Czego LlamaScope nie zobaczy z samego logu

Uczciwa granica, zmierzona 2026-09-06 na Ollamie 0.32.14. Serwer radzi
sobie ze zbyt długim wejściem na **dwa różne sposoby**:

| | pojedyncza wiadomość za duża | cała rozmowa za długa |
|---|---|---|
| co robi serwer | ucina tokeny od początku | wyrzuca całe najstarsze wiadomości |
| co przeżywa | koniec wiadomości | instrukcja systemowa i najnowsze tury |
| linia `WARN` w logu | **jest** | **nie ma** |
| widać z samego logu | **tak** | **nie** |

Innymi słowy: **z loga widać ucięcie tylko wtedy, gdy sama najnowsza
wiadomość nie mieści się w oknie.** Jeśli rozmowa w kliencie czatu
rośnie i serwer po cichu wyrzuca stare tury, w logu nie ma o tym ani
słowa.

Gorzej: log temu **zaprzecza**. Przy żądaniu, z którego Ollama wycięła
83% rozmowy, `llama-server` melduje w tej samej linii `truncated = 0`.
Spokojne zero, które wygląda jak dobra wiadomość.

Sprawdzaliśmy, czy da się to obejść sprytem — czy rosnąca rozmowa,
której licznik tokenów przestaje rosnąć tuż pod sufitem okna, nie jest
przypadkiem wykrywalnym śladem. **Zmierzone 2026-09-24 na trzech
przebiegach: nie jest.** Taki płaskowyż pojawia się też wtedy, gdy nie
ginie nic, a przy nierównych turach nie pojawia się mimo strat. Co
gorsza, po rozpoczęciu przycinania Ollama raportuje prompt **już
przycięty**, więc liczba ucieka od sufitu dokładnie wtedy, gdy zaczyna
się strata. Log po przycięciu opisuje inną rozmowę niż ta, którą wysłał
klient, i robi to bez żadnego znacznika.

Dlatego ten przypadek ma osobne narzędzie.

## Pośrednik

Wykrycie znikających tur wymaga stanięcia **między klientem a Ollamą** —
bo tylko tam widać żądanie, zanim serwer je przytnie. Aplikacja ma to od
wersji 0.5 i jest to **świadoma zamiana jednej rzeczy na drugą**:
dostajesz liczbę, której nie da się odczytać z logu, a oddajesz to, że
program przestaje być ślepy na treść.

Dlatego pośrednik jest zbudowany tak, żeby dało się to sprawdzić, a nie
tylko nam uwierzyć:

- **Jest osobnym procesem, nie funkcją w aplikacji.** „Wyłączony" znaczy,
  że tego procesu nie ma — widać to w Monitorze aktywności i w `lsof`.
- **Aplikacja nie zawiera ani grama jego kodu.** Sprawdzalne z zewnątrz,
  bez czytania źródeł: `nm LlamaScope.app/Contents/MacOS/LlamaScope | grep -c ProxyCore`
  daje `0`.
- **Domyślnie jest wyłączony.** Włącza się przyciskiem, a panel mówi
  wtedy wprost, że widzi treści promptów.
- **Z promptów zapisuje wyłącznie liczby i etykiety, nigdy treść** —
  do pliku `obserwacje.jsonl` na tym samym dysku.
- Dokłada do żądania dokładnie jedną rzecz: `stream_options.include_usage`
  dla strumieniowych żądań `/v1/`, żeby dostać prawdziwą liczbę tokenów
  do kalibracji. Klienta, który już o to poprosił, zostawia w spokoju.

Uruchamia się go z panelu albo osobno z wiersza poleceń:

```sh
LLAMASCOPE_PORT=11435 LlamaScopeProxy      # domyślnie 11435 → 11434
```

a w kliencie ustawia `OLLAMA_HOST=http://127.0.0.1:11435` (albo
`base_url` kończący się na `/v1`). Bez pośrednika aplikacja działa
normalnie — po prostu nie widzi tego jednego przypadku.

---

## Wymagania

- **macOS na Apple Silicon** (odczyt GPU idzie przez `ioreg`; na Intelu
  skrypt działa, tylko bez wykresu GPU),
- do skryptu: **Python 3** — ten z systemu wystarczy, żadnych bibliotek,
- do aplikacji: macOS 14 lub nowszy, **wyłącznie Apple Silicon** —
  pakiet jest zbudowany tylko dla `arm64` i na Intelu system odmówi
  otwarcia. To nie jest niedoróbka: aplikacja uruchomiona na Intelu
  pokazałaby panel, w którym odczyty GPU nic nie znaczą, czyli zero
  wyglądające na pomiar. Skrypt Pythona działa tam dalej,
- do budowania ze źródeł: **Xcode**,
- działająca **Ollama**.

Bez `sudo`, bez pliku konfiguracyjnego.

## Uruchomienie skryptu

```bash
git clone https://github.com/MarcinSNowak/llamascope.git
cd llamascope
python3 llamascope.py
```

Wyjście: `Ctrl-C`.

Jeśli serwer stoi pod innym adresem, ustaw `OLLAMA_HOST`:

```bash
OLLAMA_HOST=http://192.168.1.10:11434 python3 llamascope.py
```

## Zbudowanie aplikacji

```bash
cd llamascope/app
xcodebuild -scheme LlamaScope -configuration Release build
```

Gotowy pakiet leży w `Build/Products/Release/LlamaScope.app` — pełną
ścieżkę `xcodebuild` wypisze na końcu.

Gotowy `.dmg` — podpisany i notaryzowany — leży w
[wydaniach](https://github.com/MarcinSNowak/llamascope/releases);
budowanie ze źródeł jest drugą drogą, nie jedyną
([INSTALACJA.md](INSTALACJA.md)). Aplikacja **nie ma ikony w Docku** —
szukaj jej w pasku menu u góry po prawej. Panel mówi po polsku albo po
angielsku, zależnie od języków ustawionych w systemie.

Ikonę pakietu — tę widoczną w Finderze i w Launchpadzie — rysuje
[`ikona.swift`](ikona.swift) (`swift ikona.swift`); gotowy `.icns` leży
w repozytorium, więc do samej budowy skrypt nie jest potrzebny. To ten
sam wykres co w pasku menu, z jedną próbką celowo pustą: brak odczytu
nie jest zerem, także na obrazku.

W panelu jest nagłówek stanu, zdanie po ludzku, lista załadowanych
modeli, obciążenie GPU, zajętość okna kontekstu, tempo ostatniej
odpowiedzi, przyciski „Zwolnij teraz" i „Załaduj ponownie", włącznik
pośrednika — oraz **napisana wprost granica wykrywania** z sekcji wyżej,
na stałe, a nie w dokumentacji.

## W pasku menu (SwiftBar)

Ten sam plik Pythona potrafi być wtyczką [SwiftBara](https://swiftbar.app) —
dowiązanie w katalogu wtyczek, odświeżanie co 5 sekund. Nazwa pliku
`llamascope.5s.py` to nie ozdoba: SwiftBar czyta z niej częstotliwość.

```bash
brew install --cask swiftbar

KATALOG=~/Library/Application\ Support/SwiftBar/Plugins
mkdir -p "$KATALOG"
defaults write com.ameba.SwiftBar PluginDirectory -string "$KATALOG"

chmod +x llamascope.py
ln -s "$PWD/llamascope.py" "$KATALOG/llamascope.5s.py"

open -a SwiftBar
```

Katalog wtyczek trzeba utworzyć samemu — SwiftBar przed pierwszym
uruchomieniem go nie ma i sam o niego pyta. Linia z `defaults` odpowiada
na to pytanie z góry, więc nie trzeba niczego klikać. Trybu paskowego
nie włącza się przełącznikiem: skrypt rozpoznaje go po zmiennej
`SWIFTBAR`, którą SwiftBar ustawia swoim wtyczkom.

W pasku widać wykres obciążenia GPU, a gdy dzieje się coś złego —
konkretne ostrzeżenie zamiast wykresu: `⚠ prompt ucięty`,
`⚠ model poza GPU`, `⚠ mało pamięci`, `⚠ Ollama nie odpowiada`.
Kliknięcie rozwija cały ekran z podglądu w terminalu.

Jeśli używasz aplikacji natywnej, SwiftBar nie jest do niczego
potrzebny — to dwie drogi do tego samego paska.

## Co dokładnie czyta

| źródło | po co |
|---|---|
| `GET /api/ps` | co jest załadowane, ile zajmuje, ile siedzi w GPU |
| `ioreg -c AGXAccelerator` | obciążenie GPU, bez `sudo` i bez zależności |
| `sysctl vm.swapusage` | czy **model** dołożył maszynie swapu |
| log serwera Ollamy | ucięcia kontekstu i prędkość generowania |
| treść żądań | **tylko z włączonym pośrednikiem** — znikające tury rozmowy |

Ostrzeżenie o pamięci mówi o **pogorszeniu, które spowodował model**, a nie
o stanie zastanym. Maszyna, która od rana siedzi na swapie, nie jest
wiadomością — próg bezwzględny trzymał tu ostrzeżenie zapalone na okrągło
i zamieniał je w tapetę. Punktem odniesienia jest najniższy stan
zapamiętany wtedy, gdy Ollama nic nie trzymała; ostrzeżenie zapala się,
gdy przy załadowanym modelu swapu przybyło o ponad gigabajt. Liczy się
swap **użyty**, bo wolne miejsce niczego nie mówi: macOS sam powiększa
plik wymiany i przy wejściu modelu 14B do pamięci wolne spadło z 1,4
tylko do 1,1 GB, a użyte urosło z 13,6 do 17,9 GB.

Log jest szukany kolejno w `/opt/homebrew/var/log/ollama.log`,
`/usr/local/var/log/ollama.log` i `~/.ollama/logs/server.log`; aplikacja
zagląda dodatkowo do `~/Library/Logs/Ollama/server.log`, gdzie trzyma go
Ollama instalowana jako program z ikoną. Bez logu reszta działa, ale nie
widać ucięć — czyli tego, co najważniejsze.

## Prywatność

**Nic nie opuszcza Twojej maszyny.** Zero telemetrii, zero konta, zero
połączeń poza `127.0.0.1`. To dotyczy obu programów i wszystkich trybów.

Reszta zależy od tego, czy pośrednik jest włączony, i warto to rozdzielić:

**Bez pośrednika — czyli skrypt i aplikacja w trybie domyślnym —
program nie widzi treści Twoich promptów ani odpowiedzi.** Nie dlatego,
że obiecujemy ich nie czytać: dlatego, że w tych źródłach ich po prostu
nie ma. Log Ollamy zawiera liczby i zdarzenia, nie tekst rozmowy.
W aplikacji jest to mocniejsze niż obietnica — kod, który umiałby
zobaczyć prompt, **nie jest w nią wlinkowany** i sprawdza to jedna
komenda `nm` z sekcji o pośredniku.

**Z włączonym pośrednikiem program widzi treść promptów** — inaczej nie
policzyłby, co przepadło. Zapisuje z nich wyłącznie liczby i etykiety,
nigdy treść, i wyłącznie na tym dysku. Włącza się to samemu, świadomie,
a panel mówi o tym wprost w chwili włączenia.

Kod jest otwarty po to, żeby dało się to sprawdzić samemu, a nie brać na
słowo.

## Stan projektu

Wczesny i szczery. Skrypt jest działającym narzędziem, którego używamy
codziennie. Aplikacja natywna jest na szczeblu **0.9**: ma sześć stanów,
„Zwolnij teraz", własny log, pośrednika, wprost napisaną granicę
wykrywania, interfejs po polsku i po angielsku — oraz podpis Developer ID
i notaryzację, więc instaluje się ją bez obchodzenia czegokolwiek.

Czego wciąż nie ma: automatycznych aktualizacji i caska w Homebrew.
Dalej: 1.0 to strona z opisem i Homebrew. Uwagi i zgłoszenia: przez
*Issues*.

## Skąd to się wzięło

LlamaScope powstał jako materiał pomocniczy do serii **ABC AI** —
o uruchamianiu modeli lokalnie i o tym, kiedy przestają wystarczać:
[www.qshmobile.com/abc-ai/](https://www.qshmobile.com/abc-ai/),
wydawanej przez [QSHMOBILE](https://www.qshmobile.com).

Autor: **Marcin S. Nowak**.

---

## In short (English)

LlamaScope is a live, one-screen view of what your local Ollama is
actually doing: which model is loaded, how much of it sits in GPU memory,
GPU utilisation, swap pressure — and, crucially, **whether your prompt
was silently truncated**. Ollama does not report truncation through its
API; the only trace is a `WARN` line in the server log, which LlamaScope
watches for you.

Two programs, same job: `llamascope.py` (Python 3 from the system, no
dependencies, no `sudo` — just `python3 llamascope.py`; it also runs as a
[SwiftBar](https://swiftbar.app) plugin, exact commands in the Polish
section above), and a native menu-bar app in [`app/`](app/), built with
`xcodebuild -scheme LlamaScope -configuration Release build`. **The app
is version 0.9, signed with a Developer ID and notarized** — a ready
`.dmg` is in
[Releases](https://github.com/MarcinSNowak/llamascope/releases), and
[INSTALACJA.md](INSTALACJA.md) ends with an English summary. Its
interface is in Polish or English, following your system languages.

**Known limit** (measured on Ollama 0.32.14): the `WARN` line only appears
when a *single message* exceeds the context window. When a *conversation*
grows too long, Ollama silently drops the oldest messages — keeping the
system prompt and the newest turns — and logs nothing at all. Worse, it
logs `truncated = 0` for a request it just cut by 83%. We measured
(2026-09-24) whether a token-count plateau just below the window ceiling
could betray this: **it cannot.** No log-based tool can catch that case.

Catching it requires sitting **between your client and Ollama**, so the
app ships an opt-in proxy as a *separate process* — "off" means the
process does not exist, and the app binary contains none of its code
(`nm LlamaScope.app/Contents/MacOS/LlamaScope | grep -c ProxyCore` → 0).
Without it, LlamaScope never sees your prompts, because that data is not
present in any of the sources it reads. With it, it does see them, and
records only numbers and labels — never text, and only on your disk.
Nothing ever leaves your machine either way.

---

*LlamaScope nie jest powiązany z Ollama Inc. ani z Meta Platforms, Inc.,
nie jest przez nie wspierany ani sponsorowany. „Ollama" i „Llama" są
znakami towarowymi odpowiednich właścicieli. — LlamaScope is not
affiliated with, endorsed or sponsored by Ollama Inc. or Meta Platforms,
Inc.; "Ollama" and "Llama" are trademarks of their respective owners.*

Licencja: [MIT](LICENSE).
