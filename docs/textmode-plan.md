# Plan: Umstieg vom Hi-Res-Bitmap- auf den TED-Textmodus

Stand 2026-10-05, **umgesetzt** (Ergebnis siehe TODO.md und docs/hardware.md). Ziel: rund 5–7 KB RAM freimachen, ohne dass sich das Bild
ändert. Physik, Bahnformat, Editor, Sound und Spielablauf bleiben unverändert.
Die SPEC verlangt für einen Architekturwechsel eine ausdrückliche
Entscheidung; dieser Plan ist die Grundlage dafür.

## Ausgangslage

| | Bitmap (heute) | Textmodus |
|---|---:|---:|
| Bild | 8000 Bytes Bitmap | 1000 Bytes Zeichencodes |
| Farben | 2000 Bytes (Vorder- und Hintergrund je Zelle) | 1000 Bytes (Vordergrund je Zelle) |
| Zeichensatz | – (Schrift aus dem ROM) | 1024 Bytes (128 Zeichen im RAM) |
| **Summe** | **~10 KB** | **3 KB** |

Heute stecken ~1,5 KB Code und Daten versteckt in der Bitmap (Zeilen 0,
21–23, HUD-Lücken, Bitmap-Ende, Farbtabellen-Lücken). Sie wandern in
normalen RAM. Netto werden etwa **5,5 KB** frei; im Hauptbereich sind es
heute 20 Bytes.

## Machbarkeit (gemessen)

`tools/textmode_census.py` zeichnet jede Bahn mit dem echten Bitmap-Kern
(py65) und prüft jede Zelle der Zeilen 0–23:

- **0 Zellen** mit zwei Farben ohne Schwarz in allen 18 Bahnen. Mit globalem
  schwarzem Hintergrund ($FF15) reicht je Zelle eine Vordergrundfarbe:
  Boden grau, Rasen grün (zwei Luminanzen), Wasser blau (zwei Luminanzen);
  Rahmen, Ball, Loch und Zielpunkte sind Schwarz = Hintergrund.
- Höchstens **25 verschiedene statische Zeichen** je Bahn (Bahn 9), meist
  11–20.

Zeichenbudget (128 Zeichen, 1 KB):

| Zweck | Zeichen |
|---|---:|
| Schrift (BAHN, PUNKTE, PAR, SUMME, Ziffern, Leerzeichen) | ~22 |
| Bahnmuster, mit Reserve für neue Bahnen | ≤ 64 |
| Ladebalken (Linie und 8 Füllstufen) | 9 |
| Bewegliche Zeichen (Ball bis 4 Zellen, 7 Zielpunkte) | 12 |
| Reserve | ~21 |

## Technik

- TED-Textmodus, 40×25, Hi-Res (kein Multicolor), Zeichensatz im RAM
  ($FF12 Bit 2 = 0, $FF13 Bits 2–7), Reverse-Modus aus. Attributbyte je
  Zelle: Farbe Bits 0–3, Luminanz Bits 4–6, Blinken Bit 7 = 0.
- Gesetzte Bits = Zellfarbe, gelöschte Bits = Schwarz. Die Muster sind also
  gegenüber heute für Bodenzellen invertiert (Boden gesetzt, Rahmen gelöscht).
- Ball, Zielpunkte, Loch: schwarz, d. h. sie **löschen** Bits.
- **Statischer Renderer** (Bahnwechsel, Bild aus): derselbe Algorithmus wie
  heute (Scanline-Füllung, Klassifizierung, Rahmenbänder, Außenschrägen),
  aber zeilenweise in einen Puffer von 3 Zellzeilen (960 Bytes Scratch),
  dann jede Zelle mit einem Muster vergleichen und als Zeichen ablegen
  (lineare Suche über ≤ 64 Muster; geschätzt unter 1 s je Bahn).
- **Bewegliche Objekte**: pro Bild die belegten Zellen auf ihre statischen
  Codes zurücksetzen; für jede Zelle unter Ball/Zielpunkt das statische
  Zeichen in ein freies dynamisches Zeichen kopieren, Pixel löschen, Code
  setzen. Ersetzt das heutige Sichern/Wiederherstellen von Bitmap-Bytes.
- **HUD**: Schriftzeichen beim Start aus dem ROM ($D000) in den RAM-
  Zeichensatz kopieren; Balken aus 9 festen Zeichen.
- Wassererkennung bleibt: Farbton der Zelle unter der Ballmitte (jetzt
  Vordergrundfarbe).

## Speicherplan (Vorschlag)

| Bereich | Inhalt |
|---|---|
| $0000–$01FF | Zero Page, Stack, aktuelle Bahn (wie heute) |
| $0200–… | Code, Tabellen (Quadrate, Normalen), alle Bahnen |
| 2-KB-Grenze, z. B. $3000–$37FF | Attribute ($3000) und Zeichencodes ($3400) |
| 1-KB-Grenze, z. B. $3800–$3BFF | Zeichensatz |
| $3C00–$3FFF | Renderer-Scratch (960 Bytes), sonst frei |

Genaue Lage nach den TED-Registern im Datenblatt und in VICE festlegen.

## Schritte und Abnahme

1. **Entscheidung** in der SPEC festhalten (Textmodus statt Bitmap, schwarzer
   globaler Hintergrund als Regel für neue Bahnelemente).
2. **Testgrundlage zuerst**: Ein Test-Helfer setzt Bildschirm + Zeichensatz
   + Attribute wieder zu 320×200 Pixeln mit Farben zusammen. Damit bleiben
   `tests/course_reference.py` und alle Bildtests unverändert gültig.
   Abnahme: **pixelgleiches Bild** zum heutigen Bitmap-Stand für alle 18
   Bahnen und die Testbahn (vor dem Umbau als Referenz sichern).
3. **Speicherumbau**: Build ohne versteckte Bitmap-Bereiche; Tabellen, Code
   und Bahndaten in normalen RAM; Generator vereinfachen (keine HUD-,
   Farblücken-, Rest-Bereiche mehr).
4. **Statischer Renderer** auf Zeichen umstellen, mit Zeichenzählung und
   Build-/Laufzeitfehler bei Überlauf des Budgets.
5. **HUD** (Schrift, Balken, Endanzeige) auf Zeichen umstellen.
6. **Ball und Zielpunkte** über dynamische Zeichen; die bestehenden
   Pixeltests (alle 8 Ausrichtungen, x = 255/256, rechter Rand, Wasser,
   Wiederherstellung) müssen pixelgleich bestehen.
7. **VICE**: Smoke- und Joystick-Test anpassen; Zeitbudget ≤ 32000 Ticks
   (bewegliche Objekte dürften billiger werden als heute); Screenshot für die
   README neu erzeugen.
8. **Editor und Generator**: Zeichenzählung je Bahn anzeigen (Budget ≤ 64).
9. Danach den freien Speicher verteilen: Sand/Eis, Hole-in-one-Fanfare,
   HUD-Kommentare, eigener Zeichensatz, Ergebnisbild, mehr Bahnelemente.

## Risiken

- Zeichenbudget: Bahnen mit vielen Schrägen (Bahn 9: 25) und künftige
  Elemente; Editor zeigt die Zahl, der Build bricht bei Überlauf ab.
- Neue Grafikelemente müssen mit „eine Farbe + Schwarz“ je Zelle auskommen.
- Laufzeit des Bahnwechsels (Muster-Suche) – messen; notfalls Hash statt
  linearer Suche.
- Aufwand: grob so viel wie alle bisherigen Grafikschritte zusammen; die
  Physik bleibt unberührt, die Bildtests sichern das Ergebnis ab.
