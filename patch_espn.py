import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "r") as f:
    content = f.read()

old_urls = """                val espnUrls = listOf(
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.2/scoreboard"
                )"""

new_urls = """                val espnUrls = listOf(
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.2/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/ita.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/ger.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/conmebol.libertadores/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/conmebol.sudamericana/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/volleyball/mens-college-volleyball/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/scoreboard"
                )"""

content = content.replace(old_urls, new_urls)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "w") as f:
    f.write(content)

