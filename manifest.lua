-- GTS OS Manifest (wird von INFO > SYSTEM > UPDATE gelesen). Nicht von Hand aendern:
-- release.py schreibt es mit Groesse und Pruefsummen neu.
{
  version = "8.3",
  release = "1.2.1",
  agent = "5.4",
  date = "2026-10-11",
  notes = {
    "GTS OS 1.2.1 - Claude findet seinen Weg",
    "Claude: neue Wegfindung (plant wie NPCs, scannt unterwegs)",
    "Claude: Punkte im Huegel/Block, kein falsches \"stecke fest\"",
    "Claude: ortet Spieler auch ohne playerSpy",
    "INFO > SYSTEM > AUFRAEUMEN: Muell weg, mehr Platz",
    "Danach in CLAUDE: PROGRAMM-UPDATE antippen"
  },
  files = {
    pc = { file = "gts_os.lua", size = 786512, sha256 = "7eca8dd258fc6e64db33904407aaf8edaa73fdb730f0cd60d14534a26c4d4482",
      parts = { "4c1fe9481e91d2d8", "e4e116c749b17fe3", "b3a12a8f8d9516ca", "21a8f542a26fbc81", "19bac8cd86879e98", "1dbf69d2e1afaa2e", "63141e4d5108b4a8", "fcc8764f5b6063c6", "f6a8e2d6238728f0", "aab383987b1dcacf", "1af4de6a7e96fab3", "b94396f9d73b6ead", "02c249055b5e2212", "aab8d9ddc225f248", "aece70ba5c4f8f95", "0dedc40dc73e040b", "612fbedb663a3839", "3eab8acd5a848ddf", "adec7cf61586a622", "1bc1b51f3233f5c0", "965a1ef13c7a6cfc", "e91ac3d41c0ab807", "2fed553699d1ce13", "07d98dd60bd7b445", "5e14169a5fd5d1c7" } },
    pocket = { file = "gts_pocket.lua", size = 544299, sha256 = "8e6ff01b77af4e221e72e1060d8748e6db427027a3c767ff9da014438f718dbc",
      parts = { "7f06089c0e0de9ec", "1c6dd657f70f6a0c", "2ab5c81efaab3648", "3fbfd82ab8f79f94", "49228ee525ddc80a", "0e380bed067ca546", "f03f932bca4a614a", "4cb25e9e8a13a8e5", "6aad16cfe241ed37", "21297d8d43f7e1d0", "ddf1eb825567e001", "23773da4f24c5bcc", "1960c425ccb42cb9", "6677044abd5d7af5", "4fdc41788856f8a6", "364c002c2bc5594d", "050faafd307714a9" } },
    phone = { file = "gts_phone.lua", size = 544298, sha256 = "94bdb9670f3bbedf6ae6fb655cedc413870440ce4db58cf6e08b10879fb28b98",
      parts = { "9925d44ad21e935c", "85d01d11e9829acb", "f3968e56c16ff219", "ec32c72108c31974", "51eb4bf989b90a93", "779922ef6d3b307a", "d2abc6b1fe61d799", "1c31da3e5fef3e67", "3865ca11bf4300ff", "b30330e158028629", "f1ef997b776aa333", "6c5b67a02b00ab16", "44ef1cc241f72313", "b61049cf01a62466", "0a7cf2f619bdb9b5", "0c2cdf8ef65b69d2", "d994b4b874da928d" } },
    claude = { file = "gts_claude.lua", size = 544299, sha256 = "8ec0cc061dfbf5d23325dd96fc80d33fbcded983bea2380d89f4c7de6af62c11",
      parts = { "15af8937ed3032af", "1c6dd657f70f6a0c", "2ab5c81efaab3648", "3fbfd82ab8f79f94", "49228ee525ddc80a", "0e380bed067ca546", "f03f932bca4a614a", "4cb25e9e8a13a8e5", "6aad16cfe241ed37", "21297d8d43f7e1d0", "ddf1eb825567e001", "23773da4f24c5bcc", "1960c425ccb42cb9", "6677044abd5d7af5", "4fdc41788856f8a6", "364c002c2bc5594d", "050faafd307714a9" } },
    turtle = { file = "gts_turtle.lua", size = 123743, sha256 = "e1d70d39f10d598e512662c2c22a52d32a23df0412fb9f001f0f904a90a25236",
      parts = { "3868422e68c8049b", "5c5e22011d597ab9", "403cbe6f43cd8b51", "98d118d39b770ab1" } },
  },
}
