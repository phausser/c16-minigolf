# C16 Minigolf — Spezifikation

## Ziel und verbindlicher Rahmen

Ein technisch anspruchsvolles Minigolfspiel für den unveränderten Commodore 16 mit 16 KB RAM. 18 handgestaltete Löcher, reine 2D-Draufsicht, geometrische Bahnen mit breiten Flächen, schmalen Wegen und bewusst spielbaren Ecken. Präzise Richtung und Schlagstärke, nachvollziehbare Ballbewegung und kleine humorvolle Reaktionen machen den Reiz aus.

Planungsannahmen: PAL als erstes Ziel, ein Spieler, C16-kompatibler Joystick an Port 1 als Grundsteuerung, P auf der Tastatur zum Pausieren. Alle 18 Löcher liegen im geladenen Programm; während einer Runde wird nichts nachgeladen. Auslieferung als PRG, zusätzlich ein D64 mit demselben Programm. Keine Speichererweiterung erforderlich. NTSC ist ein späteres Kompatibilitätsziel mit derselben Simulationszeit, aber eigener Laufzeitprüfung.

„Kein Multicolor“ bedeutet TED Standard-Hi-Res mit einem Bit pro Pixel und zwei Farben pro 8×8-Zelle. Weiße Spielflächen sind die Hintergrundfarbe, Ball und Markierungen die schwarze Vordergrundfarbe. Rahmen und grüne Rasenstreifen entstehen allein über die Zellattribute. Die Pixelauflösung bleibt 320×200.

## Darstellung und Atmosphäre

