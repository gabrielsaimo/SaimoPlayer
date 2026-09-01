import re

new_codes = {
    "AXN": "AXN",
    "canal-brasil": "CBR",
    "Discovery Channel": "DIS",
    "Discovery Home & Health": "HEA",
    "Discovery Science": "DSC",
    "Discovery Turbo": "DTU",
    "E!": "EET",
    "Sony Channel": "SET",
    "Studio Universal": "HAL",
    "Band Sports": "BSP",
    "ESPN 3": "ES3",
    "ESPN 5": "ES5",
    "canal-off": "OFF",
    "Premiere Clubes": "121",
    "Multishow": "MSH",
    "Viva": "VIV",
    "Arte 1": "BQ5",
    "TLC": "TRV",
}

with open('../SaimoTV-Android/app/src/main/java/br/com/saimo/tv/MeuGuia.kt', 'r') as f:
    content = f.read()

match = re.search(r'private val CODES = mapOf\((.*?)\)', content, flags=re.DOTALL)
if match:
    existing_codes = match.group(1)
    for name, code in new_codes.items():
        if f'"{name}"' not in existing_codes:
            existing_codes += f', "{name}" to "{code}"'
            
    content = content[:match.start(1)] + existing_codes + content[match.end(1):]
    
with open('../SaimoTV-Android/app/src/main/java/br/com/saimo/tv/MeuGuia.kt', 'w') as f:
    f.write(content)

print("Updated MeuGuia.kt with all codes")
