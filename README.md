# GTS OS

Betriebssystem fuer CC: Tweaked (Minecraft 1.21.1, All the Mods 10) - by Jonsi.
Schwarm-Steuerung fuer Turtles, ME-artiges Lager, Notizen, Web, Rechner, Spiele -
mit verschluesseltem Funk, Codesperre und Ein-Knopf-Update.

## Installieren (ein Befehl)

Im Computer, Pocket oder in der Turtle eintippen:

```
wget run https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua
```

Der Installer erkennt das Geraet (PC, Pocket: Tablet oder Phone, Turtle), laedt die
passende Datei, prueft sie und richtet sie als `startup.lua` ein. Turtles danach mit
`P` das Schwarm-Passwort geben - oder bequemer am PC: DATEN > TURTLE-DISK.

## Dateien

| Datei | Wohin |
|---|---|
| `gts_os.lua` | Advanced Computer (am besten mit 5x2 Advanced Monitor) |
| `gts_pocket.lua` | Advanced Wireless Pocket Computer (Schwarm-Tablet, nur Anzeige) |
| `gts_phone.lua` | Pocket Computer fuer Freunde (Lager, Notizen, Rechner, Nether, Web, Spiele) |
| `gts_turtle.lua` | Schwarm-Agent fuer jede Turtle (kommt per TURTLE-DISK / UPDATE vom PC) |
| `manifest.lua` | Versionen, Groessen und Pruefsummen fuer das Update |
| `install.lua` | Installer (siehe oben) |
| `chatbox.lua`, `gts_blaze.lua` | Zusatzprogramme (LUA APPS bzw. eigenstaendige Blaze-Turtle) |

## Updates

- **PC, Pocket, Phone:** INFO > SYSTEM > UPDATE > SUCHEN, dann JETZT INSTALLIEREN.
  Das OS sucht ausserdem einmal am Tag selbst und meldet sich (Uhr antippen).
  Geprueft wird Groesse, SHA-256 je 32 KB, Version und ob die Datei laeuft.
  Startet die neue Fassung nicht, kommt die alte automatisch zurueck.
- **Turtles:** danach am PC SCHWARM > ALLE > UPDATE (der neue Agent geht per Funk raus).

## Wie das Repo funktioniert (kurz)

- Ein **Repository** ist ein Ordner mit Verlauf: jede Aenderung ist ein **Commit**
  (Schnappschuss mit Beschreibung). `main` ist der Hauptzweig, aus dem die Computer
  im Spiel ihre Updates holen.
- Jede Datei hat eine feste **Raw-Adresse**, z.B.
  `https://raw.githubusercontent.com/Jonsixx101/gts-os/main/gts_os.lua`. Die liest das OS.
- Jede Version bekommt einen **Tag** (z.B. `v8.0`). Darueber kommt eine alte Fassung
  zurueck, falls ein Update schiefgeht: `.../gts-os/v8.0/gts_os.lua`.
- Neue Version veroeffentlichen = Dateien + neues `manifest.lua` committen, Tag setzen,
  pushen. Danach finden alle Computer im Spiel das Update von selbst.
- GitHub cached die Raw-Dateien ein paar Minuten: direkt nach dem Veroeffentlichen
  kann SUCHEN noch kurz die alte Version melden.

Der alte Gist bleibt als Alternative (INFO > SYSTEM > UPDATE > Quelle GIST, nur PC).