- TED-Textmodus, 40 × 25 Zellen zu 8 × 8 Pixeln (320 × 200, kein Multicolor), Zeichensatz mit 128 Zeichen im RAM, fester Bildschirm ohne Scrollen. Globaler Hintergrund schwarz, je Zelle eine Vordergrundfarbe: jede Zelle zeigt höchstens eine Farbe plus Schwarz. Neue Bahnelemente müssen diese Regel einhalten. Entschieden am 2026-10-05 statt Hi-Res-Bitmap, um rund 5,5 KB RAM freizumachen; das Bild ist pixelgleich zum früheren Bitmap-Stand.
- Spielfeldbereich: x = 8…311, y = 8…167. Statusbereich: y = 176…199; dazwischen Abstand.
- Spielbare Flächen glatt hellgrau (Luminanz 6). Schwarzer Rahmen: an geraden Kanten 6 Pixel (optisch gleich stark wie die Schräge, 8/√2 ≈ 5,7) (die von der Fläche am weitesten entfernte Pixelzeile bzw. -spalte der Rahmenzelle bleibt grün), Außenecken rechtwinklig. An 45°-Schrägen liegt die äußere Kante genau eine Zelle weiter außen und ist glatt (8 Pixel waagerecht, ≈5,7 quer); so hat jede Zelle höchstens zwei Farben. Hindernisse erhalten dieselben Bänder; schmale Hindernisse behalten einen grünen Spalt. Alles übrige, auch die Zeilen 0 und 21–23 (volles Zeichen), zeigt ein grünes Schachbrett aus Feldern von 2×2 Zellen, hellgrün (Farbton 15, Luminanz 4/3), benachbarte Felder eine Luminanzstufe verschieden. Wasserflächen sind ganze Bodenzellen ohne Rahmen im hellblauen Schachbrett (Farbton 13, Luminanz 2/3; Ball und Zielmarke löschen Pixel und erscheinen schwarz). Das Wasser bewegt sich (src/water.asm): jede Zelle durchläuft kein, kein, 1 px, 2 px, 1 px Schatten an linker und oberer Kante, die Luminanz sinkt dabei um 0, 0, 1, 2, 1; Phase (Zeile + Spalte) mod 5, ein Schritt alle 8 Frames, das Muster läuft diagonal nach rechts unten; Wände neben Wasser behalten ihren Rahmen. Ball und Zielmarke schwarz; das Loch ist rund, 7 Pixel Durchmesser, mit schwarzem Rand und Schatten innen oben links; unten rechts bleibt die beleuchtete Innenwand grau (Muster `cup_rows` in src/render.asm, Testreferenz in tests/course_reference.py). HUD hellgrau (Luminanz 6) auf Schwarz.
- Ball: kompakte 5 × 5-Pixel-Marke mit einem freien Glanzpunkt oben links, physikalischer Radius 2 Pixel. Loch: 7 Pixel Durchmesser, Schatten innen oben links.
- Die Grenze zwischen Grau und Schwarz entspricht der physikalischen Kollisionskante. Alle Eckpunkte liegen auf dem 8×8-Zellraster; gerade Kanten folgen Zellgrenzen, 45°-Kanten schneiden Zellen genau diagonal.
- Laufrichtung vor dem Schlag als kurze gepunktete Linie: sieben Punkte im Abstand von 4 Pixeln im Fenster 8–35 Pixel vor der Ballmitte. Die Punkte wandern alle vier Bilder um einen Pixel nach außen; der äußerste verschwindet und erscheint innen wieder. Keine vollständige Flugbahnvorhersage. Bei Lochbeginn zeigt die Richtung entlang der Bahn (`aim` der Bahndaten), nach jedem Stillstand auf das Loch (atan2 der gerundeten Pixelpositionen, auf 128 Richtungen gerundet).
- HUD (Zeile 24, unter dem Rasen) in eigener 5 Pixel hoher Schrift (Glyphenzeilen 1–5 wie der Ladebalken; Ziffern 3×5, Schrägstrich, Fähnchen, Schläger; src/render.asm `hud_font`), als Pixelstreifen über die Zellen 0–1 und 35–39: links Fähnchen und Bahnnummer, rechtsbündig Schläger und „Schläge/Par“ (Schläge auf dieser Bahn, aktualisiert beim Stillstand), je 1 Pixel Rand zum Bildschirmrand; mittig (Spalten 15–24) ein Ladebalken über zehn Zellen: ein Rahmen 80×5 Pixel (Glyphenzeilen 1–5, 1 Pixel Umriss, 3 Pixel innen) mit Skalenstrichen innen bei 25, 50 und 75 % (Pixel 20, 40, 60); beim Aufladen werden die ersten 5·Stärke/2 Pixel (80 bei voller Stärke) über alle 5 Zeilen gefüllt. Keine Anleitung oder Statuswörter; das Spiel zeigt keinen Text.
- Gleichmäßig gefärbte Flächen ohne Schatten oder Pixelmuster; das Schachbrett entsteht zellweise über Farben. Keine Perspektive und keine Hardware-Sprites.

Statische Bahn einmal je Bahnwechsel bei abgeschaltetem Bild zeichnen: dreizeiliger Pixelpuffer, jede fertige Zelle wird als Zeichen abgelegt (höchstens 64 verschiedene Bahnzeichen; bei Überlauf roter Rahmen, der Test bricht ab). Ball und Zielpunkte belegen bis zu zwölf dynamische Zeichen: das statische Zeichen der Zelle wird kopiert und die Pixel gelöscht; Wiederherstellen setzt die statischen Zeichencodes zurück. Kein Vollbild-Neuzeichnen pro Frame und kein flackerndes XOR als Standardlösung.

## Spielablauf und Eingabe

Titel → Start → Lochvorstellung → Zielen → Stärke einstellen → Schlag → Ball rollt → nächster Schlag oder Einlochen → Lochbilanz → nächstes Loch → Endwertung.

Joystick Port 1: links/rechts drehen, Feuer halten lädt die Schlagstärke,
Feuer loslassen schlägt. P pausiert. A/D/W/S/SPACE steuern das Spiel nicht mehr.
Joystick und Pause werden getrennt gelesen und über zwei gleiche Samples
entprellt. Nach Pause/Rollen/Neustart muss Feuer erst losgelassen werden;
keine ungewollte Aufladung durch eine bereits gehaltene Taste.

