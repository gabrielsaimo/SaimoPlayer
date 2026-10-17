import urllib.request
urls = [
    "https://futebolplayhd.stream/api/events",
    "https://futemax.to/api/matches",
    "https://embedtv.cc/api/events",
    "https://futebot.net/api/games",
    "https://api.the-odds-api.com/v4/sports",
]

for url in urls:
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        res = urllib.request.urlopen(req, timeout=3)
        print(url, "->", res.status)
    except Exception as e:
        print(url, "->", str(e))
