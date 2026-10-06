# C16 Minigolf — Umsetzung

Grundlage: [SPEC.md](SPEC.md). Ziel ist ein vollständiges 18-Loch-Spiel auf dem unveränderten C16 mit 16 KB RAM. Reihenfolge beachten: Machbarkeit und Physik kommen vor Bahnproduktion und Effekten. Stand 2026-10-06: Schritt 1 ist abgeschlossen. Das Spiel läuft im TED-Textmodus mit allen 18 Bahnentwürfen, Wertung und Endwertung; Runtime 8360 Bytes, 3415 Bytes frei (`make budget`). 61 automatisierte Tests bestehen. VICE bestätigt ROM-Start, Textmodus, Eingabe, Joystick und Rendering; das Zeitbudget hält mit 31142 von 32000 Ticks (Test-Build mit Testbahn, ohne Wasser), inklusive der teuersten Winkel. Schritt 2 bleibt offen, bis Sweep- und Mehrfachkontaktfälle abgesichert sind; die Entwürfe sind noch nicht spielgetestet. Reale Hardware ist ungeprüft; alle sechs Tasten sind durch den Nutzer in VICE bestätigt. Messungen stehen in [docs/hardware.md](docs/hardware.md).

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
- [ ] Kontinuierlichen Sweep, Restbewegung, Doppelkontakte und Kontaktgrenze absichern (Basis implementiert).
- [x] Zielen, Stärke, Schlag und Einlochen als vollständigen Ablauf verbinden.
- [x] Code-, Daten- und Scratchbedarf messen; 18-Bahnen-Budget mit dem echten Testexport hochrechnen (`make budget`: 18 gleich große Exporte als ausdrückliche Annahme).
- [x] Schlechteste Framezeit mit Anzeige messen, einschließlich Engstellen und Mehrfachkontakten.
- [x] Allgemeine schräge Eckentreffer von 38873 auf höchstens 32000 PAL-Ticks optimieren; `make smoke` besteht mit 30173 Ticks, inklusive der vier teuersten Winkel eines 128-Winkel-Sweeps (neue Abprallphysik vom Nutzer in VICE als natürlich bestätigt).
- [x] Speicher erweitern und echtes 18-Bahnen-Budget nachweisen: Textmodus-Umbau, Spiel-Build mit allen 18 echten Exporten (371 Bytes gepackt), 3415 Bytes frei. Par-Metadaten fehlen noch.
- [x] Start innerhalb des Fangradius und Lochfang unmittelbar nach einem Abpraller gezielt absichern.
- [x] Wand-Kontakt-Epsilon gegen Rundungsreste von ein bis zwei Festkommaeinheiten prüfen.
- [ ] Gleichzeitige Kontakte und schrägere Endpunktfälle vollständig absichern.
- [x] Ball zeilenweise bytegenau zeichnen; Pixelbild aller acht Ausrichtungen, x=255/256 und rechte Bildkante vergleichen.
- [x] Verlustfreien Richtungs-/Längenexport samt Host-Decoder und Fehlerprüfungen implementieren (Testbahn 85 → 39 Bytes).
- [x] Komprimierten Export im ACME-Kern dekodieren und die entpackte aktuelle Bahn separat vom Kursbestand halten (`decode_course`, Puffer $0100–$019F, Host-Referenz bitgenau geprüft).

Abnahme: spielbarer Kern erfüllt Speicher- und Zeitbudget mit begründeter Reserve. Bei Überschreitung zuerst Architektur/Daten optimieren; Bahnproduktion erst nach erneutem Nachweis fortsetzen.

### Grafik

Seit 2026-10-05: schwarzer 6-Pixel-Rahmen (Schrägen glatt bis zur Zellkante, optisch gleich stark), gefülltes rundes Loch,
hellgraue Fläche, schwarzer Ball mit Glanzpunkt, grünes Schachbrett außerhalb
(siehe SPEC und docs/hardware.md). Der folgende Absatz beschreibt den Stand davor.

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
- [ ] Freien Speicher verteilen (Plan, Schritt 9).
- [x] Bahnwechsel beschleunigt: 1,6–3,1 → 0,89–1,47 Mio. Zyklen (Klassifizieren im Zeichenfenster statt eigener Füllung, schnellere Füllschleife, Schnellpfad für das volle Zeichen, ausgerollte Zellschleifen).

### Nächste Umsetzung innerhalb von Schritt 2

Speicher (Textmodus, 3415 Bytes frei) und Zeitbudget (31142 ≤ 32000 Ticks) sind nachgewiesen; die früheren Punkte zu Speicherarchitektur, 38873-Tick-Ecken und Decoder-Vergleich sind erledigt. Messstand und Fortsetzungskontext: [docs/continuation.md](docs/continuation.md); Teilkosten mit `make profile`, Rechenfälle mit `make benchmark`.

1. Kontinuierlichen Sweep, Restbewegung, Doppelkontakte und Kontaktgrenze systematisch prüfen; gleichzeitige Kontakte und schräge Endpunktfälle absichern.
2. Die 18 Entwürfe in VICE spieltesten (`make play HOLE=n`) und Auffälligkeiten festhalten.
3. Danach Schritt 2 schließen und mit Schritt 3/4 fortfahren.

## 3. Physik absichern

