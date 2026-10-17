import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/RadiosActivity.kt", "r") as f:
    content = f.read()

replacement = """
                val arquivo = File(filesDir, "radios.txt")
                if (!arquivo.exists()) {
                    runCatching {
                        val request = okhttp3.Request.Builder()
                            .url("https://raw.githubusercontent.com/gabrielsaimo/SaimoPlayer/main/vod/radios.txt")
                            .build()
                        Playback.client.newCall(request).execute().use { response ->
                            if (response.isSuccessful) {
                                response.body?.string()?.let { arquivo.writeText(it) }
                            }
                        }
                    }
                }
                
                if (!arquivo.exists()) return@withContext emptyList<Radio>()
                arquivo.readLines().mapNotNull { linha ->
                    val partes = linha.split("|")
                    if (partes.size >= 2) Radio(partes[0].trim(), partes[1].trim()) else null
                }
"""

old_code = """
                val arquivo1 = File(filesDir, "vod/radios.txt")
                val arquivo2 = File(filesDir, "radios.txt")
                val alvo = if (arquivo1.exists()) arquivo1 else arquivo2
                if (!alvo.exists()) return@withContext emptyList<Radio>()
                
                alvo.readLines().mapNotNull { linha ->
                    val partes = linha.split("|")
                    if (partes.size >= 2) Radio(partes[0].trim(), partes[1].trim()) else null
                }
"""

content = content.replace(old_code.strip(), replacement.strip())

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/RadiosActivity.kt", "w") as f:
    f.write(content)

