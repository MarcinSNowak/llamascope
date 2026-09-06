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

## Czego LlamaScope nie zobaczy

Uczciwa granica, zmierzona 2026-09-06 na Ollamie 0.32.14. Serwer radzi
sobie ze zbyt długim wejściem na **dwa różne sposoby**:

| | pojedyncza wiadomość za duża | cała rozmowa za długa |
|---|---|---|
| co robi serwer | ucina tokeny od początku | wyrzuca całe najstarsze wiadomości |
| co przeżywa | koniec wiadomości | instrukcja systemowa i najnowsze tury |
| linia `WARN` w logu | **jest** | **nie ma** |
| LlamaScope ostrzeże | **tak** | **nie** |

Innymi słowy: **LlamaScope widzi ucięcie tylko wtedy, gdy sama najnowsza
wiadomość nie mieści się w oknie.** Jeśli rozmowa w kliencie czatu rośnie
i serwer po cichu wyrzuca stare tury, w logu nie ma o tym ani słowa —
żadne narzędzie czytające log tego nie wykryje, łącznie z tym.

Wykrycie tego drugiego przypadku wymaga stanięcia między klientem
a Ollamą i czytania treści żądań. To osobne narzędzie i osobna decyzja
o prywatności — świadomie nie ma go tutaj.

---

## Wymagania

- **macOS na Apple Silicon** (odczyt GPU idzie przez `ioreg`; na Intelu
  program działa, tylko bez wykresu GPU),
- **Python 3** — ten z systemu wystarczy, żadnych bibliotek,
- działająca **Ollama**.

Bez `sudo`, bez instalacji, bez pliku konfiguracyjnego.

## Uruchomienie

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

## W pasku menu (SwiftBar)

Ten sam plik potrafi być wtyczką [SwiftBara](https://swiftbar.app) —
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

## Co dokładnie czyta

| źródło | po co |
|---|---|
| `GET /api/ps` | co jest załadowane, ile zajmuje, ile siedzi w GPU |
| `ioreg -c AGXAccelerator` | obciążenie GPU, bez `sudo` i bez zależności |
| `sysctl vm.swapusage` | czy **model** dołożył maszynie swapu |
| log serwera Ollamy | ucięcia kontekstu i prędkość generowania |

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
`/usr/local/var/log/ollama.log` i `~/.ollama/logs/server.log`. Bez niego
reszta działa, ale nie widać ucięć — czyli tego, co najważniejsze.

## Prywatność

**Program nie widzi treści Twoich promptów ani odpowiedzi.** Nie dlatego,
że obiecujemy ich nie czytać — dlatego, że w tych źródłach ich po prostu
nie ma. Log Ollamy zawiera liczby i zdarzenia, nie tekst rozmowy.
Nic nie jest nigdzie wysyłane; jedyne połączenie sieciowe idzie do
`127.0.0.1:11434`. Kod ma jakieś trzysta linii i po to jest tutaj
otwarty, żeby dało się to sprawdzić samemu, a nie brać na słowo.

## Stan projektu

Wczesny i szczery: to działający skrypt, którego używamy codziennie, a nie
gotowy program. Aplikacja natywna w pasku menu — z sześcioma stanami,
przyciskiem „Zwolnij pamięć", podpisem i notaryzacją — jest w planach
i pojawi się tutaj w wydaniach. Uwagi i zgłoszenia: przez *Issues*.

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

macOS on Apple Silicon, Python 3 from the system, no dependencies, no
`sudo`, no configuration: `python3 llamascope.py`. For the menu bar,
create SwiftBar's plugin folder — it does not exist before SwiftBar's
first launch — and symlink the same file into it as `llamascope.5s.py`;
the Polish section above has the exact commands. It never sees your
prompts or responses — that data is not present in any of the sources
it reads.

**Known limit** (measured on Ollama 0.32.14): the `WARN` line only appears
when a *single message* exceeds the context window. When a *conversation*
grows too long, Ollama silently drops the oldest messages — keeping the
system prompt and the newest turns — and logs nothing at all. No log-based
tool can catch that case, this one included.

---

*LlamaScope nie jest powiązany z Ollama Inc. ani z Meta Platforms, Inc.,
nie jest przez nie wspierany ani sponsorowany. „Ollama" i „Llama" są
znakami towarowymi odpowiednich właścicieli. — LlamaScope is not
affiliated with, endorsed or sponsored by Ollama Inc. or Meta Platforms,
Inc.; "Ollama" and "Llama" are trademarks of their respective owners.*

Licencja: [MIT](LICENSE).
