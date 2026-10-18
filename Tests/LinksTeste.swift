import Foundation

// Teste dos endereços das listas, do formulário e do guia.txt. Sem rede.
// Rodar: ./scripts/testar_links.sh
nonisolated(unsafe) var falhas = 0
func conferir(_ ok: Bool, _ nome: String) {
    if !ok { falhas += 1; print("FALHOU: \(nome)") } else { print("ok: \(nome)") }
}

// Normalização
func n(_ s: String) -> Links.Resultado { Links.normalizar(s) }
conferir(n("saimo-canais.pages.dev") == .valido("https://saimo-canais.pages.dev/"), "sem esquema")
conferir(n("https://x.dev/listas/catalogo.txt") == .valido("https://x.dev/listas/"), "arquivo colado")
conferir(n("  https://x.dev/a/  ") == .valido("https://x.dev/a/"), "trim e barra")
conferir(n("http://localhost:8101") == .valido("http://localhost:8101/"), "http com porta")
conferir(n("localhost:8101") == .valido("https://localhost:8101/"), "porta sem esquema")
conferir(n("https://x.dev/pasta?a=1#frag") == .valido("https://x.dev/pasta/"), "query e fragmento")
conferir(n("https://x.dev/catalogo.txt?v=2") == .valido("https://x.dev/"), "arquivo com query")
conferir(n("HTTPS://X.DEV/Listas") == .valido("https://x.dev/Listas/"), "caixa do host")
conferir(n("x.dev/v1.2/lista") == .valido("https://x.dev/v1.2/lista/"), "ponto no meio fica")
conferir(n("") == .vazio && n("   ") == .vazio, "vazio")
for ruim in ["ftp://x.dev/", "https://", "http:///a", "a b.dev", "https://x .dev", "mailto:a@b.c",
             "javascript://x", "https://:80/", "https://x.dev:abc/", "https://-x.dev/"] {
    conferir(n(ruim) == .invalido, "invalido \(ruim)")
}

// Pedido de teste
let pc = Links.pedidoDeTeste(base: "https://x.dev/l/", tipo: .canais)
let pf = Links.pedidoDeTeste(base: "https://x.dev/l/", tipo: .filmes)
conferir(pc?.url?.absoluteString == "https://x.dev/l/catalogo.txt" && pc?.httpMethod == "GET", "pedido canais")
conferir(pf?.url?.absoluteString == "https://x.dev/l/indice.txt", "pedido filmes")
conferir(Links.respostaAceita(200) && !Links.respostaAceita(404) && !Links.respostaAceita(nil), "so 200")

// Decisões de tela
conferir(Links.deveMostrarPrimeiraAbertura(canais: nil, filmes: nil), "pergunta com os dois vazios")
conferir(Links.deveMostrarPrimeiraAbertura(canais: "", filmes: nil), "vazio e nulo")
conferir(!Links.deveMostrarPrimeiraAbertura(canais: "https://a/", filmes: nil), "so canais: nao pergunta")
conferir(!Links.deveMostrarPrimeiraAbertura(canais: nil, filmes: "https://a/"), "so filmes: nao pergunta")
conferir(Links.semEndereco(.filmes, canais: "https://a/", filmes: nil), "filmes sem endereco")
conferir(!Links.semEndereco(.radios, canais: "https://a/", filmes: nil), "radios com endereco")
conferir(Links.mensagemVazia(.canais, canais: nil, filmes: nil)
         == "Nenhum canal. Informe o endereço da lista de canais em Ajustes > Listas.", "mensagem canais")
conferir(Links.mensagemVazia(.canais, canais: "https://a/", filmes: nil).contains("Confira"), "mensagem com endereco")

// Categoria vem do campo
conferir(Categoria.de(declarada: "Esportes") == .esportes, "categoria declarada")
conferir(Categoria.de(declarada: nil) == .outros && Categoria.de(declarada: "") == .outros, "sem categoria: Outros")
conferir(Categoria.de(declarada: "noticias") == .noticias, "categoria sem acento/caixa")
conferir(Categoria.de(declarada: "Coisa Nova") == .outros, "categoria desconhecida: Outros")
let canalSemCat = Channel(name: "SporTV", source: URL(string: "https://a/b.m3u8")!)
conferir(Categoria.de(canalSemCat) == .outros, "nome nao decide categoria")

