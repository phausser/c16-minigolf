# C16-Prototyp: Nachweise und Grenzen

Stand: 2026-10-04. ACME 0.97, VICE 3.10, C16/PAL mit 16 KB,
KERNAL 318004-05 und BASIC 318006-01.

## Speicher und Start

PRG: 12279 Bytes einschließlich Ladeadresse; BASIC-Start `SYS4109`.
Ein temporärer Kopierer läuft im unteren Stackbereich ab $0100 und kopiert
überlappungssicher den Laufzeitkörper nach $0200. Währenddessen erfolgt
kein Unterprogrammaufruf; der Stackpointer wird danach auf $FF gesetzt.
Die Tests führen den tatsächlichen Loader aus, auch mit zusätzlicher
Füllung, die das Überschreiben des ursprünglichen SYS-Stubs provoziert.

| Bereich | Verwendung |
|---|---|
| $0100–$019F | Entpackte aktuelle Bahn, bis 32 Segmente (beim Start vorher Kopierer) |
| $01A0–$01D5 | 54 Bytes Hintergrundrestaurierung |
| $01D6–$01FF | Stack, 42 Bytes reserviert; gemessene Tiefe 12 Bytes |
| $0200–$168F | Laufzeitcode, Bahn-Decoder und gepackte Bahnen: 5264 Bytes |
| $1690–$17FF | 368 freie Bytes |
| $1800–$1FFF | TED-Luminanz und Farbe |
| $2000–$213F | Unsichtbare Bitmap-Zeile: Quadrattabellen und Normalen |
| $2140–$3A3F | Sichtbares Spielfeld |
| $3A40–$3DFF | Unsichtbare Zeilen 21–23: Bahnzeichner mit Zellformung und Farben, weite Mathematik; 876 Bytes, 84 frei |
| $3E00–$3F3F | Stärke, HUD-Zeile 24 |
| $3F40–$3FFF | Nicht sichtbares Bitmap-Ende: Initialisierung 115 Bytes und Diagonal-Guard 42 Bytes |

Die vier versteckten Bitmap-Zeilen (0, 21–23) haben identische Vorder- und
Hintergrundfarbe (grünes Schachbrett). Zeichner und Clear-Routinen schützen diese Bereiche.
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
Im HUD ergeben Luminanz/Farbe $07/$10 Weiß auf Schwarz. Spielfeld siehe
Abschnitt „Rahmen, Schrägen und grünes Schachbrett (2026-10-05)“.
Palette in src/palette.inc; keine Muster, keine Schatten, kein Multicolor.
IRQ-Quellen sind deaktiviert. VICE prüft die Register mit passenden Masken.

Bitmap-Adresse: $2000 + floor(y/8)×320 + floor(x/8)×8 + (y mod 8).
Die Tests prüfen alle 200 Zeilen, insbesondere x=255/256/319. Text liest
den eingebauten ROM-Zeichensatz direkt, ohne ROM-Routinen aufzurufen.

Die Testbahn liegt gepackt (Format 2, tools/course_codec.py) in 36 Bytes vor.
decode_course entpackt 17 Kontursegmente zu 85 Bytes einschließlich
Normalenindex und Endpunkt-Flag; Start und Loch stehen in der Zero Page.
Der Zeichner leitet die Füllkanten direkt aus den nicht waagerechten
Segmenten ab. Ein byteweiser Even/Odd-Scanline-Füller öffnet die glatte Fläche
in einer schwarzen Bitmap, mit halboffenen y-Intervallen. Renderer und
Kollision nutzen dieselbe Innenkante. Die Flächenfarbe ist
gleichmäßig; Zellschatten wurden auf Nutzerwunsch wieder entfernt. Der Generator prüft Grenzen, Segmentlimit,
Nullsegmente, zulässige Winkel und Konturschnittpunkte. Ballfreiheit und
Erreichbarkeit sind noch keine vollständigen Validator-Nachweise.