- 128 Richtungen über den Vollkreis, Startausrichtung zum ersten sinnvollen Bahnabschnitt.
- 32 Stärkestufen: beim akzeptierten Feuerdruck Start mit 1, danach alle zwei PAL-Frames +1 bis 32 (etwa 1,3 Sekunden). Maximum halten, kein Pendeln und kein automatischer Schlag. Loslassen löst aus und leert die Anzeige; Pause bricht die Aufladung ab.
- Kurzes Drücken bewegt einen Schritt; Halten wiederholt nach einer Verzögerung. Keine automatisch pendelnde Stärkeanzeige.
- Ein Schlag ist nur bei ruhendem Ball möglich. Nach einem Schlag verschwindet die Richtungsmarke; die Stärkeanzeige steht wieder auf 0.
- Richtung und Stärke bleiben vollständig frei wählbar; empfohlenes Par verlangt kein pixelgenaues Rätsel.
- Nach Einlochen verschwindet der Ball, die Schlagzahl rechts zeigt das Ergebnis; Feuer führt zur nächsten Bahn (vorher loslassen).
- Nach 12 Schlägen ohne Einlochen wird das Loch mit 13 Schlägen gewertet: der Ball verschwindet, Schlagzahl 13. Kein endloser Stillstand.
- Nach Bahn 18 zeigt die Statuszeile rechts Schläger und „Gesamtschläge/Gesamtpar“, links nichts; Feuer beginnt eine neue Runde. Weitere Ergebnisbilder entfallen aus Speichergründen.
- Neustart der ganzen Runde nur über diese bestätigte Endanzeige.

18-Loch-Runde; die Runde speichert die Gesamtsumme. Trainingsmodus und Einzelergebnisse nur, falls der Speicher es nach der Bahnabnahme zulässt. Kein persistenter Highscore im ersten Release.

## Physik: präzise, konsistent, testbar

„Perfekt“ heißt robuste, deterministische Minigolfphysik innerhalb der festgelegten 2D-Regeln. Es ist keine Simulation von Grasfasern oder einer dreidimensionalen Kugel. Kein Zufall beeinflusst den Ball.

### Zeit und Zahlenformat

Fester Simulationsschritt von 1/50 Sekunde. PAL aktualisiert einmal je Bild. X-Position als vorzeichenloser 24-Bit-Wert Q16.8, Y-Position als vorzeichenloser 16-Bit-Wert Q8.8; Geschwindigkeiten als vorzeichenbehaftete 16-Bit-Werte mit acht Nachkommabits. Zwischenrechnungen verwenden ausreichende Breite, insbesondere für Quadrate und Skalarprodukte. Differenzen werden vor der Rechnung verbreitert; x > 255 darf nicht überlaufen.

Verbindlich: pixelgenaue Bewegung. Der Ball kann auf jeder einzelnen Pixelposition dargestellt werden; seine Bewegung wird nicht auf Zeichen-, Zell- oder Zweipixelraster eingerastet. Die Physik behält Subpixel-Präzision, nur die Darstellung rundet nach einer festen Regel auf ganze Pixel. Das Raster der kompakten Bahndaten (Eckpunkte 8 Pixel, Abschlag und Loch 2 Pixel) beschränkt ausschließlich die Bahnkoordinaten. Kollisionsprüfungen verfolgen den vollständigen Weg durch einen kontinuierlichen geometrischen Sweep; schnelle Schläge dürfen zwischen zwei dargestellten Bildern mehrere Pixel zurücklegen.

128 normierte Richtungsvektoren über Viertelwellen-Tabelle und Symmetrie. 32 monotone Startgeschwindigkeiten; vorläufig maximal 4 Pixel pro Simulationsschritt. Geschwindigkeit, Rollreibung und Lochfangschwelle werden gemeinsam kalibriert und als feste Konstanten dokumentiert.

### Bewegung und Reibung