- [ ] Unabhängige hochpräzise Referenz und automatisierte Ausführung des echten 6502-Kerns einrichten.
- [ ] Deterministische Eingabereplays und bitgenaue Zustandsvergleiche erstellen.
- [ ] Reichweite und Richtung auf Achsen und Diagonalen gegen SPEC-Grenzen prüfen.
- [ ] Wandkontakte frontal, flach, an Endpunkten und bei maximaler Stärke testen.
- [ ] Innen-/Außenecken, gleichzeitige Kontakte und 10-Pixel-Passagen prüfen.
- [ ] Energiegewinn, Tunneling, Zittern und erschöpfte Kontaktlimits automatisch erkennen.
- [ ] Lochfang bei geringer/hoher Geschwindigkeit und Durchquerung innerhalb eines Schritts prüfen.
- [x] Wasserflächen (blaues Schachbrett, ohne Rahmen): Ball kehrt an den Bildanfang am Rand zurück; Format 4, Erkennung über den Farbton der Zelle unter der Ballmitte.
- [ ] Sand/Eis hinzufügen und Materialgrenzen testen.
- [ ] Physikkonstanten kalibrieren und dokumentieren; Referenz und Zielkern vergleichen.

Abnahme: sämtliche Physikkriterien aus SPEC erfüllt; dokumentierte Grenzfälle und reproduzierbare Tests vorhanden.

## 4. Bahnwerkzeuge und 18-Loch-Kurs

- [ ] Menschenlesbare Bahnquellen, Generator und kompakte Exporte anlegen (Entwürfe 1–18 in assets/courses, 371 Bytes gepackt, im Spiel-Build; Generator und Exporte vorhanden, Bahnen noch nicht spielgetestet).
- [x] Validator für geschlossene Konturen, ungültige Schnittpunkte und Segmentlimit bauen.
- [x] Bahneditor im Browser (`make editor`) mit denselben Regeln und Größenanzeige; `make play HOLE=n` zum Ausprobieren.
- [ ] Ballradius, Engstellen, gültige Start-/Lochpositionen und Erreichbarkeit prüfen.
- [x] Vorschau erzeugen, die dieselben exportierten Geometriedaten verwendet (`make preview`, echter 6502-Renderer).
- [ ] Löcher 1–3: Gerade, L rechts, L links bauen und spielen.
- [ ] Löcher 4–6: Flaschenhals, Z, U bauen und spielen.
- [ ] Löcher 7–9: dick/dünn, Diagonalbande, Raute bauen und spielen.
- [ ] Löcher 10–12: S, Hindernisse, Sand bauen und spielen.
- [ ] Löcher 13–15: Eis, Trichter, Nadel bauen und spielen.
- [ ] Löcher 16–18: Banden, Labyrinth, Finale bauen und spielen.
- [ ] Für jedes Loch mindestens eine robuste Lösung als Replay sichern.
- [ ] Engstellen und Einlochen mit benachbarten Richtungs-/Stärkewerten auf Fairness prüfen.
- [ ] Namen, Schwierigkeit, Par und Gesamtsumme nach Spieltests finalisieren.
- [x] Alle 18 Exporte gemeinsam gegen das echte RAM-Budget prüfen (`make budget`: 3415 Bytes frei; nach Änderungen erneut prüfen).

Abnahme: 18 unterscheidbare, lösbare und faire Bahnen; keine unsichtbaren Kanten, kein zwingender einzelner Präzisionsschlag.

## 5. Vollständiges Spiel

- [ ] Titel, kompakte Bedienhilfe und Rundenstart ergänzen.
- [ ] Eigener Zeichensatz (zurückgestellt; ROM-Schrift genügt vorerst, eigene Glyphen ~8 Bytes je Zeichen).
- [ ] HUD mit Loch, Par, Schlägen, Stärke und Gesamtstand fertigstellen (Bahn links, Punkte rechts und pixelweiser Ladebalken in der Mitte umgesetzt; Par und Gesamtstand fehlen).
- [ ] Training mit freier Lochwahl implementieren.
- [x] Lochbilanz und bestätigten Übergang zum nächsten Loch implementieren (Ergebnis in der Statuszeile, Feuer führt weiter).
- [x] Schlaglimit mit 13er-Wertung implementieren (Ball verschwindet, PUNKTE 13).
- [x] Endwertung (PAR links, SUMME rechts) und bestätigten Rundenneustart implementieren; Einzelergebnisse aus Speichergründen nicht gespeichert.
- [x] Joystick Port 1 integriert und im VICE-Port getestet; Tastatur nur noch P. Feuerdauer steuert Stärke.
- [ ] Grafiküberlappungen, Pausieren und gehaltene Tasten an Zustandsübergängen prüfen.

Abnahme: vollständige Runde vom Start bis zur korrekten Endwertung ohne Neustart, Speicherfehler oder Eingabesperre spielbar.

## 6. Humor und Ton

- [x] Kurze Schlag-, Banden-, Einloch- und Wassergeräusche mit TED erzeugen. Seit 2026-10-05 Effekte 51/38/53 aus c16-sound-fx auf beiden Stimmen, Wasser Rauschen; Hörprüfung in VICE steht aus.
- [ ] Tonumschaltung ergänzen.
- [ ] HUD-Kommentare mit Cooldown und Prioritäten hinzufügen.
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
