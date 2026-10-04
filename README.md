# C16 Minigolf

Minigolf für den Commodore 16 mit 16 KB RAM: monochrome 320×200-Grafik,
Draufsicht und pixelgenaue Ballphysik. Der aktuelle Prototyp bietet eine
Testbahn; die geplante 18-Loch-Runde ist noch in Entwicklung.

A/D wählt die Richtung, W/S die Stärke, SPACE schlägt und P pausiert.
Nach dem Einlochen startet SPACE die Testbahn neu.

## Bauen und starten

Voraussetzungen: ACME 0.97 oder neuer, Make und Python 3.
Zum Spielen im Emulator: VICE xplus4 mit C16-ROMs.

```sh
make
make run
```

Das Programm liegt in `build/minigolf.prg`. `make run` startet einen
PAL-C16 mit 16 KB RAM. Auf dem C16: `LOAD"MINIGOLF",8,1`, danach `RUN`.

Die Farben werden in `src/palette.inc` als `(LUMINANZ << 4) + FARBE`
konfiguriert: Luminanz 0–7, Farbe 0–15 (0 = Schwarz, 1 = Grau/Weiß).
Fläche und Schatten teilen sich aktuell denselben Farbton.

Weitere Dokumentation: [Spezifikation](SPEC.md),
[Umsetzungsplan](TODO.md), [Entwicklung und Tests](docs/development.md)
und [Hardware-Nachweise](docs/hardware.md).
