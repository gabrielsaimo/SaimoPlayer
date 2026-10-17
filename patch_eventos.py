import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "r") as f:
    content = f.read()

imports_patch = """
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import java.text.Normalizer
import org.json.JSONObject
"""

if "import kotlinx.coroutines.async" not in content:
    content = content.replace("import org.json.JSONArray", "import org.json.JSONArray" + imports_patch)

carregar_eventos_new = """
    private fun carregarEventos() {
        carregando.visibility = View.VISIBLE
        avisoErro.visibility = View.GONE
        
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val embedDeferred = async { 
                    val pedido = Request.Builder().url("https://embedtv.cc/api/events").build()
                    Playback.client.newCall(pedido).execute().use { r ->
                        if (r.isSuccessful) r.body?.string() else null
                    }
                }
                
                val espnUrls = listOf(
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.2/scoreboard"
                )
                
                val espnDeferreds = espnUrls.map { url ->
                    async {
                        val pedido = Request.Builder().url(url).build()
                        Playback.client.newCall(pedido).execute().use { r ->
                            if (r.isSuccessful) r.body?.string() else null
                        }
                    }
                }
                
                val embedBody = embedDeferred.await()
                val espnBodies = espnDeferreds.awaitAll()
                
                if (embedBody == null) throw Exception("Erro de rede")
                val jsonEmbed = JSONArray(embedBody)
                val eventosDict = mutableMapOf<String, Evento>()
                
                fun norm(t: String): String {
                    val limpo = Normalizer.normalize(t, Normalizer.Form.NFD)
                        .replace("[^\\\\p{ASCII}]".toRegex(), "")
                        .lowercase()
                        .replace("clube", "")
                        .replace("esporte", "")
                        .replace("fc", "")
                        .replace("ec", "")
                        .replace("sp", "")
                        .replace("rj", "")
                        .replace("mg", "")
                        .replace("rs", "")
                        .replace("pr", "")
                        .replace("ba", "")
                        .replace("pe", "")
                        .replace("sc", "")
                        .replace("ce", "")
                        .replace("go", "")
                        .replace("mt", "")
                        .replace("ms", "")
                        .replace("pa", "")
                        .replace("rn", "")
                        .replace("pb", "")
                        .replace("al", "")
                        .replace("se", "")
                        .replace("pi", "")
                        .replace("ma", "")
                        .replace("am", "")
                        .replace("ro", "")
                        .replace("rr", "")
                        .replace("ap", "")
                        .replace("to", "")
                        .replace("df", "")
                        .replace("ac", "")
                        .replace(" ", "")
                    return limpo
                }

                // Carrega ESPN primeiro para base de dados riquíssima
                for (espnBody in espnBodies) {
                    if (espnBody == null) continue
                    try {
                        val espnJson = JSONObject(espnBody)
                        val leagues = espnJson.optJSONArray("leagues") ?: continue
                        val events = espnJson.optJSONArray("events") ?: continue
                        
                        val leagueName = leagues.optJSONObject(0)?.optString("name") ?: ""
                        val leagueLogo = leagues.optJSONObject(0)?.optJSONArray("logos")?.optJSONObject(0)?.optString("href") ?: ""
                        
                        for (i in 0 until events.length()) {
                            val ev = events.getJSONObject(i)
                            val title = ev.optString("name")
                            val dateStr = ev.optString("date")
                            
                            val comps = ev.optJSONArray("competitions")?.optJSONObject(0)?.optJSONArray("competitors") ?: continue
                            var homeName = ""
                            var homeLogo = ""
                            var awayName = ""
                            var awayLogo = ""
                            
                            for (c in 0 until comps.length()) {
                                val comp = comps.getJSONObject(c)
                                val team = comp.getJSONObject("team")
                                val isHome = comp.optString("homeAway") == "home"
                                if (isHome) {
                                    homeName = team.optString("name")
                                    homeLogo = team.optString("logo")
                                } else {
                                    awayName = team.optString("name")
                                    awayLogo = team.optString("logo")
                                }
                            }
                            
                            var inicioMs = 0L
                            var horarioFormatado = ""
                            try {
                                val formatoData = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm'Z'", java.util.Locale.US)
                                formatoData.timeZone = java.util.TimeZone.getTimeZone("UTC")
                                val dateObj = formatoData.parse(dateStr)
                                if (dateObj != null) {
                                    inicioMs = dateObj.time
                                    val sdfHorario = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
                                    horarioFormatado = sdfHorario.format(dateObj)
                                }
                            } catch (e: Exception) { }
                            
                            val key = norm(homeName) + "|" + norm(awayName)
                            eventosDict[key] = Evento(
                                titulo = title,
                                ligaNome = leagueName,
                                ligaLogo = leagueLogo,
                                timeCasaNome = homeName,
                                timeCasaLogo = homeLogo,
                                timeForaNome = awayName,
                                timeForaLogo = awayLogo,
                                inicio = dateStr,
                                fim = "",
                                playerUrl = "", // sem stream nativo ESPN
                                horarioFormatado = horarioFormatado
                            )
                        }
                    } catch (e: Exception) { e.printStackTrace() }
                }

                // Agora processa EmbedTV, enriquecendo ou adicionando
                for (i in 0 until jsonEmbed.length()) {
                    val obj = jsonEmbed.getJSONObject(i)
                    
                    val league = obj.getJSONObject("league")
                    val teams = obj.getJSONObject("teams")
                    val home = teams.getJSONObject("home")
                    val away = teams.getJSONObject("away")
                    val players = obj.optJSONArray("players")
                    val playerUrl = if (players != null && players.length() > 0) players.getString(0) else ""
                    
                    val homeName = home.getString("name")
                    val awayName = away.getString("name")
                    
                    val inicioStr = obj.getString("time_start")
                    var inicioMs = 0L
                    var horarioFormatado = ""
                    try {
                        val formatoData = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US)
                        val dateObj = formatoData.parse(inicioStr)
                        if (dateObj != null) {
                            inicioMs = dateObj.time
                            val sdfHorario = java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault())
                            horarioFormatado = sdfHorario.format(dateObj)
                        }
                    } catch (e: Exception) {}

                    val key = norm(homeName) + "|" + norm(awayName)
                    val espnMatch = eventosDict[key]
                    
                    if (espnMatch != null) {
                        // Enriquece ESPN com a URL de streaming do EmbedTV e outros fallbacks
                        eventosDict[key] = espnMatch.copy(playerUrl = playerUrl)
                    } else {
                        // Adiciona jogo exclusivo do EmbedTV
                        eventosDict[key] = Evento(
                            titulo = obj.getString("title"),
                            ligaNome = league.getString("name"),
                            ligaLogo = league.optString("image"),
                            timeCasaNome = homeName,
                            timeCasaLogo = home.optString("image"),
                            timeForaNome = awayName,
                            timeForaLogo = away.optString("image"),
                            inicio = inicioStr,
                            fim = obj.getString("time_end"),
                            playerUrl = playerUrl,
                            horarioFormatado = horarioFormatado
                        )
                    }
                }
                
                val eventosFinais = eventosDict.values.toList().sortedBy { it.titulo }
                
                withContext(Dispatchers.Main) {
                    carregando.visibility = View.GONE
                    lista.adapter = EventosAdapter(eventosFinais)
                    focarQuandoPronto { lista.getChildAt(0) }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    carregando.visibility = View.GONE
                    avisoErro.visibility = View.VISIBLE
                    avisoErro.text = "Erro ao carregar eventos. Tente novamente mais tarde."
                }
            }
        }
    }
"""

# replace the old method using regex
content = re.sub(r'private fun carregarEventos\(\) \{.*?(?=private inner class EventosAdapter)', carregar_eventos_new + "\n    ", content, flags=re.DOTALL)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "w") as f:
    f.write(content)

