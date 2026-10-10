-- GTS OS Manifest (wird von INFO > SYSTEM > UPDATE gelesen). Nicht von Hand aendern:
-- release.py schreibt es mit Groesse und Pruefsummen neu.
{
  version = "8.0",
  agent = "5.2",
  date = "2026-10-10",
  notes = {
    "Neues Design: Graphit, Akzentfarbe, Sternenhimmel",
    "LAGER v2: eigene Kategorien, Mod-Ordner, Favoriten, Mindestmengen",
    "Ein-Knopf-Update, System-Check, Backup, Papierkorb",
    "Absturz-Bildschirm mit Neustart, sicherer Modus",
    "Mitteilungen (Uhr antippen), Hilfe ? in jeder App",
    "SCHWARM: Namen + Farben, Warnungen, PLANER, Fund auf der Karte"
  },
  files = {
    pc = { file = "gts_os.lua", size = 582579, sha256 = "8b32759210d0ad96698d5d5213a6a0b6a115fe9e778bd80e19bfccc55ee96d32",
      parts = { "db73e416b2736adc", "ba53f0c5da0f0c13", "68b702a42ef93343", "ac6a48a2406a4cd3", "09ac808a72ba7f65", "c73d90d0608e3c9a", "d305b7983f017cc9", "a30cefb5881eb55b", "20a75c7224c13c2b", "28ede867951afce5", "12a88fe92a1f6b04", "f85621f20687a675", "1b7b0f61fa8854fb", "f9173ab140ee07c2", "3a6de173a3ff49c8", "c4da1c76e935eabc", "37fd8be0c418df21", "0f97c8d2b7c59313" } },
    pocket = { file = "gts_pocket.lua", size = 463656, sha256 = "b9beccfdfec5d7969b1dea7822443586132a40e2d6ecd6a6588429cfcca663ef",
      parts = { "6af43bfe35cb888d", "4416a005d24f13ba", "f2a9b63b773e83b6", "bf016c90c163b35b", "84e438c7c0841769", "07b6feb2789e9ef6", "9f9582794855f8ce", "50c3a2c623dedc54", "cfb54b38e7d320ba", "72e748c1c60a68a0", "7a7ad75090a91e5c", "bc0c4d2f79b67179", "a3d17e4cd7df92d8", "5cec89e78958d931", "ec1cb40d6d0b3674" } },
    phone = { file = "gts_phone.lua", size = 463655, sha256 = "5f377a9eb485b73fc9f0d8bf8924b9d29df332b72a9310b90404aa1c8b25c682",
      parts = { "8521c9418f8f0829", "d5a2c1f9a5545668", "7e0de63a548c9daf", "a464f7ace326738a", "c49ad3773846dfb3", "c6e2f554c9be248a", "7701f83a161e2918", "095a1bbb172f8583", "f613588701e0a20f", "d020f5ae46c89841", "d9fee999acfe3437", "0af6fec0101143da", "b2be24cbba391529", "689bfd665d8bb0f5", "958e0865fc0993db" } },
    turtle = { file = "gts_turtle.lua", size = 120395, sha256 = "4704e5a527d5160d374a743a01d58c6f53d10d4b5c67a832e79380da61db02ba",
      parts = { "40570ab937fceb64", "b4e062ffc180c85c", "2f35612ee931bb82", "038a9ddba863736d" } },
  },
}