Die 21-Pixel-Ballform wird mit fünf Zeilenmasken gezeichnet. Höchstens
zehn Bitmap-Bytes und acht Zielpunkte sichern Adresse und ursprünglichen
Bytewert. Rückwärtsrestaurierung erhält überlappende Ball-/Ziel-/Wandbytes.
Alle acht horizontalen Pixel-Ausrichtungen, x=255/256 und die rechte
Bildkante sind gegen ein unabhängiges Pixelbild geprüft. Die Form und
Subpixel-Rundung sind identisch zur vorherigen Darstellung. Bedienhilfe und
Titelzeile entfallen; Zeile 22 ist jetzt versteckter Codebereich. Die Stärke
steht allein in Zeile 24.

Tastaturmatrix: A=(1,2), D=(2,2), W=(1,1), S=(1,5), P=(5,1),
SPACE=(7,4). $FD30 wählt aktive niedrige Zeilen, $FF08 liest Spalten.
Zwei gleiche Samples entprellen; SPACE/P wiederholen nicht. Während des
Rollens bleiben Richtung und Stärke unverändert. Der Nutzer hat am
2026-10-04 A/D/W/S/SPACE/P mit echten VICE-Tastenereignissen bestätigt.
Der automatisierte Emulator-Smoke-Test injiziert weiterhin logische Ereignisse.

## Physikprüfung und Laufzeit

51 automatisierte Tests bestehen (Stand 2026-10-05), davon 44 am
assemblierten Kern und sieben für Host-Geometrie/Export. Geprüft sind: Loader, Grafik,
Eingabe, Hintergrund, exakte Arithmetik, 128 Richtungen, Reichweiten und
Stillstand, Achsen-/Diagonalbanden, radiale Endpunkte, Streifkontakte,
Lochfang und deterministische längere Testbahn-Replays. Das ersetzt noch
keine vollständige unabhängige Geometrie-Referenz oder Physikfreigabe.

VICE bestätigt ROM-Start, TED-Konfiguration, Hintergrund und Steuerung.
Der Kreis-Sweep sucht Kontaktzeitbits mit exakten 24-Bit-Positionen
(Q8.16). Additionen ersetzen die wiederholten Bruchmultiplikationen, ohne
das Ergebnis zu vergröbern. Zusätzliche Tests vergleichen zufällige
Streifkontakte mit einer unabhängigen diskreten Geometrie-Referenz.
Abpraller spiegeln den Einheitsvektor direkt und ziehen den Verlust von
SPEED ab; Wurzel und Divisionen nach einem Kontakt entfallen. Die Kreis-
Bitsuche endet bei 1/16 Frame. Die Hauptschleife synchronisiert an
Rasterzeile 205. Gemessener PAL-Abstand: 35568 Ticks; teuerster Ziel-/HUD-
Redraw: 6508 Ticks. Stand 2026-10-05, Schuss-Frame jeweils inklusive Start
des Schlags, HUD-Balken und Ball neu zeichnen:

| Bewegungsszenario, höchste Stärke | Schlechtester Frame, TED-Ticks |
|---|---:|
| Gerade | 4020 |
| Senkrechte Bande | 7334 |
| 45°-Bande | 7146 |
| Radiale Diagonalecke (Winkel 16) | 19560 |
| Doppelkontakt in Ecke | 16449 |
| Engstelle | 4121 |
| Schräger Eckanflug (Winkel 17) | 22182 |
| Flacher Eckanflug (Winkel 14) | 18822 |
| Schräger Eckanflug, Winkel 100 | 29817 |
| Flacher Eckanflug, Winkel 102 | 24953 |
| Radiale Ecke, Winkel 100 | 28294 |
| Radiale Ecke, Winkel 12 | 30173 |

**Die Framebudget-Abnahme besteht** (Grenze 32000 Ticks, 1827 Reserve).
Die zusätzlichen Winkel sind die teuersten eines py65-Sweeps über alle
128 Richtungen an den acht Startpunkten. Das ist kein Beweis für jede
mögliche Position; weitere Bahnen müssen erneut gemessen werden.
Die geprüften Einlochgrenzfälle umfassen jetzt den Start innerhalb des
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
abgeleitet. Die Spielfläche hat eine gleichmäßige Hintergrundfarbe.

## Schatten wieder entfernt (2026-10-04)

