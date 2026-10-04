# Fortsetzung nach dem Clear — 2026-10-04

## Auftrag und Arbeitsweise

C16-Minigolf in ACME/6502 für unveränderte 16 KB: monochromes 320×200-Hi-Res, reine 2D-Draufsicht, geometrische breite und schmale Bahnen, Ecken, pixelgenaue Bewegung, deterministische Festkommaphysik, 128 Richtungen, 32 Stärken, später 18 Löcher und kurze lustige Effekte. SPEC.md und TODO.md sind maßgeblich. Schrittweise vorgehen; Schritt 2 erst nach vollständiger Abnahme schließen. Conventional Commits verwenden. Commit und Push sind vom Nutzer bereits autorisiert.

Schritt 1 ist abgeschlossen. Der Nutzer hat A/D/W/S/SPACE/P in VICE bestätigt. Schritt 2 hat einen spielbaren Physikkern, bleibt aber offen. Keine vollständige 18-Loch-Runde, Materialien, Wertung oder Effekte implementiert. Reale C16-Hardware ist ungeprüft.

## Letzte Frage: schnellste Multiplikation und Division?

Antwort: Nein, ein Vergleich aller geeigneten Algorithmen fehlt. Vorhanden sind spezialisierte schnelle Pfade und eine exakte binäre Bruchdivision. Keine Behauptung eines global optimalen Verfahrens machen.

| Routine und Beispiel | Gemessene CPU-Zyklen |
|---|---:|
| multiply_signed(724, 181) | 580 |
| multiply_unit(724, 181) | 368 |
| multiply_fraction(724, 181) | 324 |
| multiply_signed(-724, 181) | 630 |
| multiply_unit(-724, 181) | 428 |
| multiply_fraction(-724, 181) | 375 |
| multiply_signed(1024, 256) | 476 |
| multiply_unit(1024, 256) | 51 |
| multiply_fraction(1024, 128) | 132 |
| divide_fraction(150, 724) | 528 |
| divide_fraction(1000, 1024) | 590 |
| divide_fraction(100000, 200000) | 340 |

Einzelmessungen am assemblierten Code mit py65; einschließlich RTS und interner JSR, ohne äußeren JSR. Keine TED-Buswartezeiten, keine bewiesenen Worst-Case-Grenzen und kein Vergleich alternativer Algorithmen. multiply_fraction hat einen anderen Ergebnisvertrag als die beiden vollständigen Multiplikationen; deren Zeiten sind daher nicht unmittelbar austauschbar.

- src/wide_math.asm: multiply_signed liefert vorzeichenbehaftetes 16×16→32-Bit-Produkt durch Shift/Add; divide_fraction liefert floor(256·Zähler/Nenner) für positive 24-Bit-Werte mit Zähler kleiner Nenner.
- src/math.asm: multiply_unit liefert das exakte volle Produkt für Richtungsfaktoren mit Betrag höchstens 256, einschließlich direktem Shift bei 256. multiply_fraction nutzt begrenzte Operanden (B unsigned 8 Bit, Betrag A höchstens 2048) und liefert das skalierte, abgerundete Ergebnis; interne Produktbytes werden auch vom Unit-Wrapper genutzt.
- Nächste Mathematikarbeit: Aufrufer/Wertebereiche erfassen, reproduzierbare Zyklusmessmatrix und Alternativen vergleichen. Insbesondere 16-Bit-Bruchdivision für geeignete Aufrufer untersuchen, ohne die weiterhin nötige allgemeine 24-Bit-Division zu ersetzen. Codegröße gegen Laufzeit abwägen. Pixelgenauigkeit, Vorzeichen und festgelegte Rundung erhalten; keine ungemessenen Geschwindigkeitsversprechen.

## Offene Budgets und nächste Reihenfolge

- 40 Tests bestanden (33 Kern-, sieben Host-Tests). make smoke scheitert derzeit absichtlich am offenen Zeitbudget: schlechtester geprüfter schräger Eckentreffer 40900 PAL-Ticks; Ziel höchstens 32000, gemessene Frameperiode 35573. Keine bestandene Laufzeitabnahme behaupten.
- Haupt-Runtime 5571 Bytes, nur sieben Bytes frei. Kompakter Host-Testexport 39 statt 85 Bytes. 18 gleich große Exporte plus Verzeichnis wären 738 Bytes; bereits 731 Bytes fehlen, Decoder und Metadaten noch zusätzlich. Das ist eine Hochrechnung, keine Sammlung von 18 fertigen Bahnen.
- Zuerst Speicherarchitektur mit mindestens 1 KB zusätzlichem nutzbarem Platz planen/umsetzen und geschützte Bitmapbereiche sauber ausweisen. Kein 64-KB-Modell, kein Multicolor. Danach allgemeinen schrägen Kreis-Sweep beschleunigen; Mathematikbenchmark darin berücksichtigen. Anschließend ACME-Decoder, Kontakt-/Restbewegungsgrenzen und echte 18-Bahnen-Speicherabnahme. Einzelheiten in TODO.md.
- Kompakter Export und Host-Decoder existieren in tools/course_codec.py; ACME verwendet noch expandierte Segmente. Ballrenderer ist byteweise optimiert, 21-Pixel-Form und sämtliche acht Ausrichtungen geprüft.

