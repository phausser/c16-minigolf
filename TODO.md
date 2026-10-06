# C16 Minigolf — Umsetzung

Grundlage: [SPEC.md](SPEC.md). Ziel ist ein vollständiges 18-Loch-Spiel auf dem unveränderten C16 mit 16 KB RAM. Reihenfolge beachten: Machbarkeit und Physik kommen vor Bahnproduktion und Effekten. Stand 2026-10-06: Schritte 1 bis 4 sind abgeschlossen. Das Spiel läuft im TED-Textmodus mit allen 18 Bahnen, Wertung und Endwertung; Runtime 10528 Bytes, 1247 Bytes frei. Die Physik ist gegen eine unabhängige Referenz abgesichert ([docs/physics.md](docs/physics.md), `make physics`: 188 288 Schläge ohne Verletzung). VICE bestätigt ROM-Start, Textmodus, Eingabe, Joystick und Rendering; das Zeitbudget hält mit 31028 von 32000 Ticks, inklusive der teuersten Winkel. Weiter mit Schritt 5. Reale Hardware ist ungeprüft; alle sechs Tasten sind durch den Nutzer in VICE bestätigt. Messungen stehen in [docs/hardware.md](docs/hardware.md).

## 1. Werkzeugkette und Hardware-Nachweis

- [x] ACME-Projekt im 6502-Modus, BASIC-SYS-Stub und reproduzierbaren Build einrichten.
- [x] ACME-Speicherlayout gemäß SPEC anlegen; Überlauf als Buildfehler, Größenbericht erzeugen.
- [x] TED-Datenblatt auswerten: Bitmap, Attribute, IRQ/Takt und Eingabe dokumentieren.
- [x] TED-Soundregister und PAL/NTSC-Erkennung für die späteren Module dokumentieren.
- [x] VICE xplus4 explizit für C16, 16 KB und PAL konfigurieren; Startkommando dokumentieren.
- [x] PRG laden und monochrome 320×200-Testgrafik darstellen; RAM-Grenzen prüfen.
- [x] Eigene Hauptschleife und zuverlässige 50-Hz-Synchronisation aufsetzen.
- [x] Tastaturmatrix gegen VICE-Keymap prüfen; entprellte Eingabe und Pause implementieren.
- [x] Physische Tasten auf realem C16 oder über echte VICE-Tastaturereignisse bestätigen (A/D/W/S/SPACE/P vom Nutzer in VICE bestätigt).

Abnahme im Emulator: PRG startet im 16-KB-Modell, zeigt stabile Hi-Res-Grafik und erzeugt einen nachvollziehbaren Speicherbericht. Logische Eingabeereignisse sind geprüft; der Nutzer hat am 2026-10-04 alle sechs Tasten in VICE bestätigt. Schritt 1 ist abgeschlossen. Reale C16-Hardware bleibt Teil der Freigabe.

## 2. Machbarer Vertikalschnitt

