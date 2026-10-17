import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "r") as f:
    content = f.read()

old_urls_match = re.search(r'val espnUrls = listOf\((.*?)\)', content, re.DOTALL)
if old_urls_match:
    urls_block = old_urls_match.group(1)
    
    # We will just replace the whole espnUrls definition
    new_espn_urls = """val espnUrls = listOf(
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.2/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/arg.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/ksa.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/fra.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/por.1/scoreboard",
                    "https://site.api.espn.com/apis/site/v2/sports/soccer/ned.1/scoreboard",
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
    
    content = content.replace(f"val espnUrls = listOf({urls_block})", new_espn_urls)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoTV-Android/app/src/main/java/br/com/saimo/tv/EventosActivity.kt", "w") as f:
    f.write(content)

