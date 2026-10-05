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
Eingabescan ein; das ersetzt keinen physischen Tastaturtest. Das Bild liegt
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
xplus4 -silent -default -console -model c16 -pal -ramsize 16 -sounddev dummy -warp -autostartprgmode 1 -autostart build/minigolf.prg -initbreak 0x0200 -moncommands build/vice-pal.mon -monlog -monlogname build/vice-pal.log -limitcycles 20000000
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

## Eckensweep-Profil

`make profile` führt sieben Physikframes für radiale, schräge und flache
Eckentreffer im assemblierten 6502-Code aus. `build/sweep-profile.json`
enthält die Aufrufzahlen sowie inklusive und exklusive CPU-Zyklen jedes
Aufrufs. Inklusive Zeiten enthalten Unteraufrufe und dürfen nicht addiert
werden; exklusive Zeiten teilen die Gesamtzeit auf. Äußere JSR fehlen,
interne JSR werden dem Aufrufer zugerechnet, RTS dem aufgerufenen Block.
Tail-Jumps und Inline-Code bleiben dem jeweiligen Aufruf zugeordnet.
Unbenannte Helfer erscheinen als Adresse. TED-Wartezeiten und Darstellung
fehlen: die PAL-Abnahme erfolgt weiterhin mit `make smoke`.

Die Zustandsfixtures in `tests/fixtures/corner-replays.json` stammen aus
Commit c01f930 vor dem direkten Kreisvergleich. Sie sichern Position,
Geschwindigkeit, Richtung und Spielzustand der jeweils sieben Frames.

## Joystick-Port und Feuerdauer

Die Tests prüfen auch die getrennte Joystick-/Pause-Abfrage, Entprellung,
Feuerdauer, Sättigung, Loslassen, Abbruch bei Pause sowie gehaltenes Feuer
nach Rollen/Neustart. Historische Eckensweep-Replays bekommen die gespeicherte
Geometrie aus `tests/fixtures/course-before-cell-grid.json`, damit die neuen
Rastermaße die alten Referenzzustände nicht verändern.

Zusätzlicher VICE-Test über den echten emulierten TED-Joystick-Pfad:

```sh
python3 tests/vice_joystick.py --prepare-only
xplus4 -silent -default -console -model c16 -pal -ramsize 16 -sounddev dummy -warp -autostartprgmode 1 -autostart build/minigolf.prg -initbreak 0x0200 -moncommands build/vice-joystick.mon -binarymonitor -binarymonitoraddress 127.0.0.1:6503
# Während VICE im Monitor wartet, in einem zweiten Terminal:
python3 tests/vice_joystick.py --verify-only
```

Der Client aktiviert das VICE-I/O-Simulationsgerät an Port 1 und setzt dessen
aktive-low Leitungen; er injiziert keine logischen Eingabe- oder Ladezustände.
Prüft Links/Rechts, 64 Feuerframes, Loslassen sowie leere Anleitung/Status und
gefüllten Balken. Bericht: `build/joystick-smoke.json`. Protokoll und Ressourcen:
[offizieller VICE-Monitor](https://vice-emu.sourceforge.io/vice_13.html).
Reale C16-Hardware und ein Host-USB-Joystick sind noch nicht geprüft.
