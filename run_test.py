import subprocess
import urllib.request
import re

def test_url(url, headers=None):
    cmd = ["curl", "-s", "-o", "/dev/null", "--max-time", "15", "-L", "-r", "0-4096", "-w", "%{http_code}"]
    if headers:
        if "User-Agent" in headers:
            cmd.extend(["-A", headers["User-Agent"]])
        if "Referer" in headers:
            cmd.extend(["-e", headers["Referer"]])
    cmd.append(url)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return res.stdout.strip()
    except:
        return "000"

def parse_catalogo():
    with open("catalogo.txt", "r") as f:
        content = f.read()
    
    channels = {}
    current_name = None
    current_variants = []
    
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        if ":" not in line: continue
        field, value = line.split(":", 1)
        field = field.strip().lower()
        value = value.strip()
        
        if field == "canal":
            if current_name and current_variants:
                channels[current_name] = current_variants
            current_name = value
            current_variants = []
        elif field == "fonte":
            current_variants.append({"url": value, "headers": {}})
        elif field == "referer":
            if current_variants:
                current_variants[-1]["headers"]["Referer"] = value
        elif field == "agente":
            if current_variants:
                current_variants[-1]["headers"]["User-Agent"] = value
                
    if current_name and current_variants:
        channels[current_name] = current_variants
        
    return channels

def parse_canais():
    with open("canais.txt", "r") as f:
        content = f.read()
        
    channels = {}
    current_name = None
    
    for line in content.splitlines():
        line = line.strip()
        if not line: continue
        
        if line.startswith("#EXTINF:"):
            match = re.search(r'tvg-id="([^"]+)"', line)
            if match:
                current_name = match.group(1)
            else:
                current_name = re.sub(r"\s*\([^)]+\)$", "", line.split(",", 1)[-1]).strip()
        elif not line.startswith("#"):
            if current_name:
                if current_name not in channels:
                    channels[current_name] = []
                channels[current_name].append({"url": line, "headers": {}})
                
    return channels

def main():
    catalogo = parse_catalogo()
    canais = parse_canais()
    
    import concurrent.futures as cf
    
    tasks = []
    # Test catalogo
    for name, variants in catalogo.items():
        for i, v in enumerate(variants):
            tasks.append(("catalogo.txt", name, i, v))
            
    # Test canais
    for name, variants in canais.items():
        for i, v in enumerate(variants):
            tasks.append(("canais.txt", name, i, v))
            
    results = {}
    
    def run_task(t):
        source, name, i, v = t
        code = test_url(v["url"], v["headers"])
        return (source, name, i, v, code)
        
    print(f"Testing {len(tasks)} links...")
    with cf.ThreadPoolExecutor(max_workers=16) as pool:
        for res in pool.map(run_task, tasks):
            source, name, i, v, code = res
            if not code.startswith("2") and not code.startswith("3"):
                print(f"DEAD [{code}] {source} - {name}: {v['url']}")

if __name__ == "__main__":
    main()
