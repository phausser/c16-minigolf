# C16-Prototyp: Nachweise und Grenzen

Stand: 2026-10-04. ACME 0.97, VICE 3.10, C16/PAL mit 16 KB,
KERNAL 318004-05 und BASIC 318006-01.

## Speicher und Start

PRG: 12282 Bytes einschließlich Ladeadresse; BASIC-Start `SYS4109`.
Ein temporärer Kopierer läuft im unteren Stackbereich ab $0100 und kopiert
überlappungssicher den Laufzeitkörper nach $0200. Währenddessen erfolgt
kein Unterprogrammaufruf; der Stackpointer wird danach auf $FF gesetzt.
Die Tests führen den tatsächlichen Loader aus, auch mit zusätzlicher
Füllung, die das Überschreiben des ursprünglichen SYS-Stubs provoziert.

| Bereich | Verwendung |
|---|---|
| $0200–$17A4 | Laufzeitcode und Daten: 5541 Bytes |
| $17A5–$17C9 | 37 freie Bytes |
| $17CA–$17FF | 54 Bytes Hintergrundrestaurierung |
| $1800–$1FFF | TED-Luminanz und Farbe |
| $2000–$213F | Unsichtbare Bitmap-Zeile: Quadrattabellen und Normalen |
| $2140–$3A3F | Sichtbares Spielfeld |
| $3A40–$3B7F | Unsichtbare Trennzeile: statischer Bahnzeichner, 319 Bytes |
| $3B80–$3CBF | Bedienhilfe, HUD-Zeile 22 |
| $3CC0–$3DFF | Unsichtbare HUD-Zeile: weite Mathematik und Komponentennormierung, 308 Bytes |
| $3E00–$3F3F | Stärke/Status, HUD-Zeile 24 |
| $3F40–$3FFF | Nicht sichtbares Bitmap-Ende: Initialisierung 143 Bytes und Diagonal-Guard 42 Bytes |

Die drei versteckten Bitmap-Zeilen haben identische schwarze Vorder- und
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
Im HUD ergeben Luminanz/Farbe $07/$10 Weiß auf Schwarz. Im Spielfeld
ergeben $30/$01 Schwarz auf Mittelgrau, Schattenzellen $10/$01 Schwarz
auf Dunkelgrau. Multicolor bleibt aus.
IRQ-Quellen sind deaktiviert. VICE prüft die Register mit passenden Masken.

Bitmap-Adresse: $2000 + floor(y/8)×320 + floor(x/8)×8 + (y mod 8).
Die Tests prüfen alle 200 Zeilen, insbesondere x=255/256/319. Text liest
den eingebauten ROM-Zeichensatz direkt, ohne ROM-Routinen aufzurufen.

17 Kontursegmente belegen 85 Bytes einschließlich Normalenindex. Neun
zusätzliche Füllkanten belegen 36 Bytes; sie sind aus denselben Konturen
abgeleitet. Ein byteweiser Even/Odd-Scanline-Füller öffnet die graue Fläche
in einer schwarzen Bitmap, mit halboffenen y-Intervallen. Renderer und
Kollision nutzen dieselbe Innenkante. Obere/linke Innenkanten bekommen
einen dunkelgrauen Hintergrund im 8×8-Zellraster. Schatten werden vor
dem Lochring bestimmt; Ball und Loch werfen keine eigenen Schatten. Der Generator prüft Grenzen, Segmentlimit,
Nullsegmente, zulässige Winkel und Konturschnittpunkte. Ballfreiheit und
Erreichbarkeit sind noch keine vollständigen Validator-Nachweise.

Die 21-Pixel-Ballform wird mit fünf Zeilenmasken gezeichnet. Höchstens
zehn Bitmap-Bytes und acht Zielpunkte sichern Adresse und ursprünglichen
Bytewert. Rückwärtsrestaurierung erhält überlappende Ball-/Ziel-/Wandbytes.
Alle acht horizontalen Pixel-Ausrichtungen, x=255/256 und die rechte
Bildkante sind gegen ein unabhängiges Pixelbild geprüft. Die Form und
Subpixel-Rundung sind identisch zur vorherigen Darstellung. Die Bedienhilfe
steht jetzt in Zeile 22; die vorherige Titelzeile entfällt zugunsten des
Mathematikbereichs. Stärke und Status bleiben in Zeile 24.

