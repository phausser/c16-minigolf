# Par und Lösungswege

Stand 2026-10-06. Par aller 18 Bahnen ist festgelegt (Summe **49**); jede
Bahn hat einen gespeicherten Lösungsweg, den die Tests im Spiel-Build
nachspielen.

## Verfahren

`tools/solve_courses.py` (`make solve`, optional `HOLES="3 7"`) spielt jede
Bahn mit dem echten 6502-Kern in py65, also mit genau der Physik des Spiels.

- Von jeder Ruhelage aus werden jede 4. der 128 Richtungen sowie die 13
  Richtungen um das Loch herum mit den Stärken 6, 10, 14, 18, 22, 26 und 31
  geschlagen (rund 300 Schläge je Lage).
- Schläge ins Wasser fallen weg; ein Lösungsweg kommt ohne Strafschlag aus.
- Für den nächsten Schlag bleiben die 10 Lagen mit dem kürzesten Laufweg
  zum Loch (Gitter-Suche um Wände und Wasser, 4-Pixel-Raster).
- Sobald ein Schlag einlocht, endet die Suche. Unter allen einlochenden
  Schlägen dieser Tiefe gewinnt der mit dem größten **Fenster**: wie viele
  der 8 Nachbarschläge (Richtung ±1, Stärke ±2) ebenfalls einlochen.
- Ergebnis: `tests/fixtures/course-solutions.json` (Schläge als
  `[Richtung, Stärke]`). `tests/test_course_solutions.py` spielt jeden Weg im
  Spiel-Build nach und prüft, dass der letzte Schlag einlocht und keiner ins
  Wasser geht. Schlägt der Test fehl, haben sich Bahn oder Physik geändert:
  Solver erneut laufen lassen.

Laufzeit: etwa 25 Minuten für alle Bahnen auf 8 Kernen.

## Grenzen

- Die gefundene Schlagzahl ist eine **obere Schranke** für das Optimum,
  kein Beweis: Richtungen und Stärken sind nur grob abgetastet.
- Der Solver trifft jeden Wert exakt. Das Fenster misst die Toleranz nur
  für den letzten Schlag; frühere Schläge eines Wegs können ebenso exakt
  sein müssen.
- Wert 0/8 heißt: nur genau dieser eine Schlag locht ein.

## Ergebnis und Par

Regel: **Par = gefundene Schläge + 1**, weil kein Mensch so genau trifft.
Ausnahme: sehr kurze, übersichtliche Bahnen (1, 3, 8) behalten Par =
gefunden. Vom Nutzer am 2026-10-06 so festgelegt.

| Bahn | Name | gefunden | Fenster | Par vorher | **Par** |
|---:|---|---:|---:|---:|---:|
| 1 | Gerader geht's nicht | 2 | 5/8 | 2 | **2** |
| 2 | Rechts ab | 1 | 0/8 | 2 | **2** |
| 3 | Links auch | 2 | 8/8 | 2 | **2** |
| 4 | Der Flaschenhals | 2 | 5/8 | 3 | **3** |
| 5 | Zweimal um die Ecke | 1 | 0/8 | 3 | **2** |
| 6 | Die Abkürzung | 2 | 0/8 | 3 | **3** |
| 7 | Dick und dünn | 2 | 0/8 | 3 | **3** |
| 8 | Billardpause | 2 | 6/8 | 2 | **2** |
| 9 | Raute mit Laune | 1 | 2/8 | 3 | **2** |
| 10 | Schlangenlinie | 2 | 0/8 | 4 | **3** |
| 11 | Inselhüpfen ohne Hüpfen | 2 | 7/8 | 3 | **3** |
| 12 | Sand im Getriebe | 2 | 8/8 | 3 | **3** |
| 13 | Glatte Sache | 3 | 1/8 | 4 | **4** |
| 14 | Der Trichter | 2 | 3/8 | 3 | **3** |
| 15 | Die Nadel | 2 | 4/8 | 4 | **3** |
| 16 | Bandenbande | 2 | 5/8 | 3 | **3** |
| 17 | Das Labyrinthchen | 2 | 2/8 | 4 | **3** |
| 18 | Feierabend | 2 | 1/8 | 4 | **3** |
| | **Summe** | 33 | | 57 | **49** |

Hole-in-one ist auf den Bahnen 2, 5 und 9 möglich, auf 9 mit etwas
Spielraum (2/8).

## Im Spiel

- Par steht je Bahn in den Bahndaten (`par` in `assets/courses/*.json`);
  `tools/generate_assets.py` erzeugt daraus `course_par` (18 Bytes) und die
  Summe für die Endwertung.
- Die Statuszeile zeigt `BAHN n PAR p` links, den Ladebalken ab Spalte 15
  und `PUNKTE` rechts; die Endwertung `PAR 49` links und `SUMME` rechts.
- Ändert sich eine Bahn, Solver erneut laufen lassen und Par nach der
  Regel oben prüfen.
