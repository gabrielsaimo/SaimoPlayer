import re

with open('catalogo.txt', 'r') as f:
    text = f.read()

# Find the Sony Channel block
pattern = re.compile(r'(canal: Sony Channel\nlogo: https://mondrian\.claro\.com\.br/channels/inverse/sony\.png\n)(fonte: https://video37\.mais\.uol\.com\.br/live/279\.mpd\nreferer: https://painel\.play\.uol\.com\.br/\nagente: Mozilla/5\.0[^\n]+\nchave: [^\n]+\n)')

new_source = "fonte: https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sony/__index.m3u8?sv=207&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787840421-CoMPQTpI1T81KNG3ezpJhbubzfOqOodNk9aR1CEItWw%3D\n"

def repl(m):
    return m.group(1) + new_source + m.group(2)

new_text, count = pattern.subn(repl, text)
if count == 0:
    print("Could not find Sony Channel block to update")
else:
    with open('catalogo.txt', 'w') as f:
        f.write(new_text)
    print("Updated catalogo.txt")
