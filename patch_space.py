import re

with open("catalogo.txt", "r") as f:
    content = f.read()

new_link = "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/space/__index.m3u8?sv=133&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787868510-6%2BObhsE359hC%2FAOQO3%2Ba4mM2CydO0agWOf8LsEL8S8c%3D"
pattern = r"(canal: Space\nlogo: https://mondrian.claro.com.br/channels/inverse/space.png\nfonte: ).*"
content = re.sub(pattern, r"\1" + new_link, content)

with open("catalogo.txt", "w") as f:
    f.write(content)
