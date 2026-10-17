import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace("http://45.162.64.114/", "https://45.162.64.114/")
content = content.replace("http://138.204.86.4:8080/", "https://138.204.86.4/")

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "w", encoding="utf-8") as f:
    f.write(content)

