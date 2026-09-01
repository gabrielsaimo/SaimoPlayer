import re

with open('../SaimoTV-Android/app/src/main/java/br/com/saimo/tv/MeuGuia.kt', 'r') as f:
    content = f.read()

new_codes = {
    "Arte 1": "BQ5",
    "TLC": "TRV",
}

match = re.search(r'val CODES: Map<String, String> = mapOf\((.*?)\)', content, flags=re.DOTALL)
if match:
    existing_codes = match.group(1)
    for name, code in new_codes.items():
        if f'"{name}"' not in existing_codes:
            existing_codes += f', "{name}" to "{code}"'
            
    content = content[:match.start(1)] + existing_codes + content[match.end(1):]
    
with open('../SaimoTV-Android/app/src/main/java/br/com/saimo/tv/MeuGuia.kt', 'w') as f:
    f.write(content)

print("Updated MeuGuia.kt")