- [x] Eine Testbahn mit breiter Fläche, 16-Pixel-Engstelle, L-Ecke und 45°-Bande erstellen.
- [x] Kompaktes Bahnformat und Decoder für maximal 32 Segmente implementieren.
- [x] Statische Geometrie sowie Ball-/Zielmarke zeichnen; Hintergrundrestaurierung prüfen.
- [x] Ballposition aus der tatsächlichen Bewegung übernehmen.
- [x] Festkommaformate, Zwischenbreiten, Rundung und Kontakt-Epsilon festlegen (SPEC; Wand-Gap-Toleranz 2/256 Pixel).
- [x] Pixelgenaue Ballbewegung mit Subpixel-Physik implementieren und prüfen: jede Pixelposition erreichbar, kein Einrasten auf Zeichen- oder Zweipixelraster, auch rechts von x=255.
- [x] 128 Richtungen und 32 Stärken erzeugen und normieren.
- [x] Rollreibung, exakten Stillstand und Wegprüfung am Loch implementieren.
- [x] Kreis-Segment- und Kreis-Endpunkt-Kontakte mit frühestem Kontakt implementieren.
- [x] Kontinuierlichen Sweep, Restbewegung, Doppelkontakte und Kontaktgrenze absichern (2026-10-06: Scheinkontakte im Reststück behoben, Kontaktlimit im 4-px-Spalt sichtbar, Sweep aller Bahnen ohne Limit; docs/physics.md).
- [x] Zielen, Stärke, Schlag und Einlochen als vollständigen Ablauf verbinden.
- [x] Code-, Daten- und Scratchbedarf messen; 18-Bahnen-Budget mit dem echten Testexport hochrechnen (`make budget`: 18 gleich große Exporte als ausdrückliche Annahme).
- [x] Schlechteste Framezeit mit Anzeige messen, einschließlich Engstellen und Mehrfachkontakten.
- [x] Allgemeine schräge Eckentreffer von 38873 auf höchstens 32000 PAL-Ticks optimieren; `make smoke` besteht mit 30173 Ticks, inklusive der vier teuersten Winkel eines 128-Winkel-Sweeps (neue Abprallphysik vom Nutzer in VICE als natürlich bestätigt).
- [x] Speicher erweitern und echtes 18-Bahnen-Budget nachweisen: Textmodus-Umbau, Spiel-Build mit allen 18 echten Exporten (371 Bytes gepackt), 3415 Bytes frei. Par-Metadaten fehlen noch.
- [x] Start innerhalb des Fangradius und Lochfang unmittelbar nach einem Abpraller gezielt absichern.
- [x] Wand-Kontakt-Epsilon gegen Rundungsreste von ein bis zwei Festkommaeinheiten prüfen.
- [x] Gleichzeitige Kontakte und schrägere Endpunktfälle vollständig absichern (gemeinsame Normale in 135°-Ecken, Eckennormale normiert, Wand vor Eckpunkt im 1/16-Bild-Fenster).
- [x] Ball zeilenweise bytegenau zeichnen; Pixelbild aller acht Ausrichtungen, x=255/256 und rechte Bildkante vergleichen.
- [x] Verlustfreien Richtungs-/Längenexport samt Host-Decoder und Fehlerprüfungen implementieren (Testbahn 85 → 39 Bytes).
- [x] Komprimierten Export im ACME-Kern dekodieren und die entpackte aktuelle Bahn separat vom Kursbestand halten (`decode_course`, Puffer $0100–$019F, Host-Referenz bitgenau geprüft).

Abnahme: spielbarer Kern erfüllt Speicher- und Zeitbudget mit begründeter Reserve. Bei Überschreitung zuerst Architektur/Daten optimieren; Bahnproduktion erst nach erneutem Nachweis fortsetzen.

### Grafik

Seit 2026-10-05: schwarzer 6-Pixel-Rahmen (Schrägen glatt bis zur Zellkante, optisch gleich stark), gefülltes rundes Loch,
hellgraue Fläche, schwarzer Ball mit Glanzpunkt, grünes Schachbrett außerhalb
(siehe SPEC und docs/hardware.md). Seit 2026-10-06: weiße Fläche, Rasen in
waagerechten Streifen von zwei Zeilen. Der folgende Absatz beschreibt den Stand davor.

### Grafikänderung vor der Speicheroptimierung

Glatte graue Fläche wiederhergestellt, Pixelmuster und Schatten entfernt.
Vollständig spielbare 8×8-Zellen: Grau/Weiß. Zellen mit festen Geometriepixeln:
Grau/Schwarz. Ball/Zielmarke/Lochring nehmen die jeweilige Zell-Vordergrundfarbe
an; beim Zellübergang teilweise schwarz/weiß. Keine Konturänderung.
Palette zentral in src/palette.inc als (LUMINANZ << 4) + FARBE, Fläche weiter
Luminanz 5. Klassifizierung aus statischer Bitmap vor den Markierungen.
47 Tests bestehen, VICE bestätigt Bild und Restaurierung sowie den echten
emulierten Joystick-Port. Gerade Kanten am 8×8-Raster, Engstelle nun 16 Pixel.
Nur Stärkeanzeige im HUD; Joystick links/rechts dreht, Feuer halten lädt,
Loslassen schlägt. Runtime 5264 Bytes, 368 frei; versteckte Zeilen 21–23 876/960.
Bahnen liegen gepackt (Format 2) im Kern; decode_course entpackt die aktuelle
Bahn in die Stackseite, Füllkanten entstehen beim Zeichnen aus den Segmenten.
Für 17 weitere Bahnen in Testbahngröße fehlen 302 Bytes plus Metadaten.
Laufzeitabnahme bestanden: 30173 ≤ 32000 PAL-Ticks
auf der veränderten Testbahn. Historische Physik-Replays verwenden ihre
ursprüngliche Geometrie in fixtures/course-before-cell-grid.json.

