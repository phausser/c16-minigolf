# C16 Minigolf

Minigolf für den Commodore 16 mit 16 KB RAM: monochrome 320×200-Grafik,
Draufsicht und pixelgenaue Ballphysik. Der aktuelle Prototyp bietet eine
Testbahn; die geplante 18-Loch-Runde ist noch in Entwicklung.

Joystick an Port 1: links/rechts drehen die Richtung. Feuer halten lädt die
Schlagstärke; Loslassen schlägt. Bei voller Stärke bleibt der Balken gefüllt.
P pausiert und bricht eine laufende Aufladung ab. Nach dem Einlochen startet
Feuer die Testbahn neu; vor dem nächsten Schlag einmal loslassen.

## Bauen und starten

Voraussetzungen: ACME 0.97 oder neuer, Make und Python 3.
Zum Spielen im Emulator: VICE xplus4 mit C16-ROMs.

```sh
make
make run
```

`make run` übernimmt die Joystick-Einstellung aus der eigenen VICE-Konfiguration
(`~/.config/vice/vicerc`, z. B. Tastensatz in den VICE-Einstellungen gewählt und
gespeichert), ohne Autofeuer. Gerät erzwingen: `make run JOYDEV=1` (Ziffernblock),
`JOYDEV=2` (Tastensatz 1) oder `JOYDEV=4` (erster Host-Joystick).

Das Programm liegt in `build/minigolf.prg`. `make run` startet einen
PAL-C16 mit 16 KB RAM. Auf dem C16: `LOAD"MINIGOLF",8,1`, danach `RUN`.

Die Farben werden in `src/palette.inc` als `(LUMINANZ << 4) + FARBE`
konfiguriert: Luminanz 0–7, Farbe 0–15 (0 = Schwarz, 1 = Grau/Weiß).
`COURSE_SURFACE_COLOR` ist die hellgraue Fläche, `COURSE_MARKER_COLOR` färbt
Ball, Zielmarke und Loch, `COURSE_FRAME_COLOR` den Rahmen, `HUD_TEXT_COLOR` die Schrift der Statuszeile,
`HUD_FOREGROUND_COLOR`/`HUD_BACKGROUND_COLOR` Füllung und Grund des Ladebalkens. Außerhalb liegt ein
grünes Schachbrett aus `CHECKER_COLOR_EVEN`/`CHECKER_COLOR_ODD`. Die Rahmenbreite
an geraden Kanten steht als `FRAME_WIDTH` in `src/course_renderer.asm`.

Weitere Dokumentation: [Spezifikation](SPEC.md),
[Umsetzungsplan](TODO.md), [Entwicklung und Tests](docs/development.md)
und [Hardware-Nachweise](docs/hardware.md).
