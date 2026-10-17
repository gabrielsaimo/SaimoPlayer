import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "r") as f:
    content = f.read()

# Update Evento class
old_evento = """    data class Evento(
        val titulo: String,
        val ligaNome: String,
        val ligaLogo: String,
        val timeCasaNome: String,
        val timeCasaLogo: String,
        val timeForaNome: String,
        val timeForaLogo: String,
        val inicio: String,
        val fim: String,
        val playerUrl: String,
        val horarioFormatado: String
    )"""
new_evento = """    data class Evento(
        val titulo: String,
        val ligaNome: String,
        val ligaLogo: String,
        val timeCasaNome: String,
        val timeCasaLogo: String,
        val timeForaNome: String,
        val timeForaLogo: String,
        val inicio: String,
        val fim: String,
        val playerUrl: String,
        val horarioFormatado: String,
        val canalNome: String,
        val canalLogo: String
    )"""
content = content.replace(old_evento, new_evento)

# Fix ESPM mapping to add canalNome and canalLogo with empty strings (though they will be dropped later if no stream)
content = content.replace("horarioFormatado = horarioFormatado\n                            )", "horarioFormatado = horarioFormatado,\n                                canalNome = \"\",\n                                canalLogo = \"\"\n                            )")

# Fix EmbedTV logic to find the channel BEFORE adding to dict, and ONLY add if channel found
old_embed_logic = """                    val espnMatch = eventosDict[key]
                    
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
                    }"""

new_embed_logic = """                    val espnMatch = eventosDict[key]
                    
                    // ACHAR O CANAL NA LISTA
                    var canalNome = ""
                    var canalLogo = ""
                    var temCanal = false
                    
                    if (playerUrl.isNotEmpty()) {
                        val slug = playerUrl.substringAfterLast("/").lowercase()
                        val slugLimpo = slug.replace("-", "").replace(" ", "")
                        val channel = CATALOG.firstOrNull { it.name.lowercase().replace(" ", "") == slugLimpo }
                            ?: CATALOG.firstOrNull { it.name.lowercase().contains(slugLimpo) }
                        
                        if (channel != null) {
                            canalNome = channel.name
                            canalLogo = channel.logo ?: ""
                            temCanal = true
                        }
                    }
                    
                    if (temCanal) {
                        if (espnMatch != null) {
                            eventosDict[key] = espnMatch.copy(playerUrl = playerUrl, canalNome = canalNome, canalLogo = canalLogo)
                        } else {
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
                                horarioFormatado = horarioFormatado,
                                canalNome = canalNome,
                                canalLogo = canalLogo
                            )
                        }
                    }"""
content = content.replace(old_embed_logic, new_embed_logic)

# Final filtering: remove any event that still has no channel
old_sort = """val eventosFinais = eventosDict.values.toList().sortedBy { it.titulo }"""
new_sort = """val eventosFinais = eventosDict.values.filter { it.canalNome.isNotEmpty() }.sortedBy { it.titulo }"""
content = content.replace(old_sort, new_sort)

# Update ViewHolder mapping
old_viewholder_fields = """        val timeFora: TextView = view.findViewById(R.id.eventoTimeFora)
        val horario: TextView = view.findViewById(R.id.eventoHorario)
        val imgLiga: ImageView = view.findViewById(R.id.imgLiga)
        val imgCasaItem: ImageView = view.findViewById(R.id.imgTimeCasaItem)
        val imgForaItem: ImageView = view.findViewById(R.id.imgTimeForaItem)"""

new_viewholder_fields = """        val timeFora: TextView = view.findViewById(R.id.eventoTimeFora)
        val horario: TextView = view.findViewById(R.id.eventoHorario)
        val imgLiga: ImageView = view.findViewById(R.id.imgLiga)
        val imgCasaItem: ImageView = view.findViewById(R.id.imgTimeCasaItem)
        val imgForaItem: ImageView = view.findViewById(R.id.imgTimeForaItem)
        val imgCanalItem: ImageView = view.findViewById(R.id.imgCanalItem)
        val textoCanalItem: TextView = view.findViewById(R.id.textoCanalItem)"""
content = content.replace(old_viewholder_fields, new_viewholder_fields)

old_bind = """            if (ev.ligaLogo.isNotEmpty()) holder.imgLiga.load(ev.ligaLogo) else holder.imgLiga.setImageDrawable(null)
            if (ev.timeCasaLogo.isNotEmpty()) holder.imgCasaItem.load(ev.timeCasaLogo) else holder.imgCasaItem.setImageDrawable(null)
            if (ev.timeForaLogo.isNotEmpty()) holder.imgForaItem.load(ev.timeForaLogo) else holder.imgForaItem.setImageDrawable(null)"""

new_bind = """            if (ev.ligaLogo.isNotEmpty()) holder.imgLiga.load(ev.ligaLogo) else holder.imgLiga.setImageDrawable(null)
            if (ev.timeCasaLogo.isNotEmpty()) holder.imgCasaItem.load(ev.timeCasaLogo) else holder.imgCasaItem.setImageDrawable(null)
            if (ev.timeForaLogo.isNotEmpty()) holder.imgForaItem.load(ev.timeForaLogo) else holder.imgForaItem.setImageDrawable(null)
            
            holder.textoCanalItem.text = ev.canalNome
            if (ev.canalLogo.isNotEmpty()) holder.imgCanalItem.load(ev.canalLogo) else holder.imgCanalItem.setImageDrawable(null)"""
content = content.replace(old_bind, new_bind)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "w") as f:
    f.write(content)

