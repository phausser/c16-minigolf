# C16 Minigolf — Spezifikation

## Ziel und verbindlicher Rahmen

Ein technisch anspruchsvolles Minigolfspiel für den unveränderten Commodore 16 mit 16 KB RAM. 18 handgestaltete Löcher, reine 2D-Draufsicht, geometrische Bahnen mit breiten Flächen, schmalen Wegen und bewusst spielbaren Ecken. Präzise Richtung und Schlagstärke, nachvollziehbare Ballbewegung und kleine humorvolle Reaktionen machen den Reiz aus.

Planungsannahmen: PAL als erstes Ziel, ein Spieler, Tastatur als vollständige Grundsteuerung, optional ein C16-kompatibler Joystick. Alle 18 Löcher liegen im geladenen Programm; während einer Runde wird nichts nachgeladen. Auslieferung als PRG, zusätzlich ein D64 mit demselben Programm. Keine Speichererweiterung erforderlich. NTSC ist ein späteres Kompatibilitätsziel mit derselben Simulationszeit, aber eigener Laufzeitprüfung.

„Kein Multicolor“ bedeutet TED Standard-Hi-Res mit einem Bit pro Pixel und zwei Farben pro 8×8-Zelle. Die Bahn nutzt schwarze Vordergrundpixel und mittelgrauen Hintergrund; Schattenzellen verwenden dunkelgrauen Hintergrund. Die Pixelauflösung bleibt 320×200.

## Darstellung und Atmosphäre

- TED Standard-Hi-Res-Bitmap, 320 × 200 Pixel, fester Bildschirm ohne Scrollen.
- Spielfeldbereich: x = 8…311, y = 8…167. Statusbereich: y = 176…199; dazwischen Abstand.
- Spielbare Flächen mittelgrau, nichtspielbare Flächen und Hindernisse schwarz. Ball, Zielmarke und Lochring schwarz auf Grau; HUD weiß auf Schwarz.
- Ball: kompakte, symmetrische 5 × 5-Pixel-Marke, physikalischer Radius 2 Pixel. Loch: klar erkennbarer Ring mit dunklem Zentrum.
- Die Grenze zwischen Grau und Schwarz entspricht der physikalischen Kollisionskante.
- Laufrichtung vor dem Schlag als kurze gestrichelte Linie und Richtungsspitze; keine vollständige Flugbahnvorhersage.
- HUD: Loch 01/18, Par, Schläge, Stärke als Balken, Gesamtstand relativ zu Par. Spieltext ohne Umlaute für einen kleinen Zeichensatz.
- Dunkelgrauer, am 8×8-Zellraster ausgerichteter Schatten an oberen und linken Innenkanten. Er verändert keine Kollisionsdaten. Keine Perspektive und keine Hardware-Sprites.

Statische Bahn einmal zeichnen. Ball, Zielmarke und kleine Effekte als Softwaregrafik mit gesichertem Hintergrund aktualisieren. Überlappende Elemente werden in fester Reihenfolge restauriert und neu gezeichnet. Keine vollständige Bitmap-Kopie im RAM, kein Vollbild-Neuzeichnen pro Frame und kein flackerndes XOR als Standardlösung.

## Spielablauf und Eingabe

Titel → Start → Lochvorstellung → Zielen → Stärke einstellen → Schlag → Ball rollt → nächster Schlag oder Einlochen → Lochbilanz → nächstes Loch → Endwertung.

Tastaturbelegung als Ausgangspunkt: A/D drehen, W/S Stärke ändern, SPACE schlagen bzw. bestätigen, RETURN zwischen Richtung und Stärke wechseln, P pausieren. Tastenerfassung verwendet einen eigenen, entprellten Scan. Die endgültige Matrixbelegung wird am Gerät geprüft. Joystick: links/rechts drehen, hoch/runter Stärke, Feuer schlagen; Taste P bleibt verfügbar.

