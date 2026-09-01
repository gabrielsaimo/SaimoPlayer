import re

new_channels = [
    ('TLC', 'TLC (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/tlc.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/tlc/__index.m3u8?sv=159&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787853044-2e7yfZ9E4HLlLkenO52EQsxXwMScvSzc%2Fz7HVGyb4HY%3D'),
    ('Sabor & Arte', 'SABOR & ARTE (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/saborarte.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/saboriarte/__index.m3u8?sv=191&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787853630-Ov89o11tjVcIwXD5OirccRAUIFp%2FMvbH4Jf4FTxEQfk%3D'),
    ('Lifetime', 'LIFETIME (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/lifetime.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/lifetime/__index.m3u8?sv=113&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787853741-zDygdvxUnB0jk5ZRw8pCsJ7bj12cXIrRrbIqPz5Uz5c%3D'),
    ('Dog TV', 'DOG TV (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/dogtv.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/dogtv/__index.m3u8?sv=157&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787853817-oSLVhfILeWGj42L8kM4Hg3pHpqso2AwJEAEep4unSSE%3D'),
    ('Curta!', 'CURTA! (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/curta.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/curta/__index.m3u8?sv=147&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787853874-ujpNjiiSw%2BHTQqGM2V5VLixs9Rae8aiCDr0zDkTvrgY%3D'),
    ('Bis', 'BIS (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/bis.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/bis/__index.m3u8?sv=190&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787853962-BcH80%2BN3Fp5W7qiSDY2ne2ahfKlpqlLPDlNfCRnZcm4%3D'),
    ('Arte 1', 'ARTE 1 (ST)', 'VARIEDADES', 'https://api.reidoscanais.ooo/img/arte1.png', 'https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/arte1/__index.m3u8?sv=164&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787854030-oP99H6SqZG3gKONBy9U0QmG2OYVr2atLRezCJ9Irmbg%3D')
]

with open('canais.txt', 'r') as f:
    content = f.read()

for ch_id, ch_name, group, logo, url in new_channels:
    if f'tvg-id="{ch_id}"' not in content:
        content += f'\n#EXTINF:-1 tvg-id="{ch_id}" tvg-logo="{logo}" group-title="{group}", {ch_name}\n{url}\n'

# Sort canais.txt alphabetically
lines = [l for l in content.split('\n') if l.strip()]
channels = []
current_header = ""
for line in lines:
    if line.startswith('#EXTINF'):
        current_header = line
    elif line.startswith('http') and current_header:
        m = re.search(r'tvg-id="([^"]+)"', current_header)
        name = m.group(1).lower() if m else ""
        channels.append((name, current_header, line))
        current_header = ""

channels.sort(key=lambda x: x[0])

with open('canais.txt', 'w') as f:
    f.write('#EXTM3U\n')
    for _, header, url in channels:
        f.write(header + '\n' + url + '\n')

print("Added and sorted in canais.txt")
