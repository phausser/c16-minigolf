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

## Aufrufprofil und direkter Kreisvergleich

`make profile` ist implementiert (tools/profile_sweep.py), Bericht
build/sweep-profile.json. Inclusive-Zeiten überlappen; exklusive Zeiten
teilen die gemessene reine CPU-Zeit auf, ohne TED-Stalls/Rendering.
Schräge Worst-Case-Physik: 25255 -> 24974 CPU-Zyklen. VICE-Worst-Case:
40542 -> 40247 Ticks; Grenze 32000 weiter überschritten.
Die exakte Kreisprüfung verwendet jetzt square_circle mit früher Ablehnung
einer Achsenkomponente >=Radius, statt voller Quadratsumme und separatem
Vergleich. Scratch/Product-Ausgaben sind unspezifiziert; QX/QY bleiben
unverändert. Vertrag |QX|,|QY|<=2815 und Radius 512/768.
43 Tests und 448 Mathematikfälle bestehen. tests/fixtures/corner-replays.json
sichert die Zustände aus c01f930 vor der Änderung für drei Eckenszenarien
über sieben Frames. Haupt-Runtime 5480 Bytes, 98 frei; 18-Geometrien-Lücke
640 Bytes plus Decoder/Metadaten. Diese Optimierung kostet 44 Bytes.
Nächster Fokus laut Profil: Bruchmultiplikationen, genaue Kreis-Suche und
Normalisierung; aktuelle Ergebnisse allein rechtfertigen keine PAL-Abnahme.

## Graue Spielflächen mit Zellschatten

Auf Nutzerwunsch vor der Speicheroptimierung umgesetzt: mittelgraue
spielbare Flächen, schwarze nichtspielbare Flächen/Hindernisse und
8×8-Dunkelgrau-Zellen an oberen/linken Innenkanten. Hi-Res bleibt 320×200,
kein Multicolor. Ball, Zielmarke und Lochring schwarz; HUD weiß auf Schwarz.
SPEC erlaubt jetzt wechselnde Zellfarben und diesen Schatten.

Der statische Renderer füllt mit Even/Odd-Scanlines byteweise aus denselben
Konturen wie die Kollision. Neun zusätzliche Füllkanten kosten 36 Bytes.
Initialisierung muss vor draw_course erfolgen (schwarze Bitmap als Basis).
Zellschatten verwenden Top-left-Abtastung der aktuellen, oberen und linken
Zelle; danach wird der Lochring gezeichnet. Keine Zusatzbitmap im RAM.

43 Tests bestehen, auch unabhängige punktweise Geometrie-/Zellfarbenprüfung
und Schutz der Codezeilen. VICE-Screenshots: build/vice-pal.png und -aim.png.
Grafik-/Eingabeabnahme besteht; make smoke endet am bekannten Physikbudget:
40250 > 32000 Ticks (Frameperiode 35573), Anzeige/Steuerung maximal 16832.
Runtime 5541 Bytes, 37 frei, statischer Renderer 319/320 Bytes, Bitmap-Ende
183/192 Bytes. PRG 12280 Bytes. 18-Geometrien-Hochrechnung 738 Bytes:
701 Bytes fehlen, zusätzlich Decoder, aktuelle Bahn/Füllkanten, Metadaten.
Nächster Schritt bleibt Speicherarchitektur; keine Bahnproduktion freigeben.

Farben sind jetzt zentral in src/palette.inc als (LUMINANZ << 4) + FARBE
konfiguriert. Hi-Res-Attributbytes werden daraus abgeleitet; Fläche und
Schatten teilen sich den Farbton. Build besteht, Bildpalette unverändert.
PRG jetzt 12282 Bytes, Bitmap-Ende 185/192 Bytes; Runtime weiter 5541/37.

## Schatten auf Nutzerwunsch entfernt

Aktueller Stand ersetzt die Schattenbeschreibung oben: keine Schatten im
Kurs. Flächen gleichmäßig, Nutzereinstellung COURSE_SURFACE_COLOR =
(5 << 4) + 1 bleibt erhalten. COURSE_SHADOW_COLOR und shade_course entfernt.
initialise_course_colors liegt jetzt mit dem statischen Renderer in Zeile21
und initialisiert Luminanz/Farbton der 800 Spielfeldzellen, ohne Code/HUD.
43 Tests bestehen; VICE-Bild und Grafik/Eingabeprüfung ebenfalls. Runtime
5516 Bytes, 62 frei; statischer Renderer einschließlich Paletteninitialisierung
239/320 Bytes. PRG weiter 12282 Bytes. Physikmaximum 40253 > 32000 Ticks.
Kurs-Hochrechnung: 676 Bytes fehlen plus Decoder/aktuelle Bahn/Metadaten.
Nächster Schritt bleibt die Speicherarchitektur.

