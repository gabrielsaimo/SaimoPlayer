import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/MainActivity.kt", "r") as f:
    content = f.read()

# Add isModoRadio property
if "private var isModoRadio = false" not in content:
    content = content.replace("private var current = 0", "private var isModoRadio = false\n    private var current = 0")

# Update initialization logic for radios
old_init = """        val rUrl = intent.getStringExtra(EXTRA_RADIO_URL)
        val rNome = intent.getStringExtra(EXTRA_RADIO_NOME)
        if (rUrl != null && rNome != null) {
            val radioChannel = Channel(name = rNome, sources = listOf(Source(url = rUrl)), categoria = "Rádio")
            ordered = (listOf(radioChannel) + ordered).distinctBy { it.name }
            play(0)
        } else {"""

new_init = """        val rUrl = intent.getStringExtra(EXTRA_RADIO_URL)
        val rNome = intent.getStringExtra(EXTRA_RADIO_NOME)
        if (rUrl != null && rNome != null) {
            isModoRadio = true
            val radiosFile = java.io.File(filesDir, "radios.txt")
            val radiosFallback = java.io.File(filesDir, "vod/radios.txt")
            val alvo = if (radiosFile.exists()) radiosFile else radiosFallback
            
            val radiosList = mutableListOf<Channel>()
            if (alvo.exists()) {
                alvo.readLines().forEach { linha ->
                    val partes = linha.split("|")
                    if (partes.size >= 2) {
                        radiosList.add(Channel(name = partes[0].trim(), sources = listOf(Source(url = partes[1].trim())), categoria = "Rádio"))
                    }
                }
            }
            if (radiosList.isEmpty()) {
                radiosList.add(Channel(name = rNome, sources = listOf(Source(url = rUrl)), categoria = "Rádio"))
            }
            
            ordered = radiosList
            numeros = ordered.mapIndexed { i, c -> c.name to i + 1 }.toMap()
            play(ordered.indexOfFirst { it.name == rNome }.coerceAtLeast(0))
        } else {"""

content = content.replace(old_init, new_init)

# Update reorder()
old_reorder = """        // canal sem nenhuma fonte não abriria mesmo.
        ordered = FontesDesativadas.peneirarCanais(Categorias.ordenar(Unlock.channels()))
        numeros = Categorias.ordenarFixo(ordered).mapIndexed { i, c -> c.name to i + 1 }.toMap()"""

new_reorder = """        // canal sem nenhuma fonte não abriria mesmo.
        if (!isModoRadio) {
            ordered = FontesDesativadas.peneirarCanais(Categorias.ordenar(Unlock.channels()))
            numeros = Categorias.ordenarFixo(ordered).mapIndexed { i, c -> c.name to i + 1 }.toMap()
        }"""

content = content.replace(old_reorder, new_reorder)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/MainActivity.kt", "w") as f:
    f.write(content)