- 128 Richtungen über den Vollkreis, Startausrichtung zum ersten sinnvollen Bahnabschnitt.
- 32 Stärkestufen; gewählte Stärke bleibt zwischen Schlägen bestehen.
- Kurzes Drücken bewegt einen Schritt; Halten wiederholt nach einer Verzögerung. Keine automatisch pendelnde Stärkeanzeige.
- Ein Schlag ist nur bei ruhendem Ball möglich. Nach einem Schlag wird die Richtung-/Stärkeanzeige ausgeblendet.
- Richtung und Stärke bleiben vollständig frei wählbar; empfohlenes Par verlangt kein pixelgenaues Rätsel.
- Nach Einlochen wird das Ergebnis kurz angezeigt; Bestätigung führt weiter.
- Nach 12 Schlägen ohne Einlochen wird das Loch mit 13 Schlägen gewertet und als abgebrochen markiert. Kein endloser Stillstand.
- Neustart der ganzen Runde nur über eine eigene bestätigte Menüaktion.

18-Loch-Runde und Trainingsmodus mit frei wählbarem Loch. Die Runde speichert 18 Ergebnisse im RAM; Endbild zeigt alle Schläge, Gesamtsumme und Abweichung vom Gesamtpar. Kein persistenter Highscore im ersten Release.

## Physik: präzise, konsistent, testbar

„Perfekt“ heißt robuste, deterministische Minigolfphysik innerhalb der festgelegten 2D-Regeln. Es ist keine Simulation von Grasfasern oder einer dreidimensionalen Kugel. Kein Zufall beeinflusst den Ball.

### Zeit und Zahlenformat

Fester Simulationsschritt von 1/50 Sekunde. PAL aktualisiert einmal je Bild. X-Position als vorzeichenloser 24-Bit-Wert Q16.8, Y-Position als vorzeichenloser 16-Bit-Wert Q8.8; Geschwindigkeiten als vorzeichenbehaftete 16-Bit-Werte mit acht Nachkommabits. Zwischenrechnungen verwenden ausreichende Breite, insbesondere für Quadrate und Skalarprodukte. Differenzen werden vor der Rechnung verbreitert; x > 255 darf nicht überlaufen.

Verbindlich: pixelgenaue Bewegung. Der Ball kann auf jeder einzelnen Pixelposition dargestellt werden; seine Bewegung wird nicht auf Zeichen-, Zell- oder Zweipixelraster eingerastet. Die Physik behält Subpixel-Präzision, nur die Darstellung rundet nach einer festen Regel auf ganze Pixel. Das Zweipixelraster der kompakten Bahndaten beschränkt ausschließlich die Bahnkoordinaten. Kollisionsprüfungen verfolgen den vollständigen Weg durch einen kontinuierlichen geometrischen Sweep; schnelle Schläge dürfen zwischen zwei dargestellten Bildern mehrere Pixel zurücklegen.

128 normierte Richtungsvektoren über Viertelwellen-Tabelle und Symmetrie. 32 monotone Startgeschwindigkeiten; vorläufig maximal 4 Pixel pro Simulationsschritt. Geschwindigkeit, Rollreibung und Lochfangschwelle werden gemeinsam kalibriert und als feste Konstanten dokumentiert.

### Bewegung und Reibung

Auf normalem Boden wirkt eine konstante Bremsbeschleunigung entgegen der Bewegungsrichtung. Die Implementierung darf eine kleine Integer-Näherung für den Betrag benutzen, muss aber die Richtungsabhängigkeit nach den untenstehenden Kriterien begrenzen. Keine unabhängige, gleich große Bremsung beider Achsen: das würde Diagonalschläge benachteiligen.

Der Ball wird unterhalb einer klaren Geschwindigkeitsgrenze exakt stillgesetzt. Keine dauerhaft kriechende Kugel. Sand erhöht die Bremsung; Eis vermindert sie. Materialwechsel wird an der Ballmitte erkannt und gilt ab dem nächsten Simulationsschritt. Alle Materialwerte sind konstant, sichtbar und reproduzierbar.

### Kollisionen

Kollision basiert auf geometrischen Daten, niemals auf Bildschirm-Pixeln. Der Ball ist ein Kreis. Bahnen bestehen aus geschlossenen Konturen und gegebenenfalls geschlossenen Hindernissen. Erste Version unterstützt waagerechte und senkrechte Segmente sowie 45°-Segmente; beliebige Winkel sind nicht erforderlich.

Ein kontinuierlicher Sweep prüft den vollständigen Frame-Weg von höchstens 4 Pixeln. Er bestimmt die früheste Berührung entlang des Bewegungsweges: Kreis gegen Segment einschließlich Endpunkt. Zeit des Kontakts, verbleibende Bewegung und Rundungsregeln sind Teil der Implementierung, damit der Ball keine Wand durchquert.

