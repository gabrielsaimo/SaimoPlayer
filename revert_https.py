import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "r", encoding="utf-8") as f:
    content = f.read()

# Revert to the original forms
content = content.replace("https://45.162.64.114/", "http://45.162.64.114/")
content = content.replace("https://138.204.86.4/", "http://138.204.86.4:8080/")

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoPlayer/catalogo.txt", "w", encoding="utf-8") as f:
    f.write(content)

