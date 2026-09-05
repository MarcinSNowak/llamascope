#!/usr/bin/env python3
"""LlamaScope — podgląd działania Ollamy na żywo. Jeden ekran, co sekundę.

Bez zależności — sama biblioteka standardowa. Bez sudo. Bez konfiguracji.

    python3 llamascope.py            pełny ekran w terminalu
    python3 llamascope.py --pasek    jedno przejście, dla SwiftBar/xbar

Czyta cztery źródła:
  /api/ps                      co jest załadowane, ile zajmuje, czy w GPU
  ioreg -c AGXAccelerator      obciążenie GPU (Apple Silicon, bez sudo)
  sysctl vm.swapusage          czy maszyna zaczyna się dławić
  log serwera Ollamy           ucięcia kontekstu i prędkość generowania
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from collections import deque

OLLAMA = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
ODSWIEZANIE = 1.0
HISTORIA = 40

SCIEZKI_LOGU = [
    "/opt/homebrew/var/log/ollama.log",
    "/usr/local/var/log/ollama.log",
    os.path.expanduser("~/.ollama/logs/server.log"),
]

BLOKI = "▁▂▃▄▅▆▇█"          # 0% to najniższy blok, nie spacja — płaska
                             # linia ma być widoczna, inaczej wykres znika
CSI = "\x1b["
RESET = f"{CSI}0m"


def barwa(kod):
    return f"{CSI}{kod}m"


SZARY, ZOLTY, CZERWONY, ZIELONY, JASNY = (
    barwa("90"), barwa("33"), barwa("31"), barwa("32"), barwa("1")
)


# ── źródła ────────────────────────────────────────────────────────────────

def api(sciezka):
    try:
        with urllib.request.urlopen(f"{OLLAMA}{sciezka}", timeout=2) as r:
            return json.loads(r.read())
    except (urllib.error.URLError, OSError, json.JSONDecodeError, TimeoutError):
        return None


def gpu_procent():
    """Obciążenie GPU bez sudo. None na maszynach bez AGXAccelerator."""
    try:
        out = subprocess.run(
            ["ioreg", "-r", "-d", "1", "-w", "0", "-c", "AGXAccelerator"],
            capture_output=True, text=True, timeout=3,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    m = re.search(r'"Device Utilization %"=(\d+)', out)
    return int(m.group(1)) if m else None


def swap_gb():
    try:
        out = subprocess.run(
            ["sysctl", "-n", "vm.swapusage"], capture_output=True, text=True, timeout=3
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return None, None
    uzyte = re.search(r"used\s*=\s*([\d.]+)M", out)
    wolne = re.search(r"free\s*=\s*([\d.]+)M", out)
    return (
        float(uzyte.group(1)) / 1024 if uzyte else None,
        float(wolne.group(1)) / 1024 if wolne else None,
    )


def znacznik(iso):
    """Czas z logu → (napis HH:MM:SS, ile sekund temu)."""
    from datetime import datetime
    try:
        chwila = datetime.fromisoformat(iso)
    except (ValueError, TypeError):
        return "?", 0.0
    wiek = (datetime.now(chwila.tzinfo) - chwila).total_seconds()
    return chwila.strftime("%H:%M:%S"), wiek


class Log:
    """Doczytuje ogon logu Ollamy. Zapamiętuje ostatnie ucięcie i prędkość."""

    WZ_UCIECIE = re.compile(
        r'time=(\S+).*?msg="truncating input prompt" '
        r'limit=(\d+) prompt=(\d+) keep=(\d+) new=(\d+)'
    )
    WZ_GENEROWANIE = re.compile(
        r"\|\s+eval time =\s*[\d.]+ ms /\s*(\d+) tokens \(.*?([\d.]+) tokens per second"
    )
    WZ_PROMPT = re.compile(
        r"prompt eval time =\s*[\d.]+ ms /\s*(\d+) tokens \(.*?([\d.]+) tokens per second"
    )

    def __init__(self):
        self.sciezka = next((s for s in SCIEZKI_LOGU if os.path.exists(s)), None)
        self.pozycja = os.path.getsize(self.sciezka) if self.sciezka else 0
        self.uciecie = None       # (czas, wyslane, przeczytane)
        self.generowanie = None   # (tokeny, tok/s)
        self.prompt = None        # (tokeny, tok/s)

    def odczytaj(self):
        if not self.sciezka:
            return
        try:
            rozmiar = os.path.getsize(self.sciezka)
            if rozmiar < self.pozycja:      # rotacja logu
                self.pozycja = 0
            with open(self.sciezka, "r", errors="replace") as f:
                f.seek(self.pozycja)
                nowe = f.read()
                self.pozycja = f.tell()
        except OSError:
            return

        for linia in nowe.splitlines():
            if m := self.WZ_UCIECIE.search(linia):
                # UWAGA: czytamy wyłącznie ten WARN. Linia "slot release ...
                # truncated = N" dotyczy przesunięcia kontekstu przy
                # generowaniu, nie ucięcia wejścia — patrz log-ollamy.md.
                # Czas bierzemy z logu, nie z zegara — inaczej ucięcie
                # sprzed godzin udaje świeży alarm.
                self.uciecie = (m.group(1), int(m.group(3)), int(m.group(5)))
            elif m := self.WZ_PROMPT.search(linia):
                self.prompt = (int(m.group(1)), float(m.group(2)))
            elif m := self.WZ_GENEROWANIE.search(linia):
                self.generowanie = (int(m.group(1)), float(m.group(2)))


# ── rysowanie ─────────────────────────────────────────────────────────────

def lb(x, miejsca=1):
    """Liczba po polsku — z przecinkiem."""
    return f"{x:.{miejsca}f}".replace(".", ",")


def sparkline(wartosci):
    if not wartosci:
        return ""
    return "".join(BLOKI[min(7, max(0, round(w / 100 * 7)))] for w in wartosci)


def pasek(procent, szerokosc=20):
    pelne = round(procent / 100 * szerokosc)
    return "█" * pelne + "░" * (szerokosc - pelne)


def czas_do(iso):
    try:
        from datetime import datetime
        cel = datetime.fromisoformat(iso)
        sekundy = (cel - datetime.now(cel.tzinfo)).total_seconds()
    except (ValueError, TypeError):
        return None
    if sekundy < 0:
        return None
    return f"{int(sekundy // 60)}:{int(sekundy % 60):02d}"


def ekran(ps, gpu, historia, swap_u, swap_w, log):
    w = shutil.get_terminal_size((80, 24)).columns
    L = []
    L.append(f"{JASNY}LlamaScope — Ollama na żywo{RESET}"
             f"{SZARY}{time.strftime('%H:%M:%S').rjust(max(1, w - 27))}{RESET}")
    L.append("")

    if ps is None:
        L.append(f"  {CZERWONY}Serwer nie odpowiada{RESET} {SZARY}({OLLAMA}){RESET}")
        L.append(f"  {SZARY}Uruchom: ollama serve{RESET}")
        return L

    modele = ps.get("models") or []
    if not modele:
        L.append(f"  {SZARY}Żaden model nie jest załadowany.{RESET}")
    for m in modele:
        rozmiar = m.get("size", 0) / 1e9
        vram = m.get("size_vram", 0) / 1e9
        if vram >= rozmiar * 0.99:
            gdzie = f"{ZIELONY}100% GPU{RESET}"
        else:
            poza = rozmiar - vram
            gdzie = f"{ZOLTY}{lb(poza)} GB poza GPU — będzie wolno{RESET}"
        L.append(f"  {JASNY}{m.get('name', '?'):<28}{RESET} {lb(rozmiar):>5} GB   {gdzie}")
        okno = m.get("context_length")
        zostalo = czas_do(m.get("expires_at", ""))
        drobne = []
        if okno:
            drobne.append(f"okno {okno}")
        if zostalo:
            drobne.append(f"zwolni pamięć za {zostalo}")
        if drobne:
            L.append(f"  {SZARY}{'   '.join(drobne)}{RESET}")

    L.append("")
    if gpu is None:
        L.append(f"  {SZARY}GPU  — brak odczytu (nie Apple Silicon?){RESET}")
    else:
        kolor = ZIELONY if gpu > 5 else SZARY
        L.append(f"  GPU  {kolor}{pasek(gpu)}{RESET} {gpu:3d} %")
        L.append(f"       {SZARY}{sparkline(historia)}{RESET}")

    if swap_u is not None:
        ostrzez = swap_w is not None and swap_w < 2.0
        kolor = ZOLTY if ostrzez else SZARY
        uwaga = "  ⚠ maszyna dławi się pamięcią" if ostrzez else ""
        L.append(f"  swap {kolor}{lb(swap_u)} GB użyte, {lb(swap_w)} GB wolne{uwaga}{RESET}")

    L.append("")
    if log.prompt or log.generowanie:
        czesci = []
        if log.prompt:
            czesci.append(f"prompt {log.prompt[0]} tok ({lb(log.prompt[1], 0)} tok/s)")
        if log.generowanie:
            czesci.append(
                f"odpowiedź {log.generowanie[0]} tok ({lb(log.generowanie[1])} tok/s)"
            )
        L.append(f"  {SZARY}ostatnie:{RESET} {'   '.join(czesci)}")

    if log.uciecie:
        iso, wyslane, przeczytane = log.uciecie
        kiedy, wiek = znacznik(iso)
        stracone = 100 - przeczytane * 100 // max(1, wyslane)
        swieze = wiek < 600                      # starsze niż 10 min to już historia
        kolor = CZERWONY if swieze else SZARY
        naglowek = "PROMPT ZOSTAŁ UCIĘTY" if swieze else "ostatnie ucięcie"
        L.append("")
        L.append(f"  {kolor}⚠ {kiedy}  {naglowek}{RESET}")
        L.append(f"    {kolor}wysłane {wyslane} tokenów, model przeczytał "
                 f"{przeczytane} — {stracone}% przepadło{RESET}")
        if swieze:
            L.append(f"    {SZARY}podnieś num_ctx albo skróć prompt{RESET}")

    if not log.sciezka:
        L.append("")
        L.append(f"  {SZARY}Nie znalazłem logu serwera — bez niego nie widać"
                 f" ucięć ani prędkości.{RESET}")
    return L


STAN = "/tmp/llamascope-gpu.txt"


def pasek_menu():
    """Tryb SwiftBar/xbar: jedno przejście, wynik na stdout.

    Instalacja to jedno dowiązanie w katalogu wtyczek SwiftBara pod
    nazwą llamascope.5s.py — tryb włącza się sam, po zmiennej SWIFTBAR
    (patrz README). Bez Swifta, bez podpisu, bez notaryzacji — ikona
    w pasku menu za darmo.
    """
    try:                                  # historia GPU między wywołaniami
        proby = [int(x) for x in open(STAN).read().split()][-(HISTORIA - 1):]
    except (OSError, ValueError):
        proby = []
    gpu = gpu_procent()
    if gpu is not None:
        proby.append(gpu)
        try:
            open(STAN, "w").write(" ".join(map(str, proby)))
        except OSError:
            pass

    log = Log()
    log.pozycja = max(0, log.pozycja - 200_000)   # ostatni kawałek logu
    log.odczytaj()
    ps = api("/api/ps")
    swap_u, swap_w = swap_gb()

    # ── tytuł: jedna rzecz, najważniejsza z tego, co się dzieje ──
    alarm = None
    if ps is None:
        alarm = "Ollama nie odpowiada"
    elif log.uciecie and znacznik(log.uciecie[0])[1] < 600:
        alarm = "prompt ucięty"
    elif swap_w is not None and swap_w < 2.0:
        alarm = "mało pamięci"
    elif ps.get("models"):
        m = ps["models"][0]
        if m.get("size_vram", 0) < m.get("size", 0) * 0.99:
            alarm = "model poza GPU"

    print(f"⚠ {alarm}" if alarm else (sparkline(proby) or "○"))
    print("---")

    for linia in ekran(ps, gpu, proby, swap_u, swap_w, log)[2:]:
        czysta = re.sub(r"\x1b\[[0-9;]*m", "", linia).rstrip()
        if czysta.strip():
            print(czysta)
    print("---")
    print("Odśwież | refresh=true")


def main():
    # SwiftBar i xbar ustawiają te zmienne — wtedy nie ma terminala,
    # który mógłby przyjąć --pasek, więc tryb wykrywamy sami.
    w_pasku = "SWIFTBAR" in os.environ or "XBARDarkMode" in os.environ
    if "--pasek" in sys.argv or w_pasku:
        pasek_menu()
        return
    log = Log()
    historia = deque(maxlen=HISTORIA)
    print(f"{CSI}?25l", end="")           # schowaj kursor
    try:
        while True:
            gpu = gpu_procent()
            if gpu is not None:
                historia.append(gpu)
            log.odczytaj()
            swap_u, swap_w = swap_gb()
            linie = ekran(api("/api/ps"), gpu, list(historia), swap_u, swap_w, log)
            sys.stdout.write(f"{CSI}H{CSI}J" + "\n".join(linie) + "\n")
            sys.stdout.flush()
            time.sleep(ODSWIEZANIE)
    except KeyboardInterrupt:
        pass
    finally:
        print(f"{CSI}?25h", end="")       # pokaż kursor


if __name__ == "__main__":
    main()