Reflexion am Kontakt: v' = v − (1 + e) · (v · n) · n. Einheitliche, leicht verlustbehaftete Bande mit vorläufig e = 15/16; kein künstlicher seitlicher Schub. Kontakt nur auflösen, wenn die Geschwindigkeit in die Fläche zeigt. Segmentenden werden als Kreis-Punkt-Kontakt behandelt; bloßes Spiegeln beider Achsen ist dort unzulässig.

Gleichzeitige Kontakte erhalten eine stabile Reihenfolge und eine gemeinsame Auflösung ohne Energiegewinn. Ein kleines fest definiertes Abstandsepsilon verhindert Wiederkollision durch Rundungsreste. Maximal vier Kontaktauflösungen pro Simulationsschritt. Bei ausgeschöpftem Limit wird die Restbewegung verworfen, kein Durchtritt erlaubt; dieser Fall muss im Test sichtbar werden und darf in freigegebenen Bahnen nicht auftreten.

### Einlochen

Lochzentrum und Fangradius sind eigene Daten. Vorläufiger Fangradius der Ballmitte: 3 Pixel, maximale Fanggeschwindigkeit: 0,75 Pixel pro Simulationsschritt. Der zurückgelegte Weg wird geprüft, nicht nur die Position am Bildende. Schnelle Bälle dürfen über das Loch laufen. Ein langsamer Treffer wird zum Zentrum gezogen, Eingabe gesperrt und mit kurzer Animation abgeschlossen. Lochfang darf keine Wand umgehen.

### Abnahmekriterien der Physik

- Dieselbe Eingabefolge liefert bitidentische Positionen, Geschwindigkeiten und Ergebnisse.
- Horizontale, vertikale und diagonale Schläge gleicher Stärke unterscheiden sich auf freier Fläche in Reichweite um höchstens 2 %; Richtungsabweichung höchstens 1°.
- Senkrechte und 45°-Banden reflektieren bei isoliertem Kontakt mit höchstens 1° Winkelfehler; Geschwindigkeit steigt ohne ausdrücklich ausgewiesenen Effekt nicht an.
- Kein Tunneling bei Höchstgeschwindigkeit, kein Steckenbleiben bei normalen Eckkontakten, kein sichtbares Zittern nach Stillstand.
- Legale Engstellen sind mindestens 10 Pixel breit, also mit deutlicher Reserve zum Balldurchmesser.
- Lochfang funktioniert auch dann, wenn der Ball in einem Schritt beide Seiten des Fangbereichs passiert.
- Physiktests decken Segmentmitte, Segmentende, Innen-/Außenecken, doppelte Kontakte, Materialgrenzen und Lochfang ab.

## 18 Löcher

Dies sind verbindliche Designbriefs; exakte Koordinaten entstehen im Bahneditor und werden erst nach Geometrie- und Spieltests eingefroren. Par ist vorläufig. Alle Bahnen müssen mit den Grundregeln lösbar sein.

| Nr. | Name | Par | Geometrie und Spielidee |
|---|---|---:|---|
| 1 | GERADER GEHT'S NICHT | 2 | Breites Rechteck, gerader Weg; Stärke und Ausrollen lernen. |
| 2 | RECHTS AB | 2 | Breites L, ein rechtwinkliger Knick; erste Bande. |
| 3 | LINKS AUCH | 2 | Gespiegeltes L mit engerem Schlussstück. |
| 4 | DER FLASCHENHALS | 3 | Große Startkammer, 12-Pixel-Durchgang, große Zielkammer. |
| 5 | ZWEIMAL UM DIE ECKE | 3 | Z-Bahn, zwei Knicke und sichere Zwischenpositionen. |
| 6 | DIE ABKUERZUNG | 3 | U-Bahn um eine dicke Innenwand; gezielter Bandenschlag. |
| 7 | DICK UND DUENN | 3 | Drei breite Räume mit versetzten schmalen Verbindungen. |
| 8 | BILLARDPAUSE | 2 | Breite Kammer mit 45°-Bande, Loch hinter einer Trennwand. |
| 9 | RAUTE MIT LAUNE | 3 | Rautenförmige Außenkontur, zentraler eckiger Block. |
| 10 | SCHLANGENLINIE | 4 | Rechtwinklige S-Bahn; mehrere kontrollierte Teilschläge. |
| 11 | INSELHUEPFEN OHNE HUEPFEN | 3 | Rechteck mit zwei versetzten rechteckigen Hindernissen. |
| 12 | SAND IM GETRIEBE | 3 | Breite Bahn, Sandfeld vor der letzten Kurve. |
| 13 | GLATTE SACHE | 3 | Eiszone auf gerader Passage, normaler Boden am Loch. |
| 14 | DER TRICHTER | 3 | Breiter Eingang verengt sich über 45°-Wände auf 10 Pixel. |
| 15 | DIE NADEL | 4 | Langer schmaler Weg mit zwei breiten Ruhekammern. |
| 16 | BANDENBANDE | 3 | Versetzte dicke Wände und diagonale Endbande; mehrere Routen. |
| 17 | DAS LABYRINTHCHEN | 4 | Kompaktes rechtwinkliges Labyrinth mit einer fairen Sackgasse. |
| 18 | FEIERABEND | 4 | Finale aus breitem Start, schmalem Knick, Sand und 45°-Zielkammer. |

