import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "r") as f:
    content = f.read()

old_fields = """    private class EventoViewHolder(v: View) : RecyclerView.ViewHolder(v) {
        val timeCasa: TextView = v.findViewById(R.id.eventoTimeCasa)
        val timeFora: TextView = v.findViewById(R.id.eventoTimeFora)
        val horario: TextView = v.findViewById(R.id.eventoHorario)
        val imgLiga: ImageView = v.findViewById(R.id.imgLiga)
        val imgCasaItem: ImageView = v.findViewById(R.id.imgTimeCasaItem)
        val imgForaItem: ImageView = v.findViewById(R.id.imgTimeForaItem)
    }"""

new_fields = """    private class EventoViewHolder(v: View) : RecyclerView.ViewHolder(v) {
        val timeCasa: TextView = v.findViewById(R.id.eventoTimeCasa)
        val timeFora: TextView = v.findViewById(R.id.eventoTimeFora)
        val horario: TextView = v.findViewById(R.id.eventoHorario)
        val imgLiga: ImageView = v.findViewById(R.id.imgLiga)
        val imgCasaItem: ImageView = v.findViewById(R.id.imgTimeCasaItem)
        val imgForaItem: ImageView = v.findViewById(R.id.imgTimeForaItem)
        val imgCanalItem: ImageView = v.findViewById(R.id.imgCanalItem)
        val textoCanalItem: TextView = v.findViewById(R.id.textoCanalItem)
    }"""

content = content.replace(old_fields, new_fields)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "w") as f:
    f.write(content)

