# Physik: Konstanten, Regeln und Nachweis

Stand 2026-10-06. Grundlage ist [SPEC.md](../SPEC.md), Abschnitt „Physik“.
Dieses Dokument hält die kalibrierten Konstanten fest, beschreibt, wie der
6502-Kern einen Simulationsschritt rechnet, und belegt die
Abnahmekriterien mit Messwerten.

## Konstanten

| Größe | Wert | Quelle |
|---|---|---|
| Simulationsschritt | 1/50 s, ein Schritt je PAL-Bild | `physics_tick` |
| Position | x Q16.8 (24 Bit), y Q8.8 | `BALL_POS_X/Y` |
| Richtung | Einheitsvektor Q1.8 aus 128 Richtungen | `UNIT_X/Y`, `unit_cos` |
| Geschwindigkeit | `SPEED` in 1/256 px je Bild, Stärke × 32 | `start_shot` |
| Höchstgeschwindigkeit | 1024 = 4 px je Bild (Stärke 32) | |
| Rollbremsung | 4/256 px je Bild² (`ROLL_DECEL`) | `memory.inc` |
| Stillstand | `SPEED` ≤ 4: Ball steht exakt | |
| Ballradius | 2 px (`BALL_RADIUS` 512) | |
| Wand-Epsilon | 2/256 px Spalt werden als Berührung gewertet | `try_line` |
| Kontakte je Bild | höchstens 4 (`MAX_CONTACTS`) | |
| Eckpunkt-Zeitauflösung | 1/16 Bild (`CIRCLE_MIN_BIT` 16) | |
| Banden-Verlust | `SPEED` · d² · 31/512 + `SPEED`/128 + 1, d = u · n | `reflect_speed_loss` |
| Lochfang | Radius 3 px, nur bei `SPEED` ≤ 192 (0,75 px je Bild) | `test_cup` |
| Lochrand | unter 5,5 px Abstand: 1/64 rad je Bild zum Loch, Reibung `SPEED`/128 + 1 | `cup_rim` |

Reichweite auf freier Fläche: etwa Stärke²/2 Pixel (Stärke 8: 32,5 px,
16: 129 px, 32: 514 px); der Ball rollt Stärke × 8 Bilder.

## Ein Simulationsschritt

1. `VELOCITY` = `SPEED` · `UNIT` je Achse, auf die nächste Q8.8-Einheit
   gerundet.
2. Broadphase: Segmente, deren Rechteck ±8 px um den Ball liegt.
3. Kontinuierlicher Sweep über den Rest des Bildes: früheste Berührung mit
   einer Wandfläche (exakt, 1/256 des Reststücks) oder einem freiliegenden
   Eckpunkt (Halbierungssuche, letzter Punkt außerhalb, 1/16 Bild).
4. Lochfang nur unterhalb der Fanggeschwindigkeit und nur vor dem
   Wandkontakt; die Prüfung folgt dem Weg, nicht nur dem Endpunkt.
5. Reflexion, Geschwindigkeitsverlust, Reststück; höchstens vier Kontakte.
6. Wasser, Lochrand (nur in Bildern ohne Wandkontakt), Rollbremsung.

### Kontaktregeln

- **Wandflächen** spiegeln exakt: Achsen über das Vorzeichen, 45° über den
  Komponententausch. Im Reststück nach so einem Kontakt behält `VELOCITY`
  die alte Geschwindigkeit (höchstens 0,28 px Unterschied zur exakten
  Rechnung); ab dem nächsten Bild gilt der neue Betrag.
- **Eckpunkte**: Die Normale kommt aus dem Versatz zum Eckpunkt am letzten
  Punkt außerhalb. `vertex_normal` normiert ihn über |Versatz|² (Tabelle
  `normal_scale`, 48 Stufen) auf 0,98 ≤ |n| < 1. Ein Eckpunkt konkurriert
  mit dem spätesten Zeitpunkt seines 1/16-Bild-Fensters, damit eine in
  diesem Fenster erreichte Wandfläche gewinnt; der Ball rückt trotzdem nur
  bis zum sicheren Punkt außerhalb vor (`BEST_MOVE`).