Tastaturmatrix: A=(1,2), D=(2,2), W=(1,1), S=(1,5), P=(5,1),
SPACE=(7,4). $FD30 wählt aktive niedrige Zeilen, $FF08 liest Spalten.
Zwei gleiche Samples entprellen; SPACE/P wiederholen nicht. Während des
Rollens bleiben Richtung und Stärke unverändert. Der Nutzer hat am
2026-10-04 A/D/W/S/SPACE/P mit echten VICE-Tastenereignissen bestätigt.
Der automatisierte Emulator-Smoke-Test injiziert weiterhin logische Ereignisse.

## Physikprüfung und Laufzeit

43 automatisierte Tests bestehen, davon 36 am assemblierten Kern und
sieben für Host-Geometrie/Export. Geprüft sind: Loader, Grafik,
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
35573 Ticks; teuerster Ziel-/HUD-Redraw: 16751 Ticks.

| Bewegungsszenario, höchste Stärke | Schlechtester Frame, TED-Ticks |
|---|---:|
| Gerade | 6445 |
| Senkrechte Bande | 9558 |
| 45°-Bande | 14045 |
| Radiale Diagonalecke | 25880 |
| Doppelkontakt in Ecke | 23038 |
| Engstelle | 6515 |
| Schräger Eckanflug | 40247 |
| Flacher Eckanflug | 36550 |

**Die Framebudget-Abnahme scheitert.** Eckentreffer überschreiten ein
PAL-Bild. Die Physik bleibt
reproduzierbar, läuft bei diesen Spitzen aber langsamer als die beabsichtigte
50-Hz-Zeitbasis. `make smoke` meldet dies als Fehler und schreibt auch bei
Überschreitung `build/timing.json`. Die Grenze wird nicht gelockert. Vor
Bahnproduktion und Effekten müssen diese Spitzen sowie der RAM-Verbrauch
reduziert werden. Die geprüften Einlochgrenzfälle umfassen jetzt den Start innerhalb des
Fangradius und die reduzierte Geschwindigkeit unmittelbar nach einem
Abpraller. Die Wand-Gap-Toleranz von 2/256 Pixel ist gegen ein und zwei
Einheiten Überlappung geprüft. Gleichzeitige Kontakte und weitere
Kontaktgrenzfälle bleiben offen.

In der eingeschränkten macOS-Umgebung startet VICE als Make/Python-
Unterprozess teilweise nicht zuverlässig; der direkte CLI-Aufruf wurde
geprüft. Vorbereitung, nativer Start und Prüfung sind deshalb getrennt
aufrufbar; siehe [Entwicklung und Tests](development.md). Das Host-Startproblem und die tatsächlich gemessene
Framebudget-Überschreitung sind getrennte Befunde.

Offen: vollständige Physikabnahme, 18-Bahnen-Budget, reale Hardware,
reale Eingabe am C16, Wertung, Materialien, Sound und NTSC.

## Export- und RAM-Hochrechnung

`make budget` erzeugt den Richtungs-/Längenstrom der Testbahn und liest
seine Geometrie zurück. Der Export benötigt 39 statt 85 Bytes. Die
Hochrechnung 18 × 39 + 36 Verzeichnisbytes ergibt 738 Bytes. Sie verwendet
den echten Testexport, aber noch keine 18 finalen Bahnen. Der Hauptbereich
hat jetzt 98 freie Bytes; bereits die Geometrie-Hochrechnung benötigt
640 zusätzliche Bytes. ACME-Decoder, aktuelle entpackte Bahn, Name/Par,
Materialien und Spielmodule sind in diesem Bedarf noch nicht enthalten.
`build/course-budget.json` benennt diese Annahmen ausdrücklich.

Die neuen Sonderfälle verbessern die Laufzeit auf Kosten des Codeumfangs.
Weitere einzelne Abkürzungen im Hauptbereich lösen das Gesamtbudget nicht.
Die konkrete nächste Architekturarbeit steht in [TODO.md](../TODO.md): geschützte,
garantiert freie Bitmapbereiche für Daten ausweisen, Kursbestand und
aktuelle Bahn trennen, anschließend allgemeinen Kreis-Sweep und
Worst-Case-Messmatrix verbessern. Zielreserve: höchstens 32000 TED-Ticks
für jeden geprüften Frame. Schritt 2 ist weiterhin nicht abgenommen.

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

## Divisionsoptimierung (2026-10-04)