Schattenroutine und Schattenfarbe entfernt; gleichmäßige Fläche mit der vom
Nutzer gewählten Luminanz 5. 43 Tests und VICE-Grafikprüfung bestehen.
Runtime 5516 Bytes, 62 frei; Renderer/Paletteninitialisierung 239/320 Bytes.
Physikmaximum 40253 PAL-Ticks; die 32000-Tick-Abnahme bleibt offen. Die
vorherigen Schattenmessungen oben beschreiben den historischen Stand.

## Weiße Markierungen auf gemusterter Fläche (2026-10-04)

Ersetzt den früheren Stand mit echter grauer Hintergrundfarbe: Hi-Res bleibt
320×200, weiße Vordergrundpixel und schwarzer Hintergrund in jeder Zelle.
Das 50%-Schachbrettmuster wird direkt beim Füllen durch Maskieren der
Scanline-Spannen erzeugt; kein zusätzlicher Bildspeicher. 43 Tests bestehen,
einschließlich unabhängiger punktweiser Geometrie und Musterparität. VICE
bestätigt Bild, Palette und Restaurierung. Runtime unverändert 5516 Bytes,
62 frei; Renderer/Palette/Muster 253/320 Bytes. PRG 12282 Bytes. Physikmaximum
40253 PAL-Ticks, Laufzeitabnahme weiter offen. Historische Graufarbwerte und
Schattenmessungen oben sind überholt.

## Glatte Fläche mit zellabhängiger Markierungsfarbe (2026-10-04)

Aktueller Stand ersetzt die Musterlösung: Grau als Hintergrund, Weiß als
Vordergrund in vollständig spielbaren Zellen, Schwarz als Vordergrund in
allen Zellen mit festen Geometriepixeln. Die schwarze Kontur bleibt exakt.
Markierungen übernehmen die Zellfarbe und können am Übergang schwarz/weiß
geteilt sein. Keine Änderung der Bahngeometrie oder Physik.
44 Tests bestehen, einschließlich unabhängiger Kontur-/Zellklassifizierung
und Restaurierung von Markierungen an geraden/schrägen Kanten. VICE prüft
alle 800 Zellattribute gegen die Geometrie und bestätigt die glatte Fläche.
Runtime weiter 5516 Bytes, 62 frei; statischer Renderer 287/320 Bytes;
Bitmap-Ende 182/192 Bytes. PRG 12279 Bytes. Physikmaximum weiterhin 40253
PAL-Ticks; die Abnahme von höchstens 32000 bleibt offen.

## Rasterkonturen, Joystick und aufgeladener Schlag (2026-10-04)

Gerade Konturen jetzt vollständig am 8×8-Raster: x=196→200, y=84→88;
Engstelle 16 statt 12 Pixel. Der Generator weist unrasterige gerade Kanten
zurück. Diagonale bleibt unverändert. Originalgeometrie als Testfixture
bewahrt; alte sieben-Frame-Replays laufen weiterhin bitgenau dagegen.

Joystick Port 1 getrennt von der Tastatur: FD30=$FF, FF08=$FB, links/rechts
Bits 2/3, Feuer Bit 6 aktiv niedrig. Pause: FD30=$DF, FF08=$FF, Bit 1.
47 Tests bestehen. VICE-Binärmonitor mit I/O-Simulationsgerät bestätigt den
TED-Abfragepfad, links/rechts, Laden bis 32 und Schlag erst beim Loslassen.
Nur Stärke bleibt im HUD; Anleitung und Statuswörter entfernt.

Bei 50 Hz Start mit Stärke 1, alle zwei Frames +1, Sättigung bei 32 nach etwa
1,3 s. Loslassen entprellt, Pause löscht die Aufladung. Während Rollen und
nach Pause/Neustart gehaltenes Feuer wird bis zum Loslassen gesperrt.
Reale Hardware bleibt ungeprüft. make run startet ohne -default, damit die
gespeicherte VICE-Joystick-/Tastensatz-Einstellung gilt; JOYDEV erzwingt ein Gerät.

