import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/atualizacao.rs", "r") as f:
    content = f.read()

content = content.replace('pub const ARQUIVO: &str = "SaimoTV-Instalador.msi";', 'pub const ARQUIVO: &str = "SaimoTV-Windows.zip";')
content = content.replace('SaimoTV-Instalador.msi', 'SaimoTV-Windows.zip')

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/atualizacao.rs", "w") as f:
    f.write(content)