### Textmodus (umgesetzt 2026-10-05)

Plan und Ergebnis: [docs/textmode-plan.md](docs/textmode-plan.md).

- [x] Entscheidung in der SPEC festhalten.
- [x] Test-Helfer Text → Pixel; alle Bahnen pixelgleich zur Referenz.
- [x] Speicherumbau ohne versteckte Bitmap-Bereiche: 3415 Bytes frei.
- [x] Statischer Renderer auf Zeichen, mit Zeichenbudget (höchstens 25 von 64).
- [x] HUD auf Zeichen.
- [x] Ball und Zielpunkte über dynamische Zeichen.
- [x] VICE-Smoke und Zeitbudget: 31142 ≤ 32000 Ticks.
- [x] Editor: Zeichenzahl je Bahn.
- [x] README-Screenshot neu erzeugen.
- [x] Freien Speicher verteilen (Plan, Schritt 9): Verteilung unten unter „Speicherverteilung“.
- [x] Bahnwechsel beschleunigt: 1,6–3,1 → 0,89–1,47 Mio. Zyklen (Klassifizieren im Zeichenfenster statt eigener Füllung, schnellere Füllschleife, Schnellpfad für das volle Zeichen, ausgerollte Zellschleifen).

### Speicherverteilung (2026-10-06)

Nach der Physikabsicherung bleiben im Spiel-Build 1247 Bytes frei (`make`;
vorher 1858, davon 256 für die Quadrattabelle der schnelleren
Multiplikation). Sand und Eis entfallen. Vorschlag für den Rest, grob
geschätzt; Reihenfolge wie in Schritt 5 und 6:

| Zweck | Schritt | Bytes |
|---|---|---:|
| Titel und kompakte Bedienhilfe (ROM-Zeichensatz nur auf dem Titelbild, Text) | 5 | 250 |
| Laufender Gesamtstand im HUD | 5 | 40 |
| Training mit freier Lochwahl | 5 | 80 |
| Tonumschaltung | 6 | 30 |
| HUD-Kommentare mit Cooldown und Prioritäten | 6 | 250 |
| Hole-in-one-Sternchen und Abschlussfanfare | 6 | 150 |
| Reserve für Korrekturen bis zur Freigabe | 7 | 300 |
| **Summe** | | **1100** |

Übersteigt ein Punkt seine Schätzung, zuerst Code verkleinern, dann den
Umfang kürzen; die Reserve bleibt bis zur Freigabe unangetastet.

### Nächste Umsetzung innerhalb von Schritt 2

Speicher (Textmodus, 2623 Bytes frei) und Zeitbudget (31140 ≤ 32000 Ticks) sind nachgewiesen; die früheren Punkte zu Speicherarchitektur, 38873-Tick-Ecken und Decoder-Vergleich sind erledigt. Messstand und Fortsetzungskontext: [docs/continuation.md](docs/continuation.md); Teilkosten mit `make profile`, Rechenfälle mit `make benchmark`.

1. Kontinuierlichen Sweep, Restbewegung, Doppelkontakte und Kontaktgrenze systematisch prüfen; gleichzeitige Kontakte und schräge Endpunktfälle absichern. Erledigt 2026-10-06 (docs/physics.md).
2. Die 18 Entwürfe in VICE spieltesten (`make play HOLE=n`) und Auffälligkeiten festhalten. Erledigt 2026-10-06: alle 18 Bahnen vom Nutzer in VICE gespielt; 1–4, 6, 11 und 13–16 danach überarbeitet, die übrigen ohne Änderungswunsch. Dabei neu: Lochrand lenkt ab, Loch mit Schatten, Startrichtung je Bahn und danach Richtung aufs Loch, Wasser +1 Schlag mit 3 Pixel Abstand zum Ufer, bis zu 7 Wasserflächen.
3. Schritt 2 ist abgeschlossen.

## 3. Physik absichern