Runtime 5381 Bytes, 197 frei; 135 Bytes gegenüber dem letzten Stand gewonnen.
PRG 12279 Bytes. Renderer 287, weite Mathematik 308, Bitmap-Ende 182 Bytes.
VICE: Anzeige/Steuerung maximal 7205 Ticks, Physik-/Schlagframe maximal 38873,
Frameperiode 35569. Kein Nachweis einer Physikoptimierung: Geometrie und
HUD/Steuerungsarbeit wurden geändert. 32000-Tick-Abnahme weiterhin offen.

Neuer kompakter Testexport 37 statt 39 Bytes; 18 gleich große Exporte
plus Verzeichnis: 702 Bytes, 505 fehlen plus Decoder/Metadaten.

## Speicherarchitektur und Laufzeitoptimierung (2026-10-05)

Ziel war, ohne Bildrand-Speicher (Spalten 0/39 bleiben auf Nutzerwunsch
frei) Platz für 18 Bahnen zu schaffen und das 32000-Tick-Budget einzuhalten.

Speicher:

| Änderung | Wirkung |
|---|---|
| HUD-Zeile 22 (frühere Bedienhilfe) versteckt; Zeilen 21–23 ein Codeblock | Eingabemodul aus der Runtime verschoben, +284 Bytes frei |
| Restaurierungspuffer in die Stackseite (gemessene Stacktiefe 12 Bytes) | +54 Bytes, RUNTIME_LIMIT = $1800 |
| Gepackte Bahnen (Format 2) + decode_course, aktuelle Bahn in $0100 | Testbahn 36 statt 121 Bytes (Segmente + Füllkanten); Decoder ca. 270 Bytes |
| Füllkanten aus Segmenten abgeleitet | keine gespeicherten Füllkanten mehr |
| Abprall ohne Wurzel/Division (siehe unten) | normalize_velocity, sqrt_speed, normalize_component entfallen, −491 Bytes |

Laufzeit, gemessen an Winkel 17 (py65-Physikzyklen) bzw. VICE-Ticks:

| Schritt | Physik | VICE schlechtester Frame |
|---|---:|---:|
| Ausgangslage | 23672 | 38811 |
| Bit-Suche: CIRCLE_OUT ist exakt, Nachprüfung circle_entry entfällt | 22576 | 37673 |
| Teilprodukt im Akku (multiply_fraction), Broadphase-Grenzen vorberechnet | 21340 | |
| multiply_signed in zwei Bytedurchläufen | 20760 | |
| sqrt_speed: 2 statt 10 Vorab-Shifts, 24- statt 32-Bit (−25 Bytes) | 20093 | 34841 |
| Ballzeichner: eine Adresse, zwei vorgeschobene Masken; save_dynamic_byte mit Y-Offset; kürzere Restaurierung | Zeichnen 1687→1222, Restaurieren 414→305 | |
| Entrollte Delta-Halbierung, Kreuzterm von square_small im Akku | 19906 | 33210 |

Bis hier waren alle Ballzustände bitgenau unverändert. Verworfen: Vorab-
Ablehnung in square_circle über das High-Byte (langsamer, 20093→20579).

Der VICE-Test maß jede Ecke nur bei einem Winkel. Ein py65-Sweep über alle
128 Richtungen an den acht Startpunkten fand teurere Winkel (100, 102, 12);
diese sind seitdem Teil von `make smoke`. Mit ihnen lag der schlechteste
Frame zunächst bei 35876 Ticks.

Mit Nutzerfreigabe weicht die Physik seitdem ab (Nutzertest in VICE:
„fühlt sich sehr natürlich an“, bleibt vorerst so):

| Schritt | VICE schlechtester Frame |
|---|---:|
| reflect_unit: UNIT spiegeln, Verlust auf SPEED; exakte Achsen-/45°-Pfade; Lochfang über SPEED | 31429 (nur alte Winkel) |
| Stärkebalken inkrementell (HUD 4642→1194 Zyklen) | 29190 (alte Winkel) / 35876 (mit Sweep-Winkeln) |
| Kreis-Bitsuche bis 1/32 Frame | 33472 |
| start_shot ohne doppelte VELOCITY-Berechnung | 32692 |
| multiply_fraction zweifach entrollt (+10 Bytes) | 31996 |
| Kreis-Bitsuche bis 1/16 Frame (Abstand ≤ 1/4 px) | 30173 |

