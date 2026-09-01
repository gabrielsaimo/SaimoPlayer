import re

with open('Sources/MeuGuia.swift', 'r') as f:
    content = f.read()

new_codes = {
    "Arte 1": "BQ5",
    "TLC": "TRV",
}

match = re.search(r'static let codes: \[String: String\] = \[(.*?)\]', content, flags=re.DOTALL)
if match:
    existing_codes = match.group(1)
    for name, code in new_codes.items():
        if f'"{name}"' not in existing_codes:
            existing_codes += f', "{name}": "{code}"'
            
    content = content[:match.start(1)] + existing_codes + content[match.end(1):]
    
with open('Sources/MeuGuia.swift', 'w') as f:
    f.write(content)

print("Updated MeuGuia.swift")