- [x] Unabhängige hochpräzise Referenz und automatisierte Ausführung des echten 6502-Kerns einrichten (tests/physics_reference.py, tests/physics_check.py, `make physics`).
- [x] Deterministische Eingabereplays und bitgenaue Zustandsvergleiche erstellen (tests/replay.py, fixtures/input-replays.json: Joystick-Eingaben aller 18 Lösungswege).
- [x] Reichweite und Richtung auf Achsen und Diagonalen gegen SPEC-Grenzen prüfen (alle 32 Stärken: höchstens 0,17 % und 0,02°; Geschwindigkeit jetzt gerundet).
- [x] Wandkontakte frontal, flach, an Endpunkten und bei maximaler Stärke testen.
- [x] Innen-/Außenecken, gleichzeitige Kontakte und 10-Pixel-Passagen prüfen; Validator und Editor lehnen Engstellen unter 10 px ab.
- [x] Energiegewinn, Tunneling, Zittern und erschöpfte Kontaktlimits automatisch erkennen (dabei Energiegewinn an Ecken gefunden und behoben).
- [x] Lochfang bei geringer/hoher Geschwindigkeit und Durchquerung innerhalb eines Schritts prüfen.
- [x] Wasserflächen (blaues Schachbrett, ohne Rahmen): Ball kehrt an den Bildanfang am Rand zurück; Format 4, Erkennung über den Farbton der Zelle unter der Ballmitte; ein Strafschlag.
- [x] Physikkonstanten kalibrieren und dokumentieren; Referenz und Zielkern vergleichen (docs/physics.md).

Abnahme: sämtliche Physikkriterien aus SPEC erfüllt; dokumentierte Grenzfälle und reproduzierbare Tests vorhanden. Erfüllt 2026-10-06; Par von Bahn 2 bleibt nach Nutzerentscheidung 2 (docs/par.md).

## 4. Bahnwerkzeuge und 18-Loch-Kurs

- [x] Menschenlesbare Bahnquellen, Generator und kompakte Exporte anlegen (Bahnen 1–18 in assets/courses, 371 Bytes gepackt, im Spiel-Build; vom Nutzer am 2026-10-06 spielgetestet).
- [x] Validator für geschlossene Konturen, ungültige Schnittpunkte und Segmentlimit bauen.
- [x] Bahneditor im Browser (`make editor`) mit denselben Regeln und Größenanzeige; `make play HOLE=n` zum Ausprobieren.
- [x] Ballradius, Engstellen, gültige Start-/Lochpositionen und Erreichbarkeit prüfen (Validator, Solver-Replays, Spieltest).
- [x] Vorschau erzeugen, die dieselben exportierten Geometriedaten verwendet (`make preview`, echter 6502-Renderer).
- [x] Löcher 1–3: Gerade, L rechts, L links bauen und spielen.
- [x] Löcher 4–6: Flaschenhals, Z, U bauen und spielen.
- [x] Löcher 7–9: dick/dünn, Diagonalbande, Raute bauen und spielen.
- [x] Löcher 10–12: S, Hindernisse, breite Bahn bauen und spielen (Sand und Eis am 2026-10-06 gestrichen).
- [x] Löcher 13–15: Eis, Trichter, Nadel bauen und spielen (Bahn 13 jetzt Wasser-Mäander statt Eis).
- [x] Löcher 16–18: Banden, Labyrinth, Finale bauen und spielen.
- [x] Für jedes Loch mindestens eine Lösung als Replay sichern (`make solve`, tests/fixtures/course-solutions.json, Test im Spiel-Build; Toleranz nur für den letzten Schlag gemessen, siehe docs/par.md).
- [x] Engstellen und Einlochen mit benachbarten Richtungs-/Stärkewerten auf Fairness prüfen (Spieltest des Nutzers 2026-10-06: spielt sich gut).
- [x] Par und Gesamtsumme nach Spieltest und Solver festgelegt: Summe 49 (docs/par.md). Namen bleiben vorerst.
- [x] Alle 18 Exporte gemeinsam gegen das echte RAM-Budget prüfen (`make budget`: 2623 Bytes frei; nach Änderungen erneut prüfen).

