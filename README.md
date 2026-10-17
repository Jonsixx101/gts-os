# GTS OS

Betriebssystem fuer CC: Tweaked (Minecraft 1.21.1, All the Mods 10) - by Jonsi.
Schwarm-Steuerung fuer Turtles, ME-artiges Lager, Notizen, Web, Rechner, Spiele,
dazu **Claude**, ein Begleit-Droide (Turtle mit Diamantschwert) -
mit verschluesseltem Funk, Codesperre und Ein-Knopf-Update.

## Installieren (ein Befehl)

Im Computer, Pocket oder in der Turtle eintippen:

```
wget run https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua
```

Der Installer erkennt das Geraet (PC, Pocket: Tablet, Phone oder Claude-Fernbedienung, Turtle), laedt die
passende Datei, prueft sie und richtet sie als `startup.lua` ein. Turtles danach mit
`P` das Schwarm-Passwort geben - oder bequemer am PC: DATEN > TURTLE-DISK.

## OpenComputers (Minecraft 1.7.10) - GTS OS 1.2 fuer OC

Eigene Fassung im Ordner `oc/` fuer OpenComputers (im Simulator gegen die OC-API getestet, Lua 5.2 und 5.3,
80x25 bis 160x50 - im Spiel noch nicht). Gebaut fuer NNC Nuclear Nexus: HBM's Nuclear Tech, OpenSecurity,
Applied Energistics 2. Apps werden nur bei Bedarf geladen; mehrere Rechner arbeiten als **Verbund** unter einer Oberflaeche.

**Installieren** (im OC-Rechner mit Internet Card, OpenOS auf der Festplatte):

```
wget -f https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua /tmp/i.lua
/tmp/i.lua
```

Derselbe `install.lua` erkennt OpenComputers selbst. Auf einem **Robot** richtet er nur den
GTS-Lader ein (Schwarm-Passwort, Name). **Drohnen** und **Knoten** bekommen eine EEPROM:
DROHNEN > EINRICHTEN bzw. GERAETE > VERBUND.

| App | Was |
|---|---|
| HOME | Uebersicht: Einheiten, Sicherheit, Verbund, Energie, RAM, Funk, Meldungen, Besucher |
| DROHNEN | Drohnen (Ziel, Heim, Patrouille, Aufklaerung um die Basis, Wache, Kurier) und Robots (Abbauen, Scan); Ladestationen mit Weltkoordinaten, Karte, Wegpunkte, Besucher |
| SICHERHEIT | OpenSecurity: Tueren, Personen (Karten schreiben, Biometrie, PIN), Melder, Abwehr (Alarm, Redstone-Fallen, Abriegeln - nur wenn scharf), benannte Redstone-Ausgaenge, Protokoll |
| ANLAGEN | HBM's NTM: Energiespeicher, Turbinen, Tanks, Geiger, Reaktoren (ZIRNOX, Forschung, PWR, Watz), RBMK-Raster mit Steuerung und AZ-5 |
| LAGER | AE2: Items mit Suche, Bestellen, Auftraege, CPUs, Vorrat halten |
| GERAETE | alle Komponenten (auch an Knoten), Verbund-Knoten, Waechter-Regeln (laufen auf dem Knoten auch ohne den Hauptrechner) |
| SYSTEM | Rechner-Info, System-Check, Einstellungen (Schriftgroesse, Bildschirm), Meldungen, Update, Backup, Wartung |
| NOTIZEN, RECHNER, DATEIEN | Merkzettel, Rechner + Umrechner, Dateien mit Editor |
| KI | Claude ueber die API (eigener Schluessel), Werkzeuge fuer alle Bereiche mit Rechten je Bereich (frei/fragen/aus), Ereignis-Modus; steuert Drohnen und Robots selbst (Abbauen, Scan, Ziel, Kurier, Rundflug) - mit Schwarm-Autopilot und Dauerauftrag; Internet auch ueber einen Knoten |
| SHELL | OpenOS-Shell, Lua-Konsole, Programme - nur mit Admin-Code |

Mindestens: Gehaeuse T3, CPU T2, RAM 2x T2.5, Grafikkarte + Bildschirm T2 (80x25), Festplatte,
Netzwerk- oder Wireless-Karte. Data Card ist am Hauptrechner nicht mehr Pflicht (SHA-256 notfalls in Lua),
Tier 2 bringt AES. Empfohlen: CPU T3, RAM 2x T3.5, Grafik + Bildschirm T3 (z.B. 5x2 Bloecke = 160x32),
Internet Card (hier oder an einem Knoten). Updates: SYSTEM > UPDATE (liest `oc/manifest.lua`).

## Dateien

