# C16-Prototyp: Nachweise und Grenzen

Stand: 2026-10-04. ACME 0.97, VICE 3.10, C16/PAL mit 16 KB,
KERNAL 318004-05 und BASIC 318006-01.

## Speicher und Start

PRG: 12229 Bytes einschließlich Ladeadresse; BASIC-Start `SYS4109`.
Ein temporärer Kopierer läuft im unteren Stackbereich ab $0100 und kopiert
überlappungssicher den Laufzeitkörper nach $0200. Währenddessen erfolgt
kein Unterprogrammaufruf; der Stackpointer wird danach auf $FF gesetzt.
Die Tests führen den tatsächlichen Loader aus, auch mit zusätzlicher
Füllung, die das Überschreiben des ursprünglichen SYS-Stubs provoziert.

| Bereich | Verwendung |
|---|---|
| $0200–$1686 | Laufzeitcode und Daten: 5255 Bytes |
| $1687–$179F | 281 freie Bytes |
| $17A0–$17FF | 96 Bytes Hintergrundrestaurierung |
| $1800–$1FFF | TED-Luminanz und Farbe |
| $2000–$213F | Unsichtbare Bitmap-Zeile: Quadrattabellen und Normalen |
| $2140–$3A3F | Sichtbares Spielfeld |
| $3A40–$3B7F | Unsichtbare Trennzeile: statischer Bahnzeichner, 303 Bytes |
| $3B80–$3F3F | HUD |
| $3F40–$3FFF | Nicht sichtbares Bitmap-Ende: Initialisierung, 132 Bytes |

Die beiden versteckten Bitmap-Zeilen haben identische schwarze Vorder- und
Hintergrundfarbe. Zeichner und Clear-Routinen schützen diese Bereiche.
Der Loader transportiert die oberen Tabellen zunächst ab $3000; die
Initialisierung installiert sie vor dem Löschen der sichtbaren Bitmap.
Zero Page enthält Zustand, temporäre Mathematik und die 32-Byte-
Kandidatenliste. $00/$01 bleiben CPU-I/O. Größenbericht und Assemblierzeit-
Prüfungen sichern das 16-KB-Limit. Alle 18 Bahnen passen noch nicht
nachweislich hinein; weitere Speicheroptimierung ist Voraussetzung.

## TED, Darstellung und Eingabe

Primärquelle: [Commodore TED 7360 Datenblatt](https://www.karlstechnology.com/commodore/TED7360-datasheet.pdf).
$FF06=$3B, $FF07=$08, $FF12=$08, $FF14=$18 schalten 320×200-Hi-Res,
PAL/40 Spalten, RAM-Bitmap $2000 und Attribute $1800/$1C00 ein.
Attributwerte $07/$10 ergeben Weiß auf Schwarz; Multicolor bleibt aus.
IRQ-Quellen sind deaktiviert. VICE prüft die Register mit passenden Masken.

Bitmap-Adresse: $2000 + floor(y/8)×320 + floor(x/8)×8 + (y mod 8).
Die Tests prüfen alle 200 Zeilen, insbesondere x=255/256/319. Text liest
den eingebauten ROM-Zeichensatz direkt, ohne ROM-Routinen aufzurufen.

17 Kontursegmente belegen 85 Bytes einschließlich Normalenindex. Renderer
und Kollision nutzen dieselbe Innenkante. Drei Pixel breite Wandstriche
liegen auf der festen Seite. Der Generator prüft Grenzen, Segmentlimit,
Nullsegmente, zulässige Winkel und Konturschnittpunkte. Ballfreiheit und
Erreichbarkeit sind noch keine vollständigen Validator-Nachweise.

21 Ballpunkte und acht Zielpunkte sichern Adresse und ursprüngliches
Bitmap-Byte. Rückwärtsrestaurierung erhält den Hintergrund auch bei
mehreren Punkten im selben Byte. Alle 128 Zielrichtungen sind geprüft.
Der Ball rundet seine wirkliche Subpixelposition auf einzelne Pixel.

Tastaturmatrix: A=(1,2), D=(2,2), W=(1,1), S=(1,5), P=(5,1),
SPACE=(7,4). $FD30 wählt aktive niedrige Zeilen, $FF08 liest Spalten.
Zwei gleiche Samples entprellen; SPACE/P wiederholen nicht. Während des
Rollens bleiben Richtung und Stärke unverändert. Physische Tasten bleiben
ungeprüft; der Emulator-Smoke-Test injiziert logische Ereignisse.

## Physikprüfung und Laufzeit

26 Tests des echten assemblierten 6502-Codes bestehen: Loader, Grafik,
Eingabe, Hintergrund, exakte Arithmetik, 128 Richtungen, Reichweiten und
Stillstand, Achsen-/Diagonalbanden, radiale Endpunkte, Streifkontakte,
Lochfang und deterministische längere Testbahn-Replays. Das ersetzt noch
keine vollständige unabhängige Geometrie-Referenz oder Physikfreigabe.

VICE bestätigt ROM-Start, TED-Konfiguration, Hintergrund und Steuerung.
Die Hauptschleife synchronisiert an Rasterzeile 205. Gemessener PAL-Abstand:
35563 Ticks; teuerster Ziel-/HUD-Redraw: 22859 Ticks.

| Bewegungsszenario, höchste Stärke | Schlechtester Frame, TED-Ticks |
|---|---:|
| Gerade | 12210 |
| Senkrechte Bande | 19269 |
| 45°-Bande | 34107 |
| Gerundete Ecke | 66906 |
| Doppelkontakt in Ecke | 46354 |
| Engstelle | 12787 |

**Die Framebudget-Abnahme scheitert.** Eckentreffer überschreiten ein
PAL-Bild; die 45°-Bande hat zu wenig Reserve. Die Physik bleibt
reproduzierbar, läuft bei diesen Spitzen aber langsamer als die beabsichtigte
50-Hz-Zeitbasis. `make smoke` meldet dies als Fehler und schreibt auch bei
Überschreitung `build/timing.json`. Die Grenze wird nicht gelockert. Vor
Bahnproduktion und Effekten müssen diese Spitzen sowie der RAM-Verbrauch
reduziert werden. Einloch-/Kontaktgrenzfälle bleiben in TODO.md offen.

In der eingeschränkten macOS-Umgebung startet VICE als Make/Python-
Unterprozess teilweise nicht zuverlässig; der direkte CLI-Aufruf wurde
geprüft. Vorbereitung, nativer Start und Prüfung sind deshalb getrennt
aufrufbar; siehe README. Das Host-Startproblem und die tatsächlich gemessene
Framebudget-Überschreitung sind getrennte Befunde.

Offen: vollständige Physikabnahme, 18-Bahnen-Budget, reale Hardware,
physische Eingabe, Wertung, Materialien, Sound und NTSC.
