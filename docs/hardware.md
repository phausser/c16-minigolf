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
| $0200–$175B | Laufzeitcode und Daten: 5468 Bytes |
| $175C–$179F | 68 freie Bytes |
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
Rollens bleiben Richtung und Stärke unverändert. Der Nutzer hat am
2026-10-04 A/D/W/S/SPACE/P mit echten VICE-Tastenereignissen bestätigt.
Der automatisierte Emulator-Smoke-Test injiziert weiterhin logische Ereignisse.

## Physikprüfung und Laufzeit

31 Tests des echten assemblierten 6502-Codes bestehen: Loader, Grafik,
Eingabe, Hintergrund, exakte Arithmetik, 128 Richtungen, Reichweiten und
Stillstand, Achsen-/Diagonalbanden, radiale Endpunkte, Streifkontakte,
Lochfang und deterministische längere Testbahn-Replays. Das ersetzt noch
keine vollständige unabhängige Geometrie-Referenz oder Physikfreigabe.

VICE bestätigt ROM-Start, TED-Konfiguration, Hintergrund und Steuerung.
Der Kreis-Sweep sucht Kontaktzeitbits mit exakten 24-Bit-Positionen
(Q8.16). Additionen ersetzen die wiederholten Bruchmultiplikationen, ohne
das Ergebnis zu vergröbern. Zusätzliche Tests vergleichen zufällige
Streifkontakte mit einer unabhängigen diskreten Geometrie-Referenz.
Ein spezieller Einheitvektor-Multiplizierer und eine verkürzte exakte
Geschwindigkeitswurzel sparen weitere Zyklen. Die Hauptschleife synchronisiert an Rasterzeile 205. Gemessener PAL-Abstand:
35563 Ticks; teuerster Ziel-/HUD-Redraw: 22961 Ticks.

| Bewegungsszenario, höchste Stärke | Schlechtester Frame, TED-Ticks |
|---|---:|
| Gerade | 10183 |
| Senkrechte Bande | 16179 |
| 45°-Bande | 27255 |
| Gerundete Ecke | 51436 |
| Doppelkontakt in Ecke | 45043 |
| Engstelle | 10434 |

**Die Framebudget-Abnahme scheitert.** Eckentreffer überschreiten ein
PAL-Bild. Die Physik bleibt
reproduzierbar, läuft bei diesen Spitzen aber langsamer als die beabsichtigte
50-Hz-Zeitbasis. `make smoke` meldet dies als Fehler und schreibt auch bei
Überschreitung `build/timing.json`. Die Grenze wird nicht gelockert. Vor
Bahnproduktion und Effekten müssen diese Spitzen sowie der RAM-Verbrauch
reduziert werden. Die geprüften Einlochgrenzfälle umfassen jetzt den Start innerhalb des
Fangradius und die reduzierte Geschwindigkeit unmittelbar nach einem
Abpraller. Kontakt-Epsilon und weitere Kontaktgrenzfälle bleiben offen.

In der eingeschränkten macOS-Umgebung startet VICE als Make/Python-
Unterprozess teilweise nicht zuverlässig; der direkte CLI-Aufruf wurde
geprüft. Vorbereitung, nativer Start und Prüfung sind deshalb getrennt
aufrufbar; siehe README. Das Host-Startproblem und die tatsächlich gemessene
Framebudget-Überschreitung sind getrennte Befunde.

Offen: vollständige Physikabnahme, 18-Bahnen-Budget, reale Hardware,
reale Eingabe am C16, Wertung, Materialien, Sound und NTSC.

## TED-Sound und PAL/NTSC für spätere Module

Registerbelegung laut TED-Datenblatt, Abschnitte Sound und Register 14–18:

| Register | Bedeutung |
|---|---|
| $FF0E | Stimme 1, Frequenzwert Bits 0–7 |
| $FF12 Bits 0–1 | Stimme 1, Frequenzwert Bits 8–9 |
| $FF0F | Stimme 2, Frequenzwert Bits 0–7 |
| $FF10 Bits 0–1 | Stimme 2, Frequenzwert Bits 8–9 |
| $FF11 Bits 0–3 | Gemeinsame Lautstärke 0–8; 9–15 ebenfalls Maximum |
| $FF11 Bit 4 | Stimme 1 einschalten |
| $FF11 Bit 5 | Stimme 2 als Rechteck einschalten |
| $FF11 Bit 6 | Rauschen einschalten; Rechteck-Stimme 2 hat Vorrang |
| $FF11 Bit 7 | Sound-Reload/Test; im normalen Betrieb null |

Für Frequenzwert N gilt ungefähr f = 110840,45/(1024−N) Hz bei PAL,
111860,781/(1024−N) Hz bei NTSC. Beide Stimmen teilen die Lautstärke.
Wichtig für Hi-Res: Sound darf beim Schreiben von $FF12 nur Bits 0–1
ändern; Bitmap- und ROM/RAM-Auswahl bleiben erhalten. Dafür verwendet das
spätere Soundmodul einen gemeinsamen Register-Schatten mit der Grafik.
Der aktuelle Start schaltet Sound über $FF11=0 aus.

$FF07 Bit 6 wählt NTSC (1) oder PAL (0). Eine Moduserkennung muss **vor**
der Videoinitialisierung erfolgen: diese setzt derzeit ausdrücklich PAL.
Als unabhängige Kontrolle lässt sich über einen vollständigen Rasterumlauf
der höchste 9-Bit-Zeilenwert messen: $FF1C Bit 0 und $FF1D konsistent
lesen (High–Low–High; bei geändertem High wiederholen). PAL zählt 0–311,
NTSC 0–261. Das gewählte Bit ist kein Beweis für den Hardware-Oszillator.
Der Release bleibt daher PAL-only, bis ein eigener NTSC-Laufzeitnachweis
und eine 50-Hz-Zeitbasis für NTSC vorliegen. Keine automatische Umstellung
auf PAL auf einem NTSC-Gerät als vermeintliche Unterstützung.

Schritt 1 ist damit abgeschlossen: Sound-/Modusregister sind dokumentiert,
Build und PAL-Emulatorstart geprüft und die sechs Spieltasten vom Nutzer
in VICE bestätigt. Dies ist keine Behauptung eines Tests auf echtem C16.