| Datei | Wohin |
|---|---|
| `gts_os.lua` | Advanced Computer (am besten mit 5x2 Advanced Monitor) |
| `gts_pocket.lua` | Advanced Wireless Pocket Computer (Schwarm-Tablet, nur Anzeige) |
| `gts_phone.lua` | Pocket Computer fuer Freunde (Lager, Notizen, Rechner, Nether, Web, Spiele) |
| `gts_claude.lua` | Advanced Pocket Computer als Claude-Fernbedienung (Installer: Pocket, Auswahl 3) |
| `gts_turtle.lua` | Schwarm-Agent fuer jede Turtle (kommt per TURTLE-DISK / UPDATE vom PC), auch fuer Claude |
| `manifest.lua` | Versionen, Groessen und Pruefsummen fuer das Update |
| `install.lua` | Installer (siehe oben) |
| `chatbox.lua` | Zusatzprogramm fuer LUA APPS |

## Speicher

INFO > SYSTEM > AUFRAEUMEN zeigt, was wie viel Platz belegt, und entfernt nur echten
Muell (halb geschriebene Dateien, altes Log, Reste eines Updates). Sicherungen, alte
Backups und alte OS-Kopien nur auf Wunsch; Notizen und eigene Scripts nie.
Automatisch einmal am Tag (abschaltbar).

## Updates

- **PC, Pocket, Phone, Claude-Fernbedienung:** INFO > SYSTEM > UPDATE > SUCHEN, dann JETZT INSTALLIEREN.
  Das OS sucht ausserdem einmal am Tag selbst und meldet sich (Uhr antippen).
  Geprueft wird Groesse, SHA-256 je 32 KB, Version und ob die Datei laeuft.
  Startet die neue Fassung nicht, kommt die alte automatisch zurueck.
- **Turtles:** danach am PC SCHWARM > ALLE > UPDATE (der neue Agent geht per Funk raus).
- **Claude:** am PC in der CLAUDE-App oben AGENT bzw. PROGRAMM-UPDATE antippen
  (Claude ist nicht im Schwarm und bekommt seine Updates einzeln).

## Claude (ab 1.2.0)

Eine eigene Turtle, die nicht zum Schwarm gehoert: Begleiter, Wache, Bauhilfe,
Besucher-Log. Fliegt nur durch freie Felder (baut nie etwas ab), haelt Abstand zu
Create-Maschinen, bleibt hoechstens 100 Bloecke um den PC und haut Monster weg.
Seit 1.2.1 plant er seine Wege wie NPCs in Spielen (optimistisch, scannt unterwegs,
plant bei Hindernissen neu) und findet Spieler auch ohne `playerSpy`.
Seit 1.2.2 laeuft alles mit Advanced Peripherals 0.7 und 0.8 (0.8 hat `scanBlocks`,
`getPlayer`, Chat-Optionen als Tabelle und ein anderes Chat-Ereignis).
Die Fernbedienung braucht dasselbe Schwarm-Passwort wie der PC; hoert sie Funk mit
einem anderen Passwort, sagt sie es und bietet die Eingabe direkt an.
Steuerung am PC (App CLAUDE) oder mit der Fernbedienung (`gts_claude.lua`),
im Spiel auch per Chat (`claude hilfe`). Gleiches Schwarm-Passwort wie alle anderen.

## Versionen

Angezeigt wird die Versionsnummer der Vollversion (aktuell **1.2.2**). Intern zaehlt das
Update eine eigene Nummer weiter (`version` im Manifest, z.B. `8.4`) - damit erkennen auch
aeltere Installationen jedes neue Update. Eine 8.0 meldet deshalb einmalig "V8.4 ist da";
nach dem Update steht ueberall 1.2.2.

## Wie das Repo funktioniert (kurz)

- Ein **Repository** ist ein Ordner mit Verlauf: jede Aenderung ist ein **Commit**
  (Schnappschuss mit Beschreibung). `main` ist der Hauptzweig, aus dem die Computer
  im Spiel ihre Updates holen.
- Jede Datei hat eine feste **Raw-Adresse**, z.B.
  `https://raw.githubusercontent.com/Jonsixx101/gts-os/main/gts_os.lua`. Die liest das OS.
- Jede Version bekommt zusaetzlich einen eigenen **Zweig** mit ihrem Namen (z.B. `v1.2.2`),
  der danach nie mehr geaendert wird. Darueber kommt eine alte Fassung zurueck, falls ein
  Update schiefgeht: `.../gts-os/v1.2.2/gts_os.lua`.
- Neue Version veroeffentlichen = Dateien + neues `manifest.lua` auf `main` committen,
  Versions-Zweig anlegen, pushen. Danach finden alle Computer im Spiel das Update von selbst.
- GitHub cached die Raw-Dateien ein paar Minuten: direkt nach dem Veroeffentlichen
  kann SUCHEN noch kurz die alte Version melden.

Der alte Gist bleibt als Alternative (INFO > SYSTEM > UPDATE > Quelle GIST, nur PC).
