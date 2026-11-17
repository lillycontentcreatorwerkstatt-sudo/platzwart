# Platzwart

**Wie voll ist mein Mac – und wo lege ich das hin?**

Platzwart ist eine kleine Mac-App, die dir auf einen Blick zeigt:

- **Wohin damit?** Du wählst eine Datei aus, Platzwart schlägt die Ordner vor, in denen schon ähnliche Dateien liegen. Du entscheidest: *Hierhin verschieben*, *Anderer Ordner …*, *Nicht verschieben* oder *In den Papierkorb*.
- **Auslastung:** Speicherplatz, Speicherdruck und Prozessor, live.
- **Wo liegt wie viel?** Schreibtisch, Dokumente, Downloads und iCloud Drive als Baum, mit Größe, Anzahl der Dateien und wann zuletzt etwas geändert wurde. So siehst du sofort, welche Ordner es schon gibt und wo ein neues Dokument hinpasst.
- **Empfehlungen:** Hinweise, wo sich Aufräumen lohnt, zum Beispiel alte Downloads, sehr große Dateien oder vermutlich doppelte Dateien.

## Versprochen

- **Platzwart löscht nichts endgültig.** Eine Datei landet nur im Papierkorb von macOS, wenn du auf *In den Papierkorb* klickst und es bestätigst. Von dort kannst du sie im Finder zurücklegen.
- **Verschoben wird nur, wenn du es sagst.** Liegt im Zielordner schon eine Datei mit gleichem Namen, verschiebt Platzwart nicht und sagt dir Bescheid.
- **Alles bleibt auf deinem Mac.** Keine Internetverbindung, kein Konto, keine Datenübertragung. Damit die App sofort startet, merkt sie sich das letzte Ergebnis unter `~/Library/Application Support/Platzwart/`.
- **Offener Quellcode** unter MIT-Lizenz. Jeder kann nachlesen, was die App tut.

## Installation

1. Lade unter **Releases** die neueste ZIP-Datei herunter (z. B. `Platzwart-0.4.1-Testversion-Apple-Silicon.zip`) und entpacke sie.
2. Ziehe `Platzwart.app` in deinen Ordner **Programme**.
3. Öffne die App per Doppelklick.

Die App ist lokal signiert und nicht von Apple notarisiert. Blockiert macOS den ersten Start wegen des unbestätigten Entwicklers und vertraust du dem Download, öffne nach dem Startversuch **Systemeinstellungen → Datenschutz & Sicherheit → Dennoch öffnen**. Bei einer Meldung über Schadsoftware oder eine beschädigte App brich den Start ab. [Apples Erklärung](https://support.apple.com/de-de/102445)

Beim ersten Durchsuchen fragt macOS, ob Platzwart auf Schreibtisch, Dokumente und Downloads zugreifen darf. Ohne diese Freigabe bleiben die Ordner leer.

## Bedienung

| Was | Wie |
| --- | --- |
| Eine Datei einsortieren | Unten **Datei einsortieren …**, Datei wählen, Vorschlag anklicken |
| Herumliegende Dateien durchgehen | Unten **Liegt noch rum**, Datei anklicken → *Wohin damit?* |
| Datei aus einer Empfehlung einsortieren | *Dateien anzeigen* → *Wohin damit?* |
| Datei wegwerfen, z. B. ein Duplikat | *Wohin damit?* → **In den Papierkorb** → bestätigen |
| Ordner im Finder öffnen | Lupe rechts neben dem Ordner, Doppelklick oder Rechtsklick → *Im Finder zeigen* |
| Weiteren Ordner anzeigen | Symbol **Ordner hinzufügen** oben rechts |
| Eigenen Ordner wieder entfernen | Rechtsklick → *Aus Übersicht entfernen* |
| Neu durchsuchen | Symbol **Neu scannen** oben rechts |
| Datei aus einer Empfehlung finden | *Dateien anzeigen* → Lupe |

## Wie die Ordnervorschläge entstehen

Beim Durchsuchen merkt sich Platzwart, welche Wörter in den Datei- und Ordnernamen vorkommen und welche Dateitypen wo liegen. Für deine Datei gewinnt der Ordner, in dem

- schon Dateien mit ähnlichen Wörtern im Namen liegen,
- der Ordnername selbst passt,
- Dateien desselben Typs liegen,
- zuletzt etwas geändert wurde.

Seltene Wörter wie „Telekom“ zählen mehr als häufige. Downloads, Hauptordner wie „Dokumente“ und technische Ordner werden nicht vorgeschlagen. Passt der Vorschlag nicht, wählst du mit *Anderer Ordner …* selbst.

## Wie die Empfehlungen entstehen

| Empfehlung | Regel |
| --- | --- |
| Speicher fast voll | ab 80 % belegt (ab 90 % dringend) |
| Alte Downloads | Dateien in Downloads, die seit über 90 Tagen nicht geändert wurden, zusammen mindestens 500 MB |
| Große Dateien | einzelne Dateien ab 1 GB |
| Vermutlich doppelt | gleicher Name und gleiche Größe an mehreren Stellen, ab 1 MB. „Rechnung 2.pdf“, „Rechnung (1).pdf“ und „Rechnung Kopie.pdf“ zählen als gleicher Name. |

Technische Ordner von Programmierprojekten (etwa `node_modules` oder Build-Ordner) und versteckte Ordner zählen bei der Größe mit, erzeugen aber keine Empfehlungen. Dort sind Kopien normal und gewollt.

## Selbst bauen

Voraussetzung: macOS 14 oder neuer und die Xcode Command Line Tools. Die fertige Testversion läuft auf Macs mit Apple-Chip.

```bash
./scripts/build-app.sh
```

Die fertige App liegt danach in `dist/Platzwart.app`.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
