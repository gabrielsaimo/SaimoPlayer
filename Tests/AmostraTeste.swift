// Teste da conta da amostra (a mesma do worker.js do monitor).
// Rodar: ./scripts/testar_amostra.sh
let a = "79a275ad-b783-488c-8e18-2439ff3aed1c", b = "db09f237-fffa-40c7-94c5-35eddcad6970"
precondition(Amostra.fnv1a(a) == 3670190157)
precondition(Amostra.fnv1a(b) == 2926602047)
precondition(Amostra.amostrado(a, pct: 5))
precondition(Amostra.amostrado(a.uppercased(), pct: 5))
precondition(!Amostra.amostrado(b, pct: 5))
precondition(Amostra.amostrado(b, pct: 100))
precondition(!Amostra.amostrado(a, pct: 0))
print("ok")