Auf normalem Boden wirkt eine konstante Bremsbeschleunigung entgegen der Bewegungsrichtung. Die Implementierung darf eine kleine Integer-Näherung für den Betrag benutzen, muss aber die Richtungsabhängigkeit nach den untenstehenden Kriterien begrenzen. Keine unabhängige, gleich große Bremsung beider Achsen: das würde Diagonalschläge benachteiligen.

Der Ball wird unterhalb einer klaren Geschwindigkeitsgrenze exakt stillgesetzt. Keine dauerhaft kriechende Kugel. Sand erhöht die Bremsung; Eis vermindert sie. Materialwechsel wird an der Ballmitte erkannt und gilt ab dem nächsten Simulationsschritt. Wasser: Endet ein Rollbild mit der Ballmitte in einer Wasserzelle (Hintergrundfarbton der Zelle), kehrt der Ball ans Ufer zurück und bleibt liegen: auf jeder Achse, deren Zellgrenze er in diesem Bild überquert hat, liegen genau 3 freie Pixel zwischen Ballrand und Wasser; die andere Koordinate bleibt die vom Bildbeginn; ein Strafschlag (zählt zum Schlaglimit). Weil der Ball höchstens 4 Pixel je Bild rollt und Wasserflächen ganze Zellen sind, kann er keine Wasserzelle überspringen. Alle Materialwerte sind konstant, sichtbar und reproduzierbar.

### Kollisionen

Kollision basiert auf geometrischen Daten, niemals auf Bildschirm-Pixeln. Der Ball ist ein Kreis. Bahnen bestehen aus geschlossenen Konturen und gegebenenfalls geschlossenen Hindernissen. Erste Version unterstützt waagerechte und senkrechte Segmente sowie 45°-Segmente; beliebige Winkel sind nicht erforderlich.

Ein kontinuierlicher Sweep prüft den vollständigen Frame-Weg von höchstens 4 Pixeln. Er bestimmt die früheste Berührung entlang des Bewegungsweges: Kreis gegen Segment einschließlich Endpunkt. Zeit des Kontakts, verbleibende Bewegung und Rundungsregeln sind Teil der Implementierung, damit der Ball keine Wand durchquert.

Reflexion am Kontakt (Laufzeitmodell seit 2026-10-05): Der Einheitsvektor wird gespiegelt, u' = u − 2 · (u · n) · n; der Banden-Verlust wirkt auf den Betrag: SPEED −= SPEED · (u · n)² · 31/512 + SPEED/128 + 1. Das nähert e = 15/16 auf der Normalkomponente; der kleine Zusatz ist Kontaktreibung und schließt Energiegewinn durch Rundung aus. Achsen- und 45°-Banden spiegeln exakt (Vorzeichen bzw. Komponententausch); Eckennormalen haben |n| ≤ 1. Kein künstlicher seitlicher Schub. Kontakt nur auflösen, wenn die Geschwindigkeit in die Fläche zeigt. Segmentenden werden als Kreis-Punkt-Kontakt behandelt; bloßes Spiegeln beider Achsen ist dort unzulässig.

Gleichzeitige Kontakte erhalten eine stabile Reihenfolge und eine gemeinsame Auflösung ohne Energiegewinn. Ein kleines fest definiertes Abstandsepsilon verhindert Wiederkollision durch Rundungsreste. Maximal vier Kontaktauflösungen pro Simulationsschritt. Bei ausgeschöpftem Limit wird die Restbewegung verworfen, kein Durchtritt erlaubt; dieser Fall muss im Test sichtbar werden und darf in freigegebenen Bahnen nicht auftreten.

### Einlochen

