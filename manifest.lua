-- GTS OS Manifest (wird von INFO > SYSTEM > UPDATE gelesen). Nicht von Hand aendern:
-- release.py schreibt es mit Groesse und Pruefsummen neu.
{
  version = "8.4",
  release = "1.2.2",
  agent = "5.5",
  date = "2026-10-11",
  notes = {
    "GTS OS 1.2.2 - Advanced Peripherals 0.8",
    "Claude + Miner: Geo Scanner von AP 0.8",
    "Claude: Chat, Spieler, Monster mit AP 0.8",
    "Fernbedienung: sagt, wenn Passwort fehlt",
    "Danach: SCHWARM > UPDATE (Agent 5.5)",
    "In CLAUDE: AGENT 5.5, dann PROGRAMM-UPDATE"
  },
  files = {
    pc = { file = "gts_os.lua", size = 796107, sha256 = "55b302015c523c1d28cefbc0a5f9f08cd8049ca9ee64df89cef74b6c7b389d5c",
      parts = { "a3271912ff346255", "e4e116c749b17fe3", "b3a12a8f8d9516ca", "21a8f542a26fbc81", "56ec47d09d297830", "ec78bbc1ed293e03", "a0e068d66021bac0", "e3a2accdbf0bf56a", "98a45f475c059dd0", "37bb137d50981adf", "318f7c61aefc8baa", "898eb1990d3fa816", "c1bcdf3a39503d6d", "1604fd5bde8e277d", "db1369db3e1c46fb", "141985d025569d23", "4c7a716b5dde0486", "3a62687dd74199bd", "8fc25f6c88275fd8", "fb793fb686b43b53", "188cf432c2a8c0e1", "d4fc2a2d6f57dce1", "cccaf374779a1aa4", "105cc1c63b5c712b", "c3ac6392085ed049" } },
    pocket = { file = "gts_pocket.lua", size = 547376, sha256 = "d9fdd8830d76b64528159d0d0813ea67c0cd1b37d05f4f8340c608d97ce6475e",
      parts = { "52202a2207949403", "1c6dd657f70f6a0c", "2ab5c81efaab3648", "3fbfd82ab8f79f94", "49228ee525ddc80a", "0e380bed067ca546", "6468f391d9f0313c", "c331e508b55ca48c", "aefde2ea189dac09", "e6a96f85658ccfd5", "66a2841bc3db6b03", "3279b4196d70ba08", "8eef15f1accef119", "0c74f0990d7b5eae", "d24623000fca5eda", "cd1068d265b05335", "326a1f20c1b2077e" } },
    phone = { file = "gts_phone.lua", size = 547375, sha256 = "ae27b9bdfb928988449142a30813f77b4dbec4924774bf7503de499e412f77cb",
      parts = { "727ba60b4c8ba133", "85d01d11e9829acb", "f3968e56c16ff219", "ec32c72108c31974", "51eb4bf989b90a93", "779922ef6d3b307a", "5ad27bacd404e37d", "39412f1fdc62b195", "54fe5cff689fd8db", "56d8f22ab4ca7064", "b5cfddeab43235cb", "96b6adb5a6334307", "9b0e32832da7d858", "e8e365053315a15a", "79a6fab1907ab88a", "8d47092a758c3a6a", "f76e1c9e24730116" } },
    claude = { file = "gts_claude.lua", size = 547376, sha256 = "7729d2f4296331854a42cbe2dc0eaebf3e2d574c35d52ca974e21574482fd9a8",
      parts = { "cd1d047a9065262b", "1c6dd657f70f6a0c", "2ab5c81efaab3648", "3fbfd82ab8f79f94", "49228ee525ddc80a", "0e380bed067ca546", "6468f391d9f0313c", "c331e508b55ca48c", "aefde2ea189dac09", "e6a96f85658ccfd5", "66a2841bc3db6b03", "3279b4196d70ba08", "8eef15f1accef119", "0c74f0990d7b5eae", "d24623000fca5eda", "cd1068d265b05335", "326a1f20c1b2077e" } },
    turtle = { file = "gts_turtle.lua", size = 125247, sha256 = "366c88eb78db1f04e0214ed2b7de1bfd0b8a94f896721b8cf75a15887cb0fe24",
      parts = { "9ed56ec693f04165", "5c5e22011d597ab9", "6a851ed589f12dd3", "6b4f9ddfba58cb58" } },
  },
}
