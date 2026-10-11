-- GTS OS Manifest (wird von INFO > SYSTEM > UPDATE gelesen). Nicht von Hand aendern:
-- release.py schreibt es mit Groesse und Pruefsummen neu.
{
  version = "8.1",
  release = "1.1.0",
  agent = "5.3",
  date = "2026-10-11",
  notes = {
    "GTS OS 1.1.0 - erstes Update der Vollversion",
    "WEB neu: Suchseite, Treffer wie bei Google, Lesemodus",
    "KARTE: Drehung (INFO > EINSTELLUNGEN), Chunk-Raster, GPS-Ebene",
    "LAGER: Kategorie-Leiste ohne Leerseite, Reihenfolge mit < >",
    "Einstellungen auf Phone und kleinen Bildschirmen luftiger",
    "Turtles: danach SCHWARM > ALLE > UPDATE (Agent 5.3)"
  },
  files = {
    pc = { file = "gts_os.lua", size = 607169, sha256 = "61d0d2d175e143ae10f217b813c1d136ae6708dbc6393592782becc7dfee391d",
      parts = { "4c801bce6cc9a716", "22585fe8a9e8a20b", "51bdf796859b29c8", "c617a86c5fb03158", "05489a943602610c", "8d5e2ddaf6d4f2fe", "0ccb453846a37a58", "7b7552e31210d859", "231a156463469159", "287d287d4ebb6f87", "9715ff42095a4f01", "db3c8b93c9101762", "c231bb64f0e91456", "8f05279ddb56a2e3", "b0064a304ebe1653", "bc4586b62a9e2dc8", "c074f44e15d66481", "8dd1e39f04af4d48", "a1c8edafdac16f4c" } },
    pocket = { file = "gts_pocket.lua", size = 487933, sha256 = "9be6e77d5e52015b43f4e689200f0fb6aff82457a0d5bef120b37dbde6794fca",
      parts = { "83defa0afc10512e", "b442f941a76b6265", "8820aec5b2488f27", "3a7c482ea7ed58f5", "a1dbe47915471412", "fe18e82ee2fd7179", "a939a2ccb8784c47", "e506ae8839996a6c", "53937a311b3af36b", "37da94117e49aa38", "6217ffae39703f74", "3b0c30ac6cd04442", "742bcb9a5755a322", "3573aa01f622cfe0", "cda0cadee77e777a" } },
    phone = { file = "gts_phone.lua", size = 487932, sha256 = "32695aac7282b118a529308346dacd8492d96e52324b6dfee20943068e2cf2c3",
      parts = { "21d09c58aa3100f9", "8975e823f90181af", "4a492f84cdf7a88a", "d7bdf52bb71e8872", "21c5ef0b884bee2d", "9eb93a53e6f8c7d2", "1c7a7918ddbcbc93", "6e61bade4cff8cf2", "23f10d60204efb2b", "3b94877426cb8e34", "317f00a6ba975bd9", "d879ba54c9c44578", "b7025b577be56b25", "8abdaec184124df9", "6d351aee4b85a7f6" } },
    turtle = { file = "gts_turtle.lua", size = 120659, sha256 = "dde9c0f88a4b2c895d4d7859c46519b8354e719856614ae8e0d8c158d4155d0e",
      parts = { "1a6bee4d4bdc5587", "5fbb761d68d2d054", "8a4dd73d7fb0621f", "34abee55fd33bc37" } },
  },
}
