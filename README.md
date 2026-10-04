# C16 Minigolf

Minigolf für den unveränderten Commodore 16 mit **16 KB RAM**, programmiert
mit **ACME im 6502-Modus**. Monochrome 320×200-Hi-Res-Grafik, reine Draufsicht.
Spielregeln und 18-Loch-Plan stehen in [SPEC.md](SPEC.md), der Fortschritt in
[TODO.md](TODO.md).

Aktueller Stand: spielbarer Physikprototyp auf einer geometrischen Testbahn.
A/D wählt eine von 128 Richtungen, W/S eine von 32 Stärken, SPACE schlägt,
P pausiert. Nach dem Einlochen startet SPACE die Testbahn neu. Während des
Rollens ist kein weiterer Schlag möglich. Kurze Tastendrücke ändern einen
Schritt; Halten wiederholt nach 15 Frames alle drei Frames.

Der Ball bewegt sich pixelgenau mit acht Nachkommabits, auch rechts von
x=255. Rollreibung, geometrische Banden-/Eckkontakte und Lochfang sind
implementiert. **Schritt 2 ist noch nicht abgenommen:** schwierige
Eckentreffer überschreiten das 50-Hz-Zeitbudget; für den vollständigen
18-Loch-Kurs ist weitere Speicheroptimierung erforderlich. Noch keine
Wertung, Materialien, Sound oder vollständige Runde.

Voraussetzungen: ACME 0.97 oder neuer, Make, Python 3 und VICE xplus4 mit
C16-ROMs. Bauen und im PAL-C16-Modell starten:

```sh
make
make run
```

Das Programm entsteht als `build/minigolf.prg` mit BASIC-SYS-Startstub.
Auf einem C16 von Diskette: `LOAD"MINIGOLF",8,1`, danach `RUN`.
Ein D64 und reale Hardwareprüfung gehören zur späteren Freigabe.

Tests des tatsächlich assemblierten 6502-Codes:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tests/requirements.txt
make test
make smoke # Zeitbudget-Prüfung meldet aktuell den bekannten Eckentreffer-Überlauf
```

`make test` verwendet py65 für Loader, Bitmap-Adressierung, Geometrie,
Hintergrundrestaurierung, Eingabe, Festkommaarithmetik, Bewegung und Kollisionen. `make smoke` startet VICE mit echten
ROMs, PAL und ausdrücklich 16 KB, prüft die TED-Konfiguration und misst
128 Richtungen und sechs Bewegungsszenarien. VICE steuert dabei logische Eingabeereignisse nach dem
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
[docs/hardware.md](docs/hardware.md).