## Weiße Markierungen, gemusterte Fläche

Auf Nutzerfreigabe nun 50%-Schachbrettmuster statt echter grauer Zellfarbe.
Hi-Res bleibt 320×200; alle Spielfeldzellen Weiß auf Schwarz. Palette:
COURSE_INK_COLOR = (7 << 4) + 1, COURSE_SOLID_COLOR = (0 << 4) + 0.
COURSE_SURFACE_COLOR entfällt. Ink färbt Ball/Zielmarke/Lochring UND Muster;
Flächenhelligkeit folgt der Musterdichte, nicht einer eigenen TED-Farbe.
course_pattern = $aa,$55, fill_byte XOR maskiert mit Zeilenparität.
Keine Schatten, keine zusätzliche Bitmap. 43 Tests und VICE-Grafikprüfung
bestehen. Runtime 5516 Bytes, 62 frei; Renderer inkl. Palette/Muster 253/320.
PRG 12282 Bytes. Physikmaximum weiterhin 40253 > 32000 PAL-Ticks.
Vorschau build/vice-pal.png. Nächster Schritt weiterhin Speicherarchitektur.

## Glatte graue Fläche wiederhergestellt, Zellfarben als Kompromiss

Aktueller Nutzerwunsch ersetzt das Muster: glatte Fläche, keine Schatten.
COURSE_SURFACE_COLOR=(5 << 4)+1 wieder vorhanden, INK weiß, SOLID schwarz.
Alle acht statischen Bitmapbytes einer Zelle werden vor dem Lochring geprüft:
alle null => vollständig spielbar => Vordergrund Weiß; sonst Schwarz.
Hintergrund immer Grau. Ball/Zielmarke/Lochring übernehmen die Zellfarbe,
am Übergang teilweise weiß/schwarz. Auch unrasterige gerade Kanten bleiben
exakt schwarz. initialise_video füllt Bitmap $ff, draw_course öffnet Fläche,
initialise_course_colors klassifiziert, danach cup. Keine laufenden
Attributänderungen; restore_dynamic bleibt unverändert.
44 Tests bestehen, VICE-Grafik/Eingabeprüfung ebenso. Runtime 5516 Bytes,
62 frei; Renderer/Palette 287/320, Bitmap-Ende 182/192, PRG 12279 Bytes.
Physikmaximum 40253 >32000 weiter offen; gespeicherte Replays unverändert.
Nächster Schritt bleibt Speicherarchitektur. build/vice-pal.png zeigt das Bild.

## Rasterkonturen und Joystick-Aufladung

Alle drei aktuellen Nutzerwünsche umgesetzt: gerade Konturen auf 8×8-Raster,
Joystick Port1 links/rechts dreht die 128 Richtungen, Feuer halten lädt 1..32
alle zwei Frames, Loslassen schlägt. P bleibt Pause; A/D/W/S/SPACE entfernt.
Nur Stärke im HUD, keine Anleitung/Status. POWER idle=0, CHARGING/CHARGE_TICKS
in $2e/$2f, FIRE_LOCK=$4d; STATE_END jetzt $4e. Pause verwirft Aufladung;
gehaltenes Feuer während Rollen/Pause/Neustart bis Release gesperrt.
Rasterbahn x196→200, y84→88, Engstelle16px. Hostvalidator erzwingt Raster
bei geraden Kanten. Originalbahn tests/fixtures/course-before-cell-grid.json
hält die alten corner-replays unverändert prüfbar (explizite historische Länge).
47 Tests bestehen. tests/vice_joystick.py prüft echte VICE-TED-Joystick-Abfrage
über binären Monitor/I-O-Simulation, 64 Feuerframes, Release und leeres HUD.
Protokoll benutzt Port0 für physischen Port1, aktiv niedrige Leitungen;
Testgerät JOYPORT_ID_IO_SIMULATION=37. Build/joystick-smoke.json bestanden.
make run standardmäßig -joydev1 1 (NumPad), JOYDEV=4 für erstes Hostgerät.
Runtime5381 Bytes,197 frei; Renderer287/320; Bitmap-Ende182/192; PRG12279.
VICE-Smoke Grafik/Eingabe bestanden, Zeitbudget38873>32000 weiterhin offen.
Neue Szenarien Ecke124,84 / schräg124,83 / flach123,84, Engstelle160,80.
Profil-Szenarien angepasst. Keine Physikbeschleunigung behaupten, da Kurs und
HUD geändert. Speicherarchitektur und kompakter ACME-Decoder bleiben nächste
Arbeit; 18-Geometrien-Schätzung702,505 fehlen plus Decoder/Metadaten.