`divide_fraction` wählt bei Nennern unter 32768 einen exakten 16-Bit-Pfad.
Größere Nenner verwenden weiterhin 24 Bit. Beide Pfade subtrahieren
probeweise und übernehmen den Rest nur bei erfolgreicher Subtraktion.
Der breite Pfad nutzt zusätzlich `M_TRIAL` als Scratch; X und Y sind zerstört.
Quotient und Rest sind gegen Integer-Referenzen einschließlich 32767/32768,
65535/65536 und 2^23 geprüft. Die Routine benötigt 21 zusätzliche Bytes
in der bereits geschützten HUD-Zeile; im Hauptbereich bleiben sieben frei.

Die erweiterte Benchmarkmatrix umfasst 448 geprüfte Fälle, davon 45 für
die Division (337–578 CPU-Zyklen). Die ursprüngliche Matrix ohne die neuen
Grenzfälle maß 287–711 Zyklen: einzelne leichte Fälle werden langsamer,
der höchste gemessene Wert und die geprüften PAL-Kontaktframes sinken.
Die Tabelle oben enthält die neue VICE-Messung; die Laufzeitabnahme bleibt offen.

## Codeverkleinerung bei unverändertem Spielfeld

Die Haupt-Runtime ist von 5571 auf 5436 Bytes geschrumpft: 135 Bytes
gespart, 142 Bytes vor dem Render-Scratch frei. Gemeinsame Negationen
werden nur in selteneren Physikpfaden genutzt; heiße Arithmetik bleibt
inline. Achsennormierung nutzt einen gemeinsamen Pfad, Achsenreflexion
berechnet direkt floor(v/16)−v. Der feste Kreisvergleich berücksichtigt
die Nullbytes der Radienquadrate. Grenztests verlangen weiterhin einen
strikten Vergleich am Radius und prüfen beide Achsen/Vorzeichen.
42 Tests und 448 Mathematikfälle bestehen. Die Tabelle oben zeigt den
aktuellen PAL-Stand; der schlechteste Frame liegt bei 40542 Ticks.

142 Bytes reichen rechnerisch für drei weitere 39-Byte-Geometrien samt
je zwei Zeigerbytes. Das ist keine Freigabe von vier spielbaren Bahnen:
Decoder, Reserve für die aktuelle 32-Segment-Bahn und Metadaten fehlen
weiterhin. Der existierende Kern spielt eine Testbahn.

## Direktes Kreisprädikat und Aufrufprofil

`make profile` misst Aufrufzahlen und inklusive/exklusive CPU-Zyklen der
assemblierten Physik. Vor dem Umbau: schräge Ecke 25255 CPU-Zyklen, danach
24974. Die Kreisprüfung summiert die exakten Quadrate ohne unnötige
Produktstores und bricht bei einer bereits zu großen Achsenkomponente ab.
Unter dem 7-Pixel-Prefilter plus maximal vier Pixel Schritt gilt
|QX|, |QY| <=2815. Die beiden festen Radien bleiben strikt; Kreisgrenzen
und Zufallskoordinaten werden gegen Integer-Geometrie geprüft.

Alle 43 Tests sowie 448 Mathematikfälle bestehen. Drei gespeicherte
Eckenszenarien behalten ihre bisherigen Zustände über jeweils sieben
Frames bytegenau. In VICE sinkt der schlechteste gemessene Frame von
40542 auf 40247 Ticks. **Das PAL-Zeitbudget scheitert weiterhin.**
Die Haupt-Runtime benötigt jetzt 5480 Bytes, 98 bleiben frei. Gegenüber
c01f930 kostet diese Beschleunigung 44 Bytes; Geometrie, Spielfeld und
Kontaktgenauigkeit bleiben erhalten.

## Graue Flächen und Zellschatten (2026-10-04)

43 Tests bestehen, einschließlich unabhängiger punktweiser Konturprüfung,
Zellfarben und unveränderter geschützter Bitmapzeilen. VICE bestätigt das
Bild in `build/vice-pal.png`, ROM-Start, Eingabe und Restaurierung bei allen
128 Richtungen. Neues Maximum für Anzeige/Steuerung: 16832 PAL-Ticks.
Physikmaximum: 40250 PAL-Ticks; `make smoke` scheitert weiterhin am offenen
32000-Tick-Budget. Die Physik und ihre gesicherten Replays sind unverändert.
Die Grafik kostet 61 zusätzliche Runtime-Bytes sowie 14 Bytes im statischen
Renderer und drei Bytes im Bitmap-Ende. Es bleiben 37 Runtime-Bytes frei.

Die Palette steht zentral in `src/palette.inc` als `(LUMINANZ << 4) + FARBE`.
Die getrennten Hi-Res-Attributbytes werden zur Assemblierzeit daraus
abgeleitet. Fläche und Schatten teilen sich denselben Farbton.
