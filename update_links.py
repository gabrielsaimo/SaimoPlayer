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