Lochzentrum und Fangradius sind eigene Daten. Vorläufiger Fangradius der Ballmitte: 3 Pixel, maximale Fanggeschwindigkeit: 0,75 Pixel pro Simulationsschritt. Der zurückgelegte Weg wird geprüft, nicht nur die Position am Bildende. Schnelle Bälle dürfen über das Loch laufen. Ein langsamer Treffer wird zum Zentrum gezogen, Eingabe gesperrt und mit kurzer Animation abgeschlossen. Lochfang darf keine Wand umgehen. Lochrand: Überlappt der Ball das Loch (Ballmitte weniger als 5,5 Pixel vom Lochzentrum) und wird nicht gefangen, dreht sich seine Richtung je Bild um 1/64 rad zum Lochzentrum hin; wer links vorbeirollt, wird leicht nach rechts abgelenkt. Langsame Bälle bleiben länger am Rand und werden stärker abgelenkt, ein Ball genau über die Mitte läuft gerade. Randreibung SPEED/128 + 1 je Bild verhindert Energiegewinn durch Rundung. Bilder mit Wandkontakt lassen den Rand aus, damit sich die teuersten Kosten nicht addieren.

### Abnahmekriterien der Physik

- Dieselbe Eingabefolge liefert bitidentische Positionen, Geschwindigkeiten und Ergebnisse.
- Horizontale, vertikale und diagonale Schläge gleicher Stärke unterscheiden sich auf freier Fläche in Reichweite um höchstens 2 %; Richtungsabweichung höchstens 1°.
- Senkrechte und 45°-Banden reflektieren bei isoliertem Kontakt mit höchstens 1° Winkelfehler; Geschwindigkeit steigt ohne ausdrücklich ausgewiesenen Effekt nicht an.
- Kein Tunneling bei Höchstgeschwindigkeit, kein Steckenbleiben bei normalen Eckkontakten, kein sichtbares Zittern nach Stillstand.
- Legale Engstellen sind mindestens 10 Pixel breit, also mit deutlicher Reserve zum Balldurchmesser.
- Lochfang funktioniert auch dann, wenn der Ball in einem Schritt beide Seiten des Fangbereichs passiert.
- Physiktests decken Segmentmitte, Segmentende, Innen-/Außenecken, doppelte Kontakte, Materialgrenzen und Lochfang ab.

## 18 Löcher

Dies sind verbindliche Designbriefs; exakte Koordinaten entstehen im Bahneditor und werden erst nach Geometrie- und Spieltests eingefroren. Par ist seit 2026-10-06 festgelegt (Summe 49, Herleitung in [docs/par.md](docs/par.md)); die Par-Spalte unten ist der ursprüngliche Entwurf. Alle Bahnen müssen mit den Grundregeln lösbar sein.

| Nr. | Name | Par | Geometrie und Spielidee |
|---|---|---:|---|
| 1 | GERADER GEHT'S NICHT | 2 | Breites Rechteck, gerader Weg; Stärke und Ausrollen lernen. |
| 2 | RECHTS AB | 2 | Breites L, ein rechtwinkliger Knick; erste Bande. |
| 3 | LINKS AUCH | 2 | Gespiegeltes L mit engerem Schlussstück. |
| 4 | DER FLASCHENHALS | 3 | Große Startkammer, 16-Pixel-Durchgang, große Zielkammer. |
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