// guia.txt
let guia = """
# comentario
meuguia\tESPN\tESP
meuguia\tHBO2\tHB2
guiadetv\tespn 2\tespn-2
guiadetv\toutro\thttps://www.guiadetv.com/canal/outro
alias\tsportv 2\tsportv2
feed\t-\thttps://a.test/1.xml
feed\t-\thttps://a.test/2.xml
feed\t-\thttps://a.test/1.xml
feed\t-\tftp://ruim/x
pluto\t-\thttps://p.test/br.xml
desconhecido\tx\ty
meuguia\tsem codigo
"""
let t = GuiaTabelas.ler(guia)
conferir(t.meuguia == ["ESPN": "ESP", "HBO2": "HB2"], "guia meuguia")
conferir(t.guiadetv["espn 2"] == "espn-2" && t.guiadetv.count == 2, "guia guiadetv")
conferir(t.aliases == ["sportv 2": "sportv2"], "guia alias")
conferir(t.feeds.map(\.absoluteString) == ["https://a.test/1.xml", "https://a.test/2.xml"], "feeds em ordem, sem repetir nem ftp")
conferir(t.pluto?.absoluteString == "https://p.test/br.xml", "pluto")
conferir(GuiaTabelas.ler("").vazia && GuiaTabelas.ler("# so comentario").vazia, "guia vazio")
conferir(GuiaTabelas.paginaDoGuiaDeTv("espn-2")?.absoluteString == "https://www.guiadetv.com/canal/espn-2", "slug vira pagina")
conferir(GuiaTabelas.paginaDoGuiaDeTv("https://x.test/c")?.absoluteString == "https://x.test/c", "endereco inteiro")

// Formulário (sem rede)
@MainActor final class Registro {
    var gravados: [Links.Plano] = []
    var testados: [String] = []
}
@MainActor func formulario(_ r: Registro, testa: @escaping (String, Links.Tipo) -> Bool) -> FormularioListas {
    FormularioListas(testar: { base, tipo in r.testados.append(base + tipo.arquivoDeTeste); return testa(base, tipo) },
                     gravar: { r.gravados.append($0) })
}

let r1 = Registro(), f1 = formulario(r1, testa: { _, _ in true })
f1.canais = "a.dev"; f1.filmes = "b.dev/x/indice.txt"
await f1.salvar()
conferir(f1.fase == .concluido && r1.gravados.count == 1, "salvar com sucesso grava")
conferir(r1.testados == ["https://a.dev/catalogo.txt", "https://b.dev/x/indice.txt"], "testa catalogo e indice")

let r2 = Registro(), f2 = formulario(r2, testa: { _, _ in false })
f2.canais = "a.dev"
await f2.salvar()
conferir(f2.fase == .falhou(Links.erroDeEndereco) && r2.gravados.isEmpty, "falha nao grava")
f2.salvarMesmoAssim()
conferir(f2.fase == .concluido && r2.gravados.count == 1, "salvar mesmo assim grava")

let r3 = Registro(), f3 = formulario(r3, testa: { _, _ in true })
f3.canais = "ftp://x"
await f3.salvar()
conferir(f3.fase == .invalido(Links.erroDeFormato) && r3.gravados.isEmpty && r3.testados.isEmpty,
         "invalido nao testa nem grava")

let r4 = Registro(), f4 = formulario(r4, testa: { _, _ in false })
await f4.salvar()
conferir(f4.fase == .concluido && r4.testados.isEmpty, "tudo em branco: sem rede")

let r5 = Registro()
var vezes = 0
let f5 = formulario(r5, testa: { _, _ in vezes += 1; return vezes > 1 })
f5.filmes = "f.dev"
await f5.salvar()
conferir(f5.fase != .concluido, "primeira tentativa falha")
await f5.tentarDeNovo()
conferir(f5.fase == .concluido && r5.gravados.count == 1, "tentar de novo")

if falhas > 0 { print("\(falhas) falha(s)"); exit(1) }