- **Gleichzeitige Kontakte**: dieselbe 1/256-Stufe des Reststücks. Zwei
  Wandflächen mit 45° Normalenunterschied werden gemeinsam an der Normalen
  auf halbem Winkel reflektiert (`joint_normal`); senkrechte Wandpaare
  nacheinander, was dort dasselbe ergibt.
- **Kontaktlimit**: Nach vier Kontakten verwirft der Kern den Rest des
  Bildes und zählt `CONTACT_LIMIT_HITS`.

## Nachweis

### Unabhängige Referenz

[tests/physics_reference.py](../tests/physics_reference.py) rechnet die
SPEC-Regeln in Gleitkomma, allein aus den Bahnkonturen (JSON). Sie teilt
keinen Code und kein Festkommaformat mit dem Kern.

[tests/physics_check.py](../tests/physics_check.py) lässt den echten
6502-Kern in py65 Bild für Bild laufen. Für jedes Bild startet die Referenz
vom Zustand des Kerns und sagt das Bildende voraus; so schaukeln sich
Abweichungen nicht über viele Banden auf. Außerdem prüft jeder Schritt:

| Prüfung | Grenze |
|---|---|
| Eindringen in eine Wand | Mittelpunkt mindestens 2 − 3/256 px von jeder Wand |
| Tunneling | Mittelpunkt bleibt auf spielbarer Fläche |
| Energiegewinn | weder `SPEED` noch `SPEED` · \|u\| wächst |
| Kontaktlimit | `CONTACT_LIMIT_HITS` bleibt 0 |
| Zittern | kein dreimaliges Hin und Her um höchstens 1 px in 16 Bildern |
| Steckenbleiben | schneller als 1/4 px je Bild, aber weniger als 1 px Weg in 16 Bildern |
| Wasser | danach in Ruhe, Mittelpunkt auf trockenem Boden |

Toleranzen für den Vergleich mit der Referenz, nach Bildart:

| Bildart | Lage | Richtung | `SPEED` | Begründung |
|---|---:|---:|---:|---|
| frei | 1,5/256 px | 0,01° | 0 | Rundung der Geschwindigkeit je Achse |
| Lochrand | 2/256 px | 0,2° | 1 | Drehung je Komponente gerundet |
| Lochrand, Loch genau voraus | 2/256 px | 2° | 1 | Seitentest unter 2/256 px: beide Drehrichtungen richtig |
| Wandfläche | 0,31 px | 0,05° | 3,5 | Reststück mit alter Geschwindigkeit (≤ 0,28 px), Rundung |
| Doppelkontakt 135° | 0,3 px | 1° | 4 | halbe Normale ·255/256 |
| Eckpunkt | 0,75 px | 5° | 5 | gegen den um ≤ 1/4 px quer verschobenen Ball |
| Grenzfall | 0,3 px | – | – | Berührung am Bildende oder Streifen innerhalb 1/32 px; Lochfangkreis innerhalb 1/16 px |

Ein streifender Eckentreffer dreht den Ball um bis zu 3,2 rad je Pixel
Versatz. Der Kern reflektiert am letzten Versatz Q außerhalb des Kreises.
Das ist genau die Reflexion desselben Balls auf einer um |Q| − 2 px quer
verschobenen Bahn; |Q| − 2 ist höchstens 1/4 px (1/16 Bild bei 4 px je Bild)
und bei streifenden Treffern viel kleiner. Deshalb gilt für Eckpunkte: Der
Kern muss der exakten Physik eines Balls entsprechen, der höchstens 1/4 px
quer zu seiner Bahn verschoben ist. Die Normale in der Fenstermitte wäre
genauer, lässt den Ball bei streifenden Treffern aber erneut auf denselben
Eckpunkt laufen (zweiter Kontakt, bis 23800 Zyklen); verworfen. An der
Spitze einer V-Kerbe würde die verschobene Bahn schon die Nachbarwand
treffen; dort bleiben bis 4,4° Richtungsabweichung (Grenze 5°), die Lage
weicht höchstens 0,58 px ab (Frontaltreffer: 1/4 px früh, |n| < 1 und
Reststück).