Umgesetzt (2026-10-05): Effekte aus [c16-sound-fx](https://github.com/phausser/c16-sound-fx) (PAL-Daten, nur die benötigten Schritte übernommen): Schlag Nr. 51 „boulder-diamond“, Bande Nr. 38 „switch-click“ bei jedem Wandkontakt, Einlochen Nr. 53 „paradroid-link“, Hole-in-one Nr. 83 „mario-mushroom“, Wasser Nr. 72 „flap-double“. Beide TED-Stimmen; in $FF10 und $FF12 werden nur die Frequenzbits 0–1 geschrieben, das Zeichensatzbit bleibt erhalten. Texte erscheinen im HUD, Partikel nur nach Stillstand bzw. Einlochen. Höchstens vier kleine Partikel, maximal etwa eine halbe Sekunde. Auslöser haben Cooldown und feste Priorität. Effekte ändern weder Ballzustand noch Physikzeit. Keine Bildschirmerschütterung. Ton abschaltbar; keine dauernde Musik während des Zielens. Erst nach erfolgreicher Physikabnahme als optionale Erweiterung denkbar: deutlich markierte Spezialbanden. Sie gehören nicht zum Grundumfang.

## Architektur und Daten

6502-kompatibler Assembler: verbindlich ACME (6502-Modus), Build über Make; Python-Werkzeuge für Bahnprüfung, Datenexport und Testreferenz. BASIC dient höchstens als SYS-Startstub. Spielcode nutzt eigene Hauptschleife, TED-Synchronisation, Eingabe und Sound; ROM-Routinen sind während des Spiels keine Abhängigkeit.

Module: Start/Hardware, Frame-Takt, Eingabe, Zustand/Score, Festkomma, Bewegung/Kollision, Bahn-Decoder, Bitmap-Zeichner, HUD, Sound/Effekte. Zustand und Darstellung sind getrennt, damit der echte Assembler-Physikkern automatisiert geprüft werden kann.

Bahnquelle in menschenlesbarem Datenformat: Name, Par, Abschlag, Loch, Startrichtung des Richtungswählers (`aim`, 0–127 im Uhrzeigersinn, 0 = rechts; ein Byte im Export, gesetzt bei Lochbeginn), Außenkontur, Hindernisse und Materialflächen. Export als kompakte Byte-Ströme (Format 3: Eckpunkte und Lauflängen in Zellen, Abschlag/Loch auf 2-Pixel-Raster; Testbahn 28 Bytes). Erst entpacken, dann Rendern und Kollisionsgeometrie aus derselben Quelle erzeugen. Keine 18 gespeicherten Bitmaps. Grenze pro Bahn: maximal 32 Kollisionssegmente insgesamt, einschließlich Hindernissen, höchstens sieben Wasserflächen (zellgenaue Rechtecke, 4 Bytes je Fläche, nur über ganzen Bodenzellen, Abschlag und Loch nicht im Wasser) und höchstens zwei weitere Materialflächen. Generator prüft Konturen, Überschneidungen, Ballfreiheit, Abschlag/Loch und Engstellen.

### Vorläufiger RAM-Vertrag

| Bereich | Bytes | Verwendung |
|---|---:|---|
| $0000–$01FF | 512 | Zero Page und Hardwarestack; reservierte CPU-Port-Adressen respektieren. |
| $0200–$2FFE | 11775 | Code, Tabellen, alle gepackten Bahnen, Zustand. |
| $2FFF | 1 | Klassifizierungsrand „versteckt“ (Zelle −1), zur Laufzeit geschrieben. |
| $3000–$33FF | 1024 | TED-Attribute (Vordergrundfarbe je Zelle; beim Zeichnen Zellklassen). |
| $3400–$37FF | 1024 | Zeichencodes. |
| $3800–$3BFF | 1024 | Zeichensatz: Ladebalken, HUD-Streifen, dynamische und Bahnzeichen. |
| $3C00–$3FFF | 1024 | Pixelpuffer des Bahnzeichners (3 Zellzeilen), sonst frei. |

Stand 2026-10-05: Laufzeitbereich 8360 Bytes belegt, 3415 Bytes frei vor den Attributen. ACME-Symbole, Assemblierzeit-Grenzprüfungen und Größenbericht müssen jeden Bereich nachweisen. Kein Heap; Scratch wird zwischen ausschließlich nacheinander aktiven Routinen geteilt. Das Programm darf beim Laden den BASIC-Arbeitsbereich überschreiben, kehrt anschließend nicht zu BASIC zurück.

Falls das Budget scheitert: Daten und Text komprimieren, Routinen vereinfachen und Effekte kürzen. Keine stille Umstellung auf 64 KB, Multicolor oder schwächere Eckphysik. Ein notwendiger Architekturwechsel wird ausdrücklich neu entschieden.

### Zeitbudget

Ziel: flüssige 50-Hz-Darstellung unter PAL mit aktiver Anzeige. Nicht mit dauerhaft maximalem CPU-Takt rechnen: TED teilt die Speicherzugriffe. Kandidaten für Kollision über Segment-Bounding-Boxes filtern. Begrenzte Segmentzahl, Geschwindigkeit und Kontakte machen die schlechteste Last messbar. Rastermarkierungen bzw. Emulator-Zyklusmessung erfassen Physik, Rendern und Restbudget. Sound und Effekte haben niedrige Priorität; kein Überspringen notwendiger Physikschritte, um Effekte zu retten.

## Qualität und Release

Freigabe erst bei allen 18 geprüften Bahnen, vollständiger Runde, korrekter Wertung und eingehaltenen Speichergrenzen. Hauptprüfung in VICE xplus4 mit tatsächlich eingestelltem C16/16-KB-PAL-Modell; Plus/4-64-KB-Defaults reichen nicht. Danach reale C16-Hardware für Bild, Eingabe, Tempo, Ton und Laden prüfen; fehlende Hardwareprüfung wird im Release dokumentiert.

Tests: deterministische Wiedergaben im tatsächlichen 6502-Kern, unabhängige hochpräzise Geometrie-Referenz, Grenzfälle und Worst-Case-Framezeiten. Host-Referenz allein bestätigt nicht das Zielprogramm. Bahnvalidator und Build brechen bei ungültiger Geometrie oder Speicherüberschreitung ab. Tuning prüft alle 32 Stärken und 128 Richtungen in repräsentativen Szenarien.

## Technische Quellen und offene Nachweise

Primärquelle: [Commodore TED 7360 Datenblatt](https://www.karlstechnology.com/commodore/TED7360-datasheet.pdf), insbesondere Textmodus, Zeichensatz- und Bildschirmadressierung, Register und Timing. Der Bildschirmblock (Attribute, dann Zeichencodes) ist 2-KB-, der Zeichensatz 1-KB-ausgerichtet. Registerwerte, Attributadressierung, RAM-Ladeverhalten und PAL/NTSC-Erkennung sind vor Implementierung am Datenblatt und im Emulator zu verifizieren. Gemessene Register- und Laufzeitnachweise stehen in docs/hardware.md; offene Freigaben sind in TODO.md ausgewiesen.

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
erkannt werden. Die Suche endet bei 1/16 Frame (CIRCLE_MIN_BIT = 16): Der Ball
stoppt am letzten geprüften Punkt außerhalb, höchstens 1/4 Pixel vor der Ecke. Geradensegment-Projektionen rechnen mit 1/64-Pixel-Präzision.
Gleichzeitige Kontakte werden nach stabiler Segmentreihenfolge aufgelöst.
Die Kontaktgrenze zählt Überschreitungen und verwirft die Restbewegung.

Der Prototyp erfüllt noch nicht sämtliche Abnahmekriterien: offene
Kontaktgrenzfälle, 50-Hz-Worst-Case und Platz für alle 18 Bahnen stehen in
TODO.md. Speicherstand und Laufzeit stehen in build/memory.json und
build/timing.json. Exakte Speicher- und Laufzeitmessungen
stehen in docs/hardware.md. Das 50-Hz-Ziel bleibt bestehen.

### Rundung, Optimierungen und kompakter Export

Geradenkontakte akzeptieren ein negatives unnormalisiertes Wand-Gap von
höchstens zwei Q8.8-Einheiten (2/256 Pixel auf Achsen) als Kontaktzeit null.
Größere negative Abstände werden nicht durch diese Rundungstoleranz
verdeckt. Bei Kreis-Sweeps bleibt der letzte äußere Wegpunkt maßgeblich.

Nach einem Abprall gibt es keine Wurzel- oder Divisionsnormierung mehr:
SPEED und UNIT werden direkt fortgeschrieben. Bei Achsen- und 45°-Banden
spiegelt der Rest des Frames die alte Geschwindigkeit; ab dem nächsten
Schritt gilt VELOCITY = SPEED · UNIT. Der spezielle radiale Diagonalfall
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