Abprallmodell: u' = u − 2(u·n)n; SPEED −= SPEED·d²·31/512 + SPEED/128 + 1
mit d = u·n. Die Kontaktreibung deckt Rundungsgewinne von bis zu 0,44 % bei
streifenden Treffern ab. Eckennormale n = Q/2 − Q/256 (|n| ≤ 1). Achsen-
und 45°-Banden spiegeln UNIT und VELOCITY exakt; der Rest des Frames läuft
dort mit der alten Geschwindigkeit, ab dem nächsten Schritt gilt
VELOCITY = SPEED·UNIT. corner-replays.json wurde neu aufgezeichnet.

Messverfahren: tools/profile_sweep.py (inklusive/exklusive Zyklen je
Routine) und make smoke. Der 128-Winkel-Sweep und das Label-Histogramm
waren Wegwerfskripte auf Basis von profile_sweep.profile_call. Ein Zyklus
entspricht nicht festen Ticks: Arbeit im sichtbaren Bildbereich kostet
etwa doppelt, daher immer in VICE nachmessen.
Ergebnis: Runtime 4979 Bytes, 653 frei; schlechtester Frame 30173/32000.

## Rahmen, Schrägen und grünes Schachbrett (2026-10-05)

Nach mehreren Nutzer-Iterationen (8-px-Zellrahmen, 4 px und 3 px per
Pixel-Ausdehnung) gilt: gerade Kanten 6 px (≈ 8/√2), Schrägen glatt bis zur
Zellkante. Rahmen schmaler als eine Zelle erzeugen an 45°-Schrägen
zwangsläufig Stufen, weil die Grau/Schwarz-Zellen der inneren Schräge keine
dritte Farbe (Grün) aufnehmen können; das wurde mit Vorschaubildern geklärt.

draw_course (versteckte Zeilen): Die Spielfläche startet leer, die Even/Odd-
Füllung setzt die Flächenpixel. classify_course_cells teilt die Zellen der
Zeilen 1–20 aus OR/AND ihrer Bytes in ganze Fläche, innere Schräge und fest
ein (Klassen vorübergehend in der Farbmatrix, Anzeige aus).
shape_course_cells geht die Zellen einmal durch: Flächen- und Schrägzellen
werden invertiert (Fläche frei, fester Teil schwarz). Eine Schrägzelle
kopiert vorher ihr Flächenmuster in die feste Nachbarzelle zur festen Seite,
waagerecht und senkrecht: die glatte äußere Schräge. Erkannt wird die feste
Seite an einem freien rechten Pixel der Mittelzeile bzw. mittleren Pixel der
obersten Zeile. Jede Kopie wird auf der von der Fläche abgewandten Seite auf
FRAME_WIDTH gekappt (senkrecht in Zeilen, waagerecht in Spalten) und per OR
eingetragen; in mittleren Schrägzellen ergänzen sich beide Kopien zum vollen
Dreieck, an den Enden schließt die Schräge bündig an die gerade Kante an.
Übrige feste Zellen bekommen für jede ganze Flächenzelle in
der 8er-Nachbarschaft ein Band von FRAME_WIDTH = 6 Pixeln auf dieser Seite
(Tabellen für Zeilenbereich und Spaltenmaske), Ecken also rechtwinklig.
Attribute aus Klasse × Schachbrettparität: Fläche $61 mit schwarzer Tinte,
übrige Spielfeldzellen Schwarz auf Grün $35/$45, Zeilen 0 und 21–23 Grün
auf Grün. Loch: gefüllte 7-px-Scheibe (draw_cup, Runtime). Ball mit
Zeilenformen $70, $f8, $b8 (Glanzpunkt).

Aufbau eines Lochs (py65): ≈1,03 Mio. Zyklen, davon die Füllung ≈0,49 Mio.
tests/course_reference.py modelliert Bitmap und Attribute unabhängig und
prüft Testbahn, Schrägen in allen vier Richtungen, einspringende Schrägen und
den VICE-Smoke-Test. Bahn-Decoder wieder in der Runtime. Runtime 5264 Bytes,
368 frei; versteckte Zeilen 876/960. VICE: schlechtester Frame 30473/32000.
