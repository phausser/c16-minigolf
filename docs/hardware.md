# Hardware-Prototyp: Nachweise und Grenzen

Stand: 2026-10-04. ACME 0.97, VICE 3.10, C16/PAL mit 16 KB,
KERNAL 318004-05 und BASIC 318006-01. Kein 64-KB-Plus/4 als Ersatzmodell.

## Speicher und Start

PRG: 2363 Bytes einschließlich Ladeadresse. BASIC startet mit `SYS4109`.
Ein Kopierer wird zuerst nach $0200 verlegt; erst dort kopiert er den
Programmkörper von seiner Ladeadresse nach $0240. Dadurch darf der spätere
Programmkörper seinen ursprünglichen SYS-Stub und bereits kopierte Quellbytes
überschreiben. Ein zusätzlicher Test assembliert 3000 Füllbytes und prüft
diesen überlappenden Fall im echten 6502-Code.

Aktueller Programmkörper: $0240–$0B27, 2280 Bytes. Bis $1700 bleiben
3032 Bytes für weitere Routinen und Daten. $1700–$17FF ist Renderer-Scratch,
$1800–$1BFF Luminanz, $1C00–$1FFF Farbe, $2000–$3FFF Bitmap.
Die 192 Bytes hinter der sichtbaren Bitmap bleiben reserviert.
Zero Page enthält Zustand und Arbeitszeiger; $00/$01 bleiben CPU-I/O.
Alle Größen werden aus dem ACME-Symboldump geprüft. Das ist noch kein
Nachweis, dass der vollständige Physikkern und alle 18 Bahnen hineinpassen.

## TED und Eingabe

Primärquelle: [Commodore TED 7360 Datenblatt](https://www.karlstechnology.com/commodore/TED7360-datasheet.pdf),
Standard-Hi-Res und Registerbeschreibungen. Die Konfiguration verwendet
$FF06=$3B (Bitmap/Anzeige/25 Zeilen), $FF07=$08 (PAL/40 Spalten/Hi-Res),
$FF12=$08 (Bitmap $2000/RAM) und $FF14=$18 (Attributpaar $1800/$1C00).
Attributwerte $07 und $10 ergeben weiße gesetzte Pixel auf schwarzem Grund.
$FF13 wird auf null gesetzt; IRQ-Quellen sind deaktiviert. VICE-Rücklesewerte
werden mit Masken für reservierte Bits geprüft.

Bitmap-Adresse: $2000 + floor(y/8)×320 + floor(x/8)×8 + (y mod 8).
Getestet über alle 200 Zeilen, insbesondere rechts von x=255.
Die Anzeige wird während des initialen Bahnaufbaus ausgeschaltet.

Die lokale VICE-Datei `PLUS4/gtk3_sym.vkm` ordnet A=(1,2), D=(2,2),
W=(1,1), S=(1,5), P=(5,1) zu. $FD30 wählt aktive niedrige Zeilen,
$FF08 übernimmt den Spaltenwert. Der Scan wird im modellierten Keyboard-Bus
für alle 32 Kombinationen geprüft. Entprellung verlangt zwei gleiche Samples;
P wiederholt nicht. Echte Tastatur und Joystick bleiben ungeprüft.

## Rendering und Takt

17 Kontursegmente belegen 68 Bytes, mit Koordinaten auf Zweipixelraster.
Der Generator prüft Grenzen, Segmentlimit, degenerierte Linien, 45°-Winkel,
Konturschnittpunkte und überlappende Nachbarkanten. Er prüft noch keine
Ballfreiheit oder Erreichbarkeit; diese folgen mit der Kollisionsgeometrie.
Die Testdarstellung zeichnet zentrierte 3-Pixel-Wandstriche. Die endgültige
Zuordnung von sichtbarer Innenkante und Kollisionskante ist noch offen.

21 Ballpunkte und acht Zielpunkte sichern jeweils Adresse und ursprünglichen
Bitmap-Bytewert. Restaurierung erfolgt rückwärts, damit mehrere Punkte im
selben Byte den Hintergrund exakt wiederherstellen. Alle 128 Richtungen
wurden gegen einen nichttrivialen Hintergrund geprüft. Zielvektoren dienen
hier nur der Anzeige und sind keine vorberechneten Physikgeschwindigkeiten.

Die Hauptschleife wartet auf die aufsteigende Rastergrenze 205. VICE misst
35569 Ticks von einer Framegrenze zur nächsten, entsprechend einem PAL-Bild
mit geringer Polling-Abweichung. Der teuerste von 128 erzwungenen Redraws
einschließlich HUD braucht 20965 Ticks, rund 58,9 % eines Frames. Das ist
eine Messung des aktuellen Zielprototyps, kein zukünftiges Physikbudget.
Vor dem Physikkern wird das HUD nur bei tatsächlichen Änderungen aktualisiert.
Der initiale statische Bahnaufbau ist nicht an ein Ein-Frame-Limit gebunden.

## Prüfung und offene Punkte

12 automatisierte Tests des assemblierten Codes bestanden. Der eigenständig
gestartete VICE-Smoke-Test bestätigt ROM-Start, Grafikregister, Attribute,
Richtungs-/Stärkeänderung, Pause, Hintergrundrestaurierung und Framebudget.
Das VICE-Bild wurde visuell geprüft. Logische Kontrollereignisse werden nach
dem Hardware-Scan injiziert; kein behaupteter physischer Tastendrucktest.

In dieser eingeschränkten macOS-Umgebung scheitert der VICE-Start als
Make/Python-Unterprozess vor dem ROM-Start, teilweise mit SIGSEGV; derselbe
direkt gestartete CLI-Aufruf funktioniert. Vorbereitung und Prüfung sind
deshalb getrennt ausführbar, siehe README. Dieses Host-Startproblem ist
kein Fehler des C16-PRGs, aber `make smoke` konnte hier nicht als ein einzelner
Aufruf bestätigt werden.

Offen: reale C16-Hardware, physische Tastatur, Joystick, Diskettenladen,
Sound und NTSC. Es gibt noch keine Schläge, Roll-/Kollisionsphysik, Wertung
oder vollständige Runde. Schritt 2 muss Speicher und Laufzeit erneut messen.