Abnahme: 18 unterscheidbare, lösbare und faire Bahnen; keine unsichtbaren Kanten, kein zwingender einzelner Präzisionsschlag. Schritt 4 am 2026-10-06 vom Nutzer abgenommen.

## 5. Vollständiges Spiel

- [ ] Titel, kompakte Bedienhilfe und Rundenstart ergänzen.
- [x] Eigener Zeichensatz: 5 Pixel hohe HUD-Schrift (Ziffern, Schrägstrich, Fähnchen, Schläger) als Pixelstreifen; keine ROM-Zeichen mehr (2026-10-06).
- [ ] HUD mit Loch, Par, Schlägen, Stärke und Gesamtstand fertigstellen (Fähnchen und Bahnnummer links, Schläger und Schläge/Par rechts, Ladebalken als Rahmen mit Skala 25/50/75 % in der Mitte umgesetzt; laufender Gesamtstand fehlt).
- [ ] Training mit freier Lochwahl implementieren.
- [x] Lochbilanz und bestätigten Übergang zum nächsten Loch implementieren (Ergebnis in der Statuszeile, Feuer führt weiter).
- [x] Schlaglimit mit 13er-Wertung implementieren (Ball verschwindet, Schlagzahl 13).
- [x] Endwertung (Schläger und Gesamtschläge/Gesamtpar rechts) und bestätigten Rundenneustart implementieren; Einzelergebnisse aus Speichergründen nicht gespeichert.
- [x] Joystick Port 1 integriert und im VICE-Port getestet; Tastatur nur noch P. Feuerdauer steuert Stärke.
- [ ] Grafiküberlappungen, Pausieren und gehaltene Tasten an Zustandsübergängen prüfen.

Abnahme: vollständige Runde vom Start bis zur korrekten Endwertung ohne Neustart, Speicherfehler oder Eingabesperre spielbar.

## 6. Humor und Ton

- [x] Kurze Schlag-, Banden-, Einloch- und Wassergeräusche mit TED erzeugen. Seit 2026-10-05 Effekte 51/38/53 aus c16-sound-fx auf beiden Stimmen, Wasser 72, Hole-in-one 83; Hörprüfung in VICE bestanden (2026-10-06).
- [ ] Tonumschaltung ergänzen.
- [ ] HUD-Kommentare mit Cooldown und Prioritäten hinzufügen.
- [x] Bewegtes Wasser: diagonal laufender Schatten- und Helligkeitszyklus (src/water.asm, bis 538 Zyklen je Frame auf Bahn 13; Smoke-Bahn ohne Wasser, Messung mit Wasser steht aus).
- [ ] Hole-in-one-Sternchen und Abschlussfanfare im verbleibenden Budget ergänzen.
- [ ] Physikreplays mit und ohne Effekte vergleichen: identische Ballzustände verlangen.
- [ ] Größe und schlechteste Framezeit erneut prüfen; Effekte bei Budgetproblemen kürzen.

Abnahme: Effekte sind kurz, lesbar und beeinflussen weder Steuerung noch Physik.

## 7. Freigabe

- [ ] Release-Build im C16/16-KB-PAL-Emulator vollständig durchspielen.
- [ ] Alle Physikreplays, Bahnvalidierungen und Speicherprüfungen im Release-Build ausführen.
- [ ] Worst-Case-Framezeiten über alle 18 Bahnen messen und dokumentieren.
- [ ] Auf echtem C16 Laden, Bild, Tasten, Joystick, Tempo und Ton prüfen; fehlende Prüfung transparent ausweisen.
- [ ] NTSC-Erkennung und 50-Hz-Zeitbasis nur nach eigener Laufzeitprüfung freigeben; sonst PAL-Anforderung dokumentieren.
- [ ] PRG und D64 erzeugen, Laden beider Artefakte prüfen.
- [ ] README mit Bedienung, Hardwarevoraussetzungen, Build und bekannten Einschränkungen schreiben.
- [ ] Finale SPEC mit gemessenen Budgets, Steuerung, Physikkonstanten und tatsächlichem Par aktualisieren.

Fertig, wenn alle 18 Löcher funktionieren, die Runde korrekt gewertet wird, die Physikabnahme bestanden ist und das Spiel ohne Erweiterung in 16 KB läuft. Reale Hardwareprüfung bleibt ein gesondert auszuweisender Nachweis.