Vorläufig Gesamtpar: 54. Jede Bahn zeigt Abschlag und Loch gleichzeitig. Keine unsichtbaren Kanten, zufälligen Hindernisse oder beweglichen Türen. Mindestens eine robuste Route, auf schweren Löchern zusätzlich eine riskantere, kürzere Route. Kein Loch darf nur mit einer einzigen Richtung-/Stärkekombination lösbar sein.

## Lustige Nebeneffekte

Humor bleibt kurz und stört das Zielen nicht. Ereignisse: harter Bandentreffer → kurzes „TOK!“; mehrere Bandenkontakte → „BANDE MIT BANDE“; extrem kurzer Schlag → „WAR DAS SCHON ALLES?“; Hole-in-one → Sternchen und kleine TED-Fanfare; Einlochen nach vielen Schlägen → „ENDLICH FEIERABEND“.

Texte erscheinen im HUD, Partikel nur nach Stillstand bzw. Einlochen. Höchstens vier kleine Partikel, maximal etwa eine halbe Sekunde. Auslöser haben Cooldown und feste Priorität. Effekte ändern weder Ballzustand noch Physikzeit. Keine Bildschirmerschütterung. Ton abschaltbar; keine dauernde Musik während des Zielens. Erst nach erfolgreicher Physikabnahme als optionale Erweiterung denkbar: deutlich markierte Spezialbanden. Sie gehören nicht zum Grundumfang.

## Architektur und Daten

6502-kompatibler Assembler: verbindlich ACME (6502-Modus), Build über Make; Python-Werkzeuge für Bahnprüfung, Datenexport und Testreferenz. BASIC dient höchstens als SYS-Startstub. Spielcode nutzt eigene Hauptschleife, TED-Synchronisation, Eingabe und Sound; ROM-Routinen sind während des Spiels keine Abhängigkeit.

Module: Start/Hardware, Frame-Takt, Eingabe, Zustand/Score, Festkomma, Bewegung/Kollision, Bahn-Decoder, Bitmap-Zeichner, HUD, Sound/Effekte. Zustand und Darstellung sind getrennt, damit der echte Assembler-Physikkern automatisiert geprüft werden kann.

Bahnquelle in menschenlesbarem Datenformat: Name, Par, Abschlag, Loch, Außenkontur, Hindernisse und Materialflächen. Export als kompakte Byte-Ströme, vorzugsweise Koordinaten auf 2-Pixel-Raster. Erst entpacken, dann Rendern und Kollisionsgeometrie aus derselben Quelle erzeugen. Keine 18 gespeicherten Bitmaps. Grenze pro Bahn: maximal 32 Kollisionssegmente insgesamt, einschließlich Hindernissen, und höchstens zwei Materialflächen. Generator prüft Konturen, Überschneidungen, Ballfreiheit, Abschlag/Loch und Engstellen.

### Vorläufiger RAM-Vertrag

| Bereich | Bytes | Verwendung |
|---|---:|---|
| $0000–$01FF | 512 | Zero Page und Hardwarestack; reservierte CPU-Port-Adressen respektieren. |
| $0200–$17FF | 5632 | Startstub, Code, Tabellen, alle gepackten Bahnen, Zustand und Scratch. |
| $1800–$1FFF | 2048 | TED-Attribute, feste Farb-/Luminanzwerte. |
| $2000–$3FFF | 8192 | Bitmap; 8000 sichtbare Bytes, Rest zunächst reserviert. |

