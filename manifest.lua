-- GTS OS Manifest (wird von INFO > SYSTEM > UPDATE gelesen). Nicht von Hand aendern:
-- release.py schreibt es mit Groesse und Pruefsummen neu.
{
  version = "8.2",
  release = "1.2.0",
  agent = "5.4",
  date = "2026-10-11",
  notes = {
    "GTS OS 1.2.0 - Claude, der Begleit-Droide",
    "Neue App CLAUDE: Status, Karte, Modi, Log, Steuerkreuz",
    "Claude-Fernbedienung: Installer > Pocket > 3",
    "LUA APPS: APIproject.lua (Geruest fuer einen KI-Chat)",
    "Turtles: danach SCHWARM > ALLE > UPDATE (Agent 5.4)"
  },
  files = {
    pc = { file = "gts_os.lua", size = 761662, sha256 = "975718965ed0a2eb47f48ed5b37f4868ba8a42617394de69bcb012f23710ab61",
      parts = { "e9252955695837d2", "0ec55bf61991b517", "3bf2f53646c01788", "c41a39af6800cd0e", "b4b3c2a3296c0bd3", "aca5a29b9f013b2d", "8b69f4e69b296f33", "54f18729d222755c", "3aa8ee7ccf720b34", "b221c561fd7b29a8", "8ab9e3d5c69333ba", "1ca089d553f3b288", "7f0acd200e531479", "b2e184c4350d4e89", "46d965a604571203", "2bccf26abaa1dc08", "d74b5b214d50f45c", "28e1f9ea66005580", "4bd29ef4a1c00298", "652f992be2c35032", "2317a423ea96a7a8", "9058391f7462372f", "ef58fddd4f646f6e", "fd2be22cb4b23e28" } },
    pocket = { file = "gts_pocket.lua", size = 533729, sha256 = "45715a14afa10e0ee09f844f6c5d678b4fdb6e496b5c7a31a3010f9f7fedeb77",
      parts = { "a943a8b1a64933d4", "af0c43cc275d6fde", "ecf26ccc47353174", "c3b9d7a5adbfd5f2", "aa25c5608605e247", "b67fdc92bad45537", "67fdcdebc3f7dda6", "a934b6b3515964ee", "4c9cc852ba0c2aad", "c5b8f6ef6b1749be", "bd306dde81737b9e", "e8f97ca7dd21e547", "27e3cd3bbb79188c", "d2c8488c7fd6f5e4", "6586796e7f9c930a", "549dc8fe4a5bdac2", "67d4c0b093ce0d58" } },
    phone = { file = "gts_phone.lua", size = 533728, sha256 = "f0a232e227b4c9d156f5f2614119e031f169d0bc224f22a375567463f28763ab",
      parts = { "10b21c758a853b4e", "71b8ff803dea524b", "e118e1efda8905aa", "7c97f955f51e5ddb", "9dc0bc357e5677c8", "caf2ff2864f4ad9d", "99e2c1ac7ac46a4d", "b00470922b620020", "40593b239dec9634", "9378c27c5e3bd29e", "d60bf3c1643d262b", "2b07f7be4a2c89a3", "bc22923381fc6a74", "14ac2229998cbc15", "d9dc9ea3be4d3138", "a0c2d80067b32472", "f84bd21dc73d553a" } },
    claude = { file = "gts_claude.lua", size = 533729, sha256 = "d533fe8dae9296e57ffc129017390def889e511314ad04255e8f69763b2f632c",
      parts = { "f5984fe67d8655f2", "af0c43cc275d6fde", "ecf26ccc47353174", "c3b9d7a5adbfd5f2", "aa25c5608605e247", "b67fdc92bad45537", "67fdcdebc3f7dda6", "a934b6b3515964ee", "4c9cc852ba0c2aad", "c5b8f6ef6b1749be", "bd306dde81737b9e", "e8f97ca7dd21e547", "27e3cd3bbb79188c", "d2c8488c7fd6f5e4", "6586796e7f9c930a", "549dc8fe4a5bdac2", "67d4c0b093ce0d58" } },
    turtle = { file = "gts_turtle.lua", size = 123743, sha256 = "e1d70d39f10d598e512662c2c22a52d32a23df0412fb9f001f0f904a90a25236",
      parts = { "3868422e68c8049b", "5c5e22011d597ab9", "403cbe6f43cd8b51", "98d118d39b770ab1" } },
  },
}
