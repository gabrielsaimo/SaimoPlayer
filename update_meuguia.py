import re

with open('Sources/MeuGuia.swift', 'r') as f:
    content = f.read()

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
}

# The codes dictionary is a block we can just append to.
# Wait, let's find the closing bracket of the codes dictionary and insert it before.

match = re.search(r'static let codes: \[String: String\] = \[(.*?)\]', content, flags=re.DOTALL)
if match:
    existing_codes = match.group(1)
    
    # Check which codes are missing
    for name, code in new_codes.items():
        if f'"{name}"' not in existing_codes:
            existing_codes += f', "{name}": "{code}"'
            
    content = content[:match.start(1)] + existing_codes + content[match.end(1):]
    
with open('Sources/MeuGuia.swift', 'w') as f:
    f.write(content)