### Sweep über alle Bahnen

`make physics` (Optionen `HOLES`, `STRIDE`, `SPACING`) schlägt auf allen
18 Bahnen vom Abschlag und von einem 16-px-Raster spielbarer Punkte aus in
jede 4. Richtung mit den Stärken 4, 12, 22 und 32 und rollt jeden Ball bis
zum Stillstand. Bericht: `build/physics-sweep.json`.

Ergebnis 2026-10-06 (Stand dieses Commits): 188 288 Schläge, 21,7 Mio.
Bilder, **keine Verletzung**: kein Eindringen, kein Tunneling, kein
Energiegewinn, kein Kontaktlimit, kein Zittern, kein Steckenbleiben. Je
Bild höchstens 2 Kontakte (35 Bilder), 8755 Bilder mit einem Kontakt.

| Bildart | größte Abweichung Lage / Richtung / `SPEED` |
|---|---|
| frei | 0,003 px / 0° / 0 |
| Lochrand | 0,003 px / 0,15° / 0,99 |
| Lochrand, Loch genau voraus | 0,003 px / 1,9° / 0,99 |
| Wandfläche | 0,30 px / 0° / 3,3 |
| Eckpunkt (nach Verschiebung) | 0,58 px / 4,4° / 2,7 |
| Grenzfall | 0,10 px |

Teuerstes Physikbild auf den echten Bahnen: 18169 py65-Zyklen (Bahn 11),
im VICE-Smoke-Test schlechtestes Bild 31028 von 32000 Ticks.
Laufzeit des Sweeps: rund 20 Minuten auf 12 Kernen.

### Gezielte Tests

[tests/test_physics_safety.py](../tests/test_physics_safety.py), dazu
`tests/test_physics.py` und die Wassertests in `tests/test_runtime.py`:

| SPEC-Kriterium | Test |
|---|---|
| Bitidentische Wiederholung | `ReplayTests`: Joystick-Eingaben aller 18 Lösungswege durch Abfrage, Entprellung, Steuerung und Physik; SHA-256 über jeden Bildzustand |
| Reichweite ±2 %, Richtung ≤ 1° | `ReachTests`: 8 Achsen/Diagonalen bei allen 32 Stärken, alle 128 Richtungen bei 2, 13, 32 |
| Wände ≤ 1°, kein Anstieg | `WallTests`: alle 8 Wandrichtungen, alle anlaufenden Winkel bis 2,3° flach, drei Stärken |
| Kein Tunneling | 2-px-Leiste bei Höchstgeschwindigkeit aus 16 Subpixel-Lagen |
| Segmentende, Außenecken | `CornerTests`: Quadrat- und Rautenspitzen, Stoßparameter quer über den Ball |
| Innenecken, Doppelkontakte | 90°- und 135°-Ecken; Diagonale in die 90°-Ecke kommt gerade zurück |
| 10-px-Engstellen | `PassageTests`: 10-px-Gang; Validator und Editor lehnen engere Stellen ab |
| Kontaktlimit sichtbar | `ContactLimitTests`: 4-px-Spalt erzwingt das Limit, Ball bleibt drin und kommt zur Ruhe |
| Lochfang | `CupTests`: langsam aus 32 Richtungen, schnell darüber, Sehne innerhalb eines Schritts |
| Eckennormale | `VertexNormalTests`: \|n\| ≤ 1, ≥ 0,978, radial ≤ 0,6°; Reflexion ohne Gewinn |

## Reichweite und Richtung (gemessen)

Freie Fläche, Strecke bis zum Stillstand:

| Stärke | Reichweite | 8 Richtungen: Spanne / Richtung | 128 Richtungen: Spanne / Richtung |
|---:|---:|---:|---:|
| 1 | 0,56 px | 0,17 % / 0,00° | 2,16 % / 0,80° |
| 2 | 2,1 px | 0,17 % / 0,00° | 1,09 % / 0,43° |
| 4 | 8,3 px | 0,07 % / 0,02° | 0,74 % / 0,19° |
| 8 | 32,5 px | 0,02 % / 0,01° | 0,48 % / 0,17° |
| 16 | 129 px | 0,02 % / 0,00° | 0,46 % / 0,15° |
| 32 | 514 px | 0,01 % / 0,00° | 0,45 % / 0,15° |

Die SPEC-Grenzen (2 %, 1°) gelten für Achsen und Diagonalen bei jeder
Stärke; bei allen 128 Richtungen ab Stärke 2 (Stärke 1 rollt 0,6 px).

## Korrekturen vom 2026-10-06

Der Vergleich mit der Referenz hat im Kern gefunden und behoben:

1. **Energiegewinn an Ecken.** Die Eckennormale Q · 127/256 setzte
   |Q| ≤ 516 voraus; seit der Halbierungssuche auf 1/16 Bild ist |Q| bis
   2,26 px. Folge: |n| bis 1,06 gemessen (1,12 möglich), |u| nach dem
   Abprall bis 1,22 und bis zu 13 % mehr effektive Geschwindigkeit an
   Ecken (Bahn 14). Jetzt normiert `vertex_normal`.
2. **Falscher Kontakt.** Ein Eckpunkt, auf 1/16 Bild vorverlegt, schlug
   eine tatsächlich zuerst getroffene Wandfläche (bis 24° Richtungsfehler).
   Jetzt konkurriert der Eckpunkt mit dem Ende seines Zeitfensters.
3. **Asymmetrische Geschwindigkeit.** `VELOCITY` wurde je Achse abgerundet;
   negative Komponenten wurden dadurch betragsmäßig größer. Schwache Schläge
   streuten bis 9,7 % in der Reichweite und 3° in der Richtung. Jetzt
   gerundet: höchstens 0,17 % und 0,02° auf Achsen und Diagonalen.
4. **Gleichzeitige Kontakte.** Ein Ball genau in eine 135°-Ecke prallte je
   nach Segmentreihenfolge 90° verschieden ab. Jetzt gemeinsame Auflösung.
5. **Scheinkontakte im Reststück.** Nach einem Kontakt kurz vor Bildende
   wurde der winzige Rest-Schritt abgerundet; aus −0,35/256 wurde −1/256,
   ein scheinbarer Anlauf an die eben verlassene Wand. Der Ball „prallte“
   viermal zur Zeit 0, verlor Geschwindigkeit und erschöpfte das
   Kontaktlimit (Bahn 9). Jetzt wird zur Null hin abgeschnitten.
6. **Richtung über 1 nach dem Lochrand.** Die Randdrehung konnte eine
   Komponente auf ±257/256 heben, die `multiply_unit` nicht kennt. Jetzt
   auf ±256 begrenzt wie bei der Reflexion.

Damit das Zeitbudget hält, rechnet `multiply_fraction` das 8×8-Produkt über
eine Quadrattabelle (ab = (a² + b² − (a − b)²)/2, `square_lo/hi` mit 256
Einträgen, +256 Bytes). Kontaktbilder werden dadurch 1100–1700 Zyklen
schneller, und die Normierung der Eckennormale ist bezahlt.

## Grenzen

- Eckpunkt-Kontakte sind auf 1/16 Bild genau; das entspricht einem
  Querversatz des Balls von höchstens 1/4 px. Feiner (1/32) kostet je
  Eckensuche eine weitere Halbierung (rund 300 Zyklen) und passt derzeit
  nicht ins Zeitbudget.
- Die Eckennormale ist 0,98 bis 1 lang: Eckenabpraller verlieren bis zu
  4 % mehr Normalanteil als exakt, gewinnen aber nie. Der Richtungsvektor
  bleibt danach bis zum nächsten Schlag etwas kürzer als 1.
- py65 misst Zyklen, nicht TED-Takt; das Zeitbudget gilt nach dem
  VICE-Smoke-Test (`make smoke`).
