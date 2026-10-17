import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/main.rs", "r") as f:
    content = f.read()

# Add pip: bool to App
content = content.replace("aba: Aba,", "aba: Aba,\n    pip: bool,")

# Add pip: false to app initialization
content = content.replace("aba: Aba::Canais,", "aba: Aba::Canais,\n            pip: false,")

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/main.rs", "w") as f:
    f.write(content)

