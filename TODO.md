# C16 Minigolf — Umsetzung

Grundlage: [SPEC.md](SPEC.md). Ziel ist ein vollständiges 18-Loch-Spiel auf dem unveränderten C16 mit 16 KB RAM. Reihenfolge beachten: Machbarkeit und Physik kommen vor Bahnproduktion und Effekten. Noch nichts implementiert oder am Gerät gemessen.

## 1. Werkzeugkette und Hardware-Nachweis

- [ ] ca65/ld65-Projekt, BASIC-SYS-Stub und reproduzierbaren Build einrichten.
- [ ] Linkerlayout gemäß SPEC anlegen; Überlauf als Buildfehler, Größenbericht erzeugen.
- [ ] TED-Datenblatt auswerten: Bitmap, Attribute, IRQ/Takt, Eingabe und Sound dokumentieren.
- [ ] VICE xplus4 explizit für C16, 16 KB und PAL konfigurieren; Startkommando dokumentieren.
- [ ] PRG laden und monochrome 320×200-Testgrafik darstellen; RAM-Grenzen prüfen.
- [ ] Eigene Hauptschleife und zuverlässige 50-Hz-Synchronisation aufsetzen.
- [ ] Tastaturmatrix prüfen; entprellte Eingabe und Pause implementieren.

Abnahme: PRG startet im 16-KB-Modell, zeigt stabile Hi-Res-Grafik, reagiert auf Eingabe und erzeugt einen nachvollziehbaren Speicherbericht.

## 2. Machbarer Vertikalschnitt

- [ ] Eine Testbahn mit breiter Fläche, 10-Pixel-Engstelle, L-Ecke und 45°-Bande erstellen.
- [ ] Kompaktes Bahnformat und Decoder für maximal 32 Segmente implementieren.
- [ ] Statische Geometrie zeichnen; Ball mit Hintergrundrestaurierung bewegen.
- [ ] Festkommaformate, Zwischenbreiten, Rundung und Kontakt-Epsilon festlegen.
- [ ] 128 Richtungen und 32 Stärken erzeugen und normieren.
- [ ] Rollreibung, exakten Stillstand und Wegprüfung am Loch implementieren.
- [ ] Kreis-Segment- und Kreis-Endpunkt-Kontakte mit frühestem Kontakt implementieren.
- [ ] Teilintervalle, Restbewegung, Doppelkontakte und sichere Kontaktgrenze implementieren.
- [ ] Zielen, Stärke, Schlag und Einlochen als vollständigen Ablauf verbinden.
- [ ] Code-, Daten- und Scratchbedarf messen; 18-Bahnen-Budget mit echten Exportdaten hochrechnen.
- [ ] Schlechteste Framezeit mit Anzeige messen, einschließlich Engstellen und Mehrfachkontakten.

Abnahme: spielbarer Kern erfüllt Speicher- und Zeitbudget mit begründeter Reserve. Bei Überschreitung zuerst Architektur/Daten optimieren; Bahnproduktion erst nach erneutem Nachweis fortsetzen.

## 3. Physik absichern

- [ ] Unabhängige hochpräzise Referenz und automatisierte Ausführung des echten 6502-Kerns einrichten.
- [ ] Deterministische Eingabereplays und bitgenaue Zustandsvergleiche erstellen.
- [ ] Reichweite und Richtung auf Achsen und Diagonalen gegen SPEC-Grenzen prüfen.
- [ ] Wandkontakte frontal, flach, an Endpunkten und bei maximaler Stärke testen.
- [ ] Innen-/Außenecken, gleichzeitige Kontakte und 10-Pixel-Passagen prüfen.
- [ ] Energiegewinn, Tunneling, Zittern und erschöpfte Kontaktlimits automatisch erkennen.
- [ ] Lochfang bei geringer/hoher Geschwindigkeit und Durchquerung innerhalb eines Schritts prüfen.
- [ ] Sand/Eis hinzufügen und Materialgrenzen testen.
- [ ] Physikkonstanten kalibrieren und dokumentieren; Referenz und Zielkern vergleichen.

Abnahme: sämtliche Physikkriterien aus SPEC erfüllt; dokumentierte Grenzfälle und reproduzierbare Tests vorhanden.

## 4. Bahnwerkzeuge und 18-Loch-Kurs

- [ ] Menschenlesbare Bahnquellen, Generator und kompakte Exporte anlegen.
- [ ] Validator für geschlossene Konturen, ungültige Schnittpunkte und Segmentlimit bauen.
- [ ] Ballradius, Engstellen, gültige Start-/Lochpositionen und Erreichbarkeit prüfen.
- [ ] Vorschau erzeugen, die dieselben exportierten Geometriedaten verwendet.
- [ ] Löcher 1–3: Gerade, L rechts, L links bauen und spielen.
- [ ] Löcher 4–6: Flaschenhals, Z, U bauen und spielen.
- [ ] Löcher 7–9: dick/dünn, Diagonalbande, Raute bauen und spielen.
- [ ] Löcher 10–12: S, Hindernisse, Sand bauen und spielen.
- [ ] Löcher 13–15: Eis, Trichter, Nadel bauen und spielen.
- [ ] Löcher 16–18: Banden, Labyrinth, Finale bauen und spielen.
- [ ] Für jedes Loch mindestens eine robuste Lösung als Replay sichern.
- [ ] Engstellen und Einlochen mit benachbarten Richtungs-/Stärkewerten auf Fairness prüfen.
- [ ] Namen, Schwierigkeit, Par und Gesamtsumme nach Spieltests finalisieren.
- [ ] Alle 18 Exporte gemeinsam gegen das echte RAM-Budget prüfen.

Abnahme: 18 unterscheidbare, lösbare und faire Bahnen; keine unsichtbaren Kanten, kein zwingender einzelner Präzisionsschlag.

## 5. Vollständiges Spiel

- [ ] Titel, kompakte Bedienhilfe und Rundenstart ergänzen.
- [ ] HUD mit Loch, Par, Schlägen, Stärke und Gesamtstand fertigstellen.
- [ ] Training mit freier Lochwahl implementieren.
- [ ] Lochbilanz und bestätigten Übergang zum nächsten Loch implementieren.
- [ ] Schlaglimit mit 13er-Wertung und Abbruchmarkierung implementieren.
- [ ] 18 Ergebnisse, Endwertung und bestätigten Rundenneustart implementieren.
- [ ] Optionalen Joystick prüfen und integrieren; Tastatur bleibt vollständig nutzbar.
- [ ] Grafiküberlappungen, Pausieren und gehaltene Tasten an Zustandsübergängen prüfen.

Abnahme: vollständige Runde vom Start bis zur korrekten Endwertung ohne Neustart, Speicherfehler oder Eingabesperre spielbar.

## 6. Humor und Ton

- [ ] Kurze Schlag-, Banden- und Einlochgeräusche mit TED erzeugen.
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