Arbeitsbudget innerhalb der 5632 Bytes: 3500 Code/Stub, 1400 gepackte Bahnen/Texte, 300 Tabellen, 432 Zustand/entpackte aktuelle Bahn/Scratch. Das ist eine harte Arbeitshypothese, keine bereits bewiesene Passform. ACME-Symbole, Assemblierzeit-Grenzprüfungen und Größenbericht müssen jeden Bereich nachweisen. Kein Heap; Scratch wird zwischen ausschließlich nacheinander aktiven Routinen geteilt. Das Programm darf beim Laden den BASIC-Arbeitsbereich überschreiben, kehrt anschließend nicht zu BASIC zurück.

Hi-Res benötigt einen großen Anteil der 16 KB. Deshalb wird vor der Produktion aller Bahnen ein vollständiger Vertikalschnitt mit echtem Physikkern und Größenmessung gebaut. Falls das Budget scheitert: Daten und Text komprimieren, Routinen vereinfachen und Effekte kürzen. Keine stille Umstellung auf 64 KB, Multicolor oder schwächere Eckphysik. Ein notwendiger Architekturwechsel wird ausdrücklich neu entschieden.

### Zeitbudget

Ziel: flüssige 50-Hz-Darstellung unter PAL mit aktiver Anzeige. Nicht mit dauerhaft maximalem CPU-Takt rechnen: TED teilt die Speicherzugriffe. Kandidaten für Kollision über Segment-Bounding-Boxes filtern. Begrenzte Segmentzahl, Geschwindigkeit und Kontakte machen die schlechteste Last messbar. Rastermarkierungen bzw. Emulator-Zyklusmessung erfassen Physik, Rendern und Restbudget. Sound und Effekte haben niedrige Priorität; kein Überspringen notwendiger Physikschritte, um Effekte zu retten.

## Qualität und Release

Freigabe erst bei allen 18 geprüften Bahnen, vollständiger Runde, korrekter Wertung und eingehaltenen Speichergrenzen. Hauptprüfung in VICE xplus4 mit tatsächlich eingestelltem C16/16-KB-PAL-Modell; Plus/4-64-KB-Defaults reichen nicht. Danach reale C16-Hardware für Bild, Eingabe, Tempo, Ton und Laden prüfen; fehlende Hardwareprüfung wird im Release dokumentiert.

Tests: deterministische Wiedergaben im tatsächlichen 6502-Kern, unabhängige hochpräzise Geometrie-Referenz, Grenzfälle und Worst-Case-Framezeiten. Host-Referenz allein bestätigt nicht das Zielprogramm. Bahnvalidator und Build brechen bei ungültiger Geometrie oder Speicherüberschreitung ab. Tuning prüft alle 32 Stärken und 128 Richtungen in repräsentativen Szenarien.

## Technische Quellen und offene Nachweise

