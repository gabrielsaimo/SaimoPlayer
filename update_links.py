import re

with open('catalogo.txt', 'r') as f:
    cat = f.read()

# Update Globo RJ
cat = re.sub(
    r'(canal: Globo RJ\nlogo: https://mondrian\.claro\.com\.br/channels/inverse/globo\.png\n)fonte: .*\n',
    r'\g<1>fonte: https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/bobonordeste/__index.m3u8?sv=133&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787852368-bOmCiOUq98lMffRCA9CsqmmFhuivirJhqTJ2OhDRGPk%3D\n',
    cat
)

# Update Globo SP
cat = re.sub(
    r'(canal: Globo SP\nlogo: https://mondrian\.claro\.com\.br/channels/inverse/globo\.png\n)fonte: .*\n',
    r'\g<1>fonte: https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/bobonordeste/__index.m3u8?sv=133&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787852368-bOmCiOUq98lMffRCA9CsqmmFhuivirJhqTJ2OhDRGPk%3D\n',
    cat
)

# Update HBO Mundi (remove referer, agente, chave)
cat = re.sub(
    r'(canal: HBO Mundi\nlogo: https://mondrian\.claro\.com\.br/channels/inverse/hbo-mundi\.png\n)fonte: .*\nreferer: .*\nagente: .*\nchave: .*\n',
    r'\g<1>fonte: https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbomundi/__index.m3u8?sv=100&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787852564-6PukRkQEU48Qq9Rd4zUXQ0wEpP1zEYBJ37IFNWXpXug%3D\n',
    cat
)

with open('catalogo.txt', 'w') as f:
    f.write(cat)


with open('canais.txt', 'r') as f:
    lines = f.readlines()

new_canais = []
skip = False
for line in lines:
    if 'tvg-id="HBO Mundi"' in line:
        skip = True
        continue
    if skip and line.startswith('http'):
        skip = False
        continue
    new_canais.append(line)

with open('canais.txt', 'w') as f:
    f.writelines(new_canais)

print("Updates done!")