## Befehle und Emulatorhinweis

make, make test, make budget; make run für VICE. Buildberichte: build/memory.json, build/course-budget.json, build/timing.json. ACME und VICE liegen unter /opt/homebrew/bin. Python/py65 ist in .venv verfügbar.

Falls VICE beim Start aus dem Python-Smokeprozess in der eingeschränkten Umgebung abstürzt, getrennte Tool-Aufrufe verwenden:

1. python3 tests/vice_smoke.py --prepare-only
2. /opt/homebrew/bin/xplus4 -silent -default -console -model c16 -pal -ramsize 16 -sounddev dummy -warp -autostartprgmode 1 -autostart build/minigolf.prg -initbreak 0x0200 -moncommands build/vice-pal.mon -monlog -monlogname build/vice-pal.log -limitcycles 20000000
3. python3 tests/vice_smoke.py --verify-only

Letzte Implementierungscommits vor dieser Übergabe: 4bcaca9 (Renderer/Eckensweep), 9552c5d (Export/RAM-Bericht), beide auf main gepusht. Remote: git@github.com:phausser/c16-minigolf. Dokumentationsänderungen separat semantisch committen und pushen. Nach dem Clear zuerst git status prüfen, diesen Stand sowie TODO.md/SPEC.md lesen und keine erledigten Arbeiten wiederholen.

## Reproduzierbarer Benchmark (2026-10-04)

`make benchmark` implementiert jetzt eine feste Matrix mit 436 gegen
ganzzahlige Referenzen geprüften Rechenfällen. Bericht:
`build/math-benchmark.json`. CPU-Zyklen ohne TED-Wartezeiten:

| Routine | Fälle | Minimum–Maximum |
|---|---:|---:|
| multiply_signed | 156 | 87–741 |
| multiply_unit | 156 | 51–493 |
| multiply_fraction | 91 | 50–405 |
| divide_fraction | 33 | 287–711 |

Die Matrix ist kein erschöpfender Worst-Case-Nachweis. Alle 40 Tests
bestehen; Speicher- und PAL-Laufzeitabnahme bleiben offen.

## Aktueller Stand nach Divisionsoptimierung

SPEC.md und TODO.md liegen auf Wunsch des Nutzers wieder im Projektroot.
README enthält nur Kurzbeschreibung, Bedienung, Build und Dokumentationslinks.
`divide_fraction` besitzt jetzt einen 16-Bit-Pfad für Nenner <32768 sowie
einen kompakteren 24-Bit-Pfad. M_TRIAL, X und Y sind Scratch. 40 Tests und
448 Benchmarkfälle bestehen. Geschützte HUD-Arithmetik: 308 statt 287 Bytes;
Runtime weiterhin 5571 Bytes, sieben frei. VICE misst maximal 40581 Ticks
(zuvor 40900), die 32000-Tick-Abnahme scheitert weiterhin. Messdetails in
hardware.md. Die Kapazität bleibt eine eingebaute Testbahn, keine zusätzliche.
Spielfeldmaße bleiben vorerst unverändert; Speicherarchitektur noch offen.

## Fortsetzung nach Codeverkleinerung

Unveränderte Spielfeldmaße. Haupt-Runtime 5436 Bytes, 142 frei (135 Bytes
gewonnen). Heiße Arithmetik bleibt inline; gemeinsame Negationen nur in
selteneren Physikpfaden. Achsennormierung und -reflexion sowie der Vergleich
fester Kreisradien sind verkleinert. 42 Tests und 448 Benchmarkfälle bestehen.
PAL-Worst-Case 40542 Ticks: Abnahme weiterhin offen. `make budget` nennt
jetzt auch die rein rechnerische Zusatzkapazität: drei weitere gleich große
Geometrien mit Zeigern, ohne Decoder, aktuelle-Bahn-Reserve und Metadaten.
18-Geometrien-Hochrechnung: 738 Bytes, davon 596 noch nicht gedeckt.
Als Nächstes größere Codeblöcke verkleinern bzw. den kompakten Decoder
mit getrennter aktueller Bahn einpassen. Keine Bahnkapazität freigeben,
bevor der tatsächliche gesamte RAM-Vertrag nachgewiesen ist.