Primärquelle: [Commodore TED 7360 Datenblatt](https://www.karlstechnology.com/commodore/TED7360-datasheet.pdf), insbesondere Standard-Hi-Res, Bitmap-Organisation, Register und Timing. Der Hi-Res-Modus hat 320 × 200 Pixel und einen 8-KB-ausgerichteten Bitmap-Bereich. Registerwerte, Attributadressierung, RAM-Ladeverhalten und PAL/NTSC-Erkennung sind vor Implementierung am Datenblatt und im Emulator zu verifizieren. Gemessene Register- und Laufzeitnachweise stehen in docs/hardware.md; offene Freigaben sind in TODO.md ausgewiesen.

Keine Rückfrage ist zum Start nötig. Die oben genannten Annahmen legen einen konkreten ersten Release fest; Steuerung und physikalische Konstanten werden nach dem spielbaren Prototyp fein abgestimmt.

## Stand des Physikprototyps (2026-10-04)

ACME-Kern mit 128 Viertelwellen-Richtungen, 32 Startgeschwindigkeiten
(Stärke × 1/8 Pixel pro Schritt), radialer Bremsung 1/64 Pixel pro Schritt
und exaktem Stillstand. Die Darstellung rundet Subpixelwerte zur nächsten
Pixelmitte, bei genau einer Hälfte nach oben. Konturen nutzen fünf Bytes
pro Segment: vier Halb-Pixelkoordinaten und einen einwärts gerichteten
Normalenindex in Bits 0–2. Bit 7 markiert einen von seinen angrenzenden
Wänden verdeckten Endpunkt; dessen Kreisprüfung kann entfallen. Replays
mit und ohne dieses Flag müssen identische Ballzustände liefern. Wandstriche liegen außerhalb der geometrischen Innenkante.

Kontaktzeiten haben acht Nachkommabits; bei maximaler Geschwindigkeit
entspricht eine Zeiteinheit höchstens 1/64 Pixel Weg. Kreis-Endpunkte
verwenden eine Prüfung des nächsten Wegpunkts und anschließende Suche der Kontaktzeitbits
mit exakten 24-Bit-Positionen (Q8.16), damit auch Streifkontakte mit beiden Wegenden außerhalb
erkannt werden. Geradensegment-Projektionen rechnen mit 1/64-Pixel-Präzision.
Gleichzeitige Kontakte werden nach stabiler Segmentreihenfolge aufgelöst.
Die Kontaktgrenze zählt Überschreitungen und verwirft die Restbewegung.

Der Prototyp erfüllt noch nicht sämtliche Abnahmekriterien: offene
Kontaktgrenzfälle, 50-Hz-Worst-Case und Platz für alle 18 Bahnen stehen in
TODO.md. Der umfangreiche Physikkern benötigt derzeit 5480 Runtime-Bytes;
98 bleiben im Hauptbereich frei. Exakte Speicher- und Laufzeitmessungen
stehen in docs/hardware.md. Das 50-Hz-Ziel bleibt bestehen.

### Rundung, Optimierungen und kompakter Export

Geradenkontakte akzeptieren ein negatives unnormalisiertes Wand-Gap von
höchstens zwei Q8.8-Einheiten (2/256 Pixel auf Achsen) als Kontaktzeit null.
Größere negative Abstände werden nicht durch diese Rundungstoleranz
verdeckt. Bei Kreis-Sweeps bleibt der letzte äußere Wegpunkt maßgeblich.

Für exakt diagonale Geschwindigkeiten wird der Betrag mit 362/256 ≈ √2
berechnet. Die Abweichung zur exakten ganzzahligen Wurzel beträgt im
legalen Geschwindigkeitsbereich höchstens eine Q8.8-Einheit nach unten;
alle Vorzeichenkombinationen sind geprüft. Diagonalreflexion verwendet
31/32·(vx±vy), entsprechend e=15/16. Der spezielle radiale Diagonalfall
bestimmt die erste innere ganzzahlige Kreisposition direkt und liefert
denselben letzten äußeren Kontaktzeitpunkt wie die diskrete Geometrie.
Alle anderen Endpunkte verwenden weiterhin den allgemeinen Sweep.

Die Ballform bleibt 21 gesetzte Pixel groß. Der Renderer erzeugt sie über
fünf Zeilenmasken und restauriert höchstens zehn Bitmap-Bytes; mit acht
Zielpunkten benötigt er höchstens 18 Sicherungsplätze.

Der neue Host-Export Version 1 speichert Start/Loch auf Zweipixelraster,
Konturanzahl sowie pro Kontur Startpunkt, Run-Anzahl und Richtungs-/
Längenbytes. Drei Bits kodieren eine von acht Richtungen, fünf Bits eine
Länge von 1–32 Rastereinheiten (0 bedeutet 32). Lange Kanten werden in
Runs geteilt und beim Dekodieren wieder zusammengefügt. Geometrie und
Start/Loch werden verlustfrei zurückgelesen; Name, Par und Materialien
sind noch nicht Teil dieses Formats. Der ACME-Kern verwendet derzeit
weiter die expandierten Fünf-Byte-Segmente.

`make budget` schreibt build/course-budget.json. Der echte Testexport
benötigt 39 Bytes; 18 gleich große Bahnen plus 36-Byte-Verzeichnis würden
738 Bytes benötigen. Das ist eine ausdrückliche Hochrechnungsannahme,
kein Nachweis über 18 fertige Löcher. Gegenwärtig fehlen dafür bereits
731 Runtime-Bytes, ohne Decoder, Metadaten und weitere Spielmodule.
