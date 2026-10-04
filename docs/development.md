# Entwicklung und Prüfung

Tests des tatsächlich assemblierten 6502-Codes:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
make test
make budget # kompakten Bahnexport und 18-Bahnen-Hochrechnung prüfen
make smoke # Zeitbudget-Prüfung meldet aktuell den bekannten Eckentreffer-Überlauf
```

`make test` verwendet py65 für Loader, Bitmap-Adressierung, Geometrie,
Hintergrundrestaurierung, Eingabe, Festkommaarithmetik, Bewegung und Kollisionen.
Zusätzlich werden der Host-Bahnexport und der Rücklese-Decoder geprüft. `make smoke` startet VICE mit echten
ROMs, PAL und ausdrücklich 16 KB, prüft die TED-Konfiguration und misst
128 Richtungen und acht Bewegungsszenarien. VICE steuert dabei logische Eingabeereignisse nach dem
Tastaturscan ein; das ersetzt keinen physischen Tastaturtest. Das Bild liegt
danach in `build/vice-pal.png`, Speicher und Timing in `build/memory.json`
und `build/timing.json`.

Die Tests benötigen außerdem das C16-KERNAL-ROM. Falls es nicht im VICE-
Datenverzeichnis gefunden wird, `C16_KERNAL` auf die Datei
`kernal-318004-05.bin` setzen.

In der aktuellen eingeschränkten macOS-Ausführungsumgebung startet VICE als
Unterprozess von Make/Python nicht zuverlässig. Der direkte CLI-Aufruf wurde
erfolgreich geprüft. Dort den Smoke-Test in drei getrennten Aufrufen ausführen:

```sh
python3 tests/vice_smoke.py --prepare-only
/opt/homebrew/bin/xplus4 -silent -default -console -model c16 -pal -ramsize 16 -sounddev dummy -warp -autostartprgmode 1 -autostart build/minigolf.prg -initbreak 0x0200 -moncommands build/vice-pal.mon -monlog -monlogname build/vice-pal.log -limitcycles 20000000
python3 tests/vice_smoke.py --verify-only
```

Gemessene Ergebnisse und noch offene Hardware-Nachweise:
[hardware.md](hardware.md).

## Reproduzierbare Mathematikmessung

`make benchmark` prüft die assemblierten Multiplikations- und Divisionsroutinen
gegen ganzzahlige Referenzen und schreibt alle Operanden und CPU-Zyklen nach
`build/math-benchmark.json`. Vorzeichen, Null, Achsenfaktoren und Grenzen der
spezialisierten Routinen sind enthalten. Die verschiedenen Ergebnisverträge
werden separat geprüft. Das ist eine deterministische Stichprobenmatrix,
kein vollständiger Worst-Case-Nachweis; TED-Wartezeiten fehlen.

Nächste Schritte: geschützte Speicherreserve schaffen, alternative Arithmetik
an diesen Messfällen vergleichen, anschließend allgemeine Eckensweeps im
PAL-Emulator messen und den kompakten Bahn-Decoder integrieren. Schritt 2
bleibt bis zur Speicher- und Laufzeitabnahme offen.