## Speicherarchitektur, Phase A/B (2026-10-05)

Zeile 22 (frühere Bedienhilfe) ist jetzt schwarz/schwarz versteckt; Zeilen
21–23 bilden einen Codeblock $3A40–$3DFF mit Renderer, weiter Mathematik,
Normierung und Eingabemodul (873/960 Bytes). clear_hud_bitmap löscht nur
noch Zeile 24. Die drei DYNAMIC-Arrays liegen in $0100–$0135 (Kopierer wird
nur beim Start gebraucht), Stack ab $01C0 reserviert, gemessene Tiefe
12 Bytes, Test erzwingt höchstens 32. RUNTIME_LIMIT = $1800.
Runtime 5097 Bytes, 535 frei (vorher 197); dazu 138 Bytes Stackseite für
flüchtige Puffer (z. B. entpackte aktuelle Bahn) und 87 versteckte Bytes.
48 Tests, VICE-Grafik und Joystick bestehen; Bild unverändert. Physik
38821 > 32000 Ticks weiter offen. make budget: Geometrie allein braucht noch
167 Bytes plus Decoder/Metadaten.
Spalten 0 und 39 bleiben auf Nutzerwunsch frei: der ganze Bildschirm soll
für Bahnen verfügbar bleiben. Keine Daten im Rand verstecken. Weitere Reserve
aus Codeverkleinerung, Stackseite, Attributlücken ($1BE8/$1FE8, je 24 Bytes)
und Zero Page gewinnen.

## ACME-Bahn-Decoder (2026-10-05)

Format 2 ohne Versionsbyte: Start/Loch halbiert, Konturanzahl, je Kontur
x/2, y/2 mit Bit 7 = Normalenseite, Laufanzahl, Läufe. decode_course
(src/course_decoder.asm, X = Bahnindex) entpackt nach course_segments
$0100–$019F, berechnet Normalen und versteckte Endpunkte aus Richtungswechseln
(Vorgänger der ersten Kante = letzter Lauf). Start/Loch in $f8–$ff
(Low-/High-Bytes getrennt), COURSE_CUP_HALF_X $aa, SEGMENT_BYTES $ab.
DYNAMIC-Arrays jetzt $01A0–$01D5, Stack ab $01D6 (42 Bytes, Tiefe 12).
initialise_state ruft decode_course für Bahn 0. Füllkanten werden im
Zeichner aus Segmenten abgeleitet, keine gespeicherten Füllkanten mehr.
Python-decode lehnt nichtkanonische Streams ab (Re-Encode-Vergleich).
50 Tests (Decoder gegen expanded_segments, auch Diagonalen/Hindernisse/
konkave Ecken), VICE-Grafik und Joystick bestehen; Physik 38811 > 32000.
Runtime 5288 Bytes, 344 frei; Decoder ca. 270 Bytes. make budget: 17 weitere
Testbahn-Größen brauchen 646 Bytes, es fehlen 302 plus Metadaten.
Nächste Reserven ohne Bildrand: Codeverkleinerung (collision.asm ~2 KB),
Attributlücken $1BE8/$1FE8, Rest in versteckten Zeilen (59) und Bitmap-Ende.

## Laufzeitoptimierung, Stand 2026-10-05

Bitgenau (alle Replays unverändert): circle_entry-Nachprüfung entfällt
(CIRCLE_OUT ist exakt), Teilprodukte im Akku (multiply_fraction,
multiply_signed in zwei Bytedurchläufen), vorberechnete Broadphase-Grenzen,
sqrt_speed mit 24-Bit-Schieben, square_small-Kreuzterm im Akku, entrollte
Delta-Halbierung, Ballzeichner mit einmaliger Adresse/Maske,
save_dynamic_byte mit Y-Offset, kürzere Restaurierungsschleife.
Profil Winkel 17 (VICE-Fall): Physik 23672 -> 19906 Zyklen; VICE 38811 ->
33210 Ticks (Grenze 32000). ACHTUNG: VICE misst das Eckenszenario nur bei
Winkel 17. py65 über 128 Winkel: schlechtester Fall Winkel 100 (124,83)
mit 22619 Physikzyklen, dort zwei vollständige Kreis-Suchen (~4800 je).
Grob: 32000 Ticks entsprechen ~18800 Physikzyklen; es fehlen ~3800.
Runtime 5309 Bytes, 323 frei. Messskripte: Histogramm nach Label und
Winkel-Sweep (nicht im Repo; profile_sweep.profile_call wiederverwenden).
