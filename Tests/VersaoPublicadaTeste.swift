import Foundation
import CryptoKit

nonisolated(unsafe) var falhas = 0
func conferir(_ ok: Bool, _ nome: String) {
    if !ok { falhas += 1; print("FALHOU: \(nome)") } else { print("ok: \(nome)") }
}
let h64 = String(repeating: "ab", count: 32)
func json(url: String, sha: String? = h64, tag: String = "v2.4.0") -> Data {
    let s = sha.map { ",\"sha256\":\"\($0)\"" } ?? ""
    return Data("""
    {"versao":"2.4.0","tag":"\(tag)","notas":"n","arquivos":{"mac":{"nome":"SaimoTV.dmg","url":"\(url)","bytes":123\(s)}}}
    """.utf8)
}
let bom = "https://github.com/dono/repo/releases/download/v2.4.0/SaimoTV.dmg"
let v = VersaoPublicada.ler(json(url: bom))
conferir(v?.numero == "2.4.0" && v?.tamanho == 123 && v?.sha256 == h64, "parse basico")
conferir(v?.pagina?.absoluteString == "https://github.com/dono/repo/releases/tag/v2.4.0", "pagina derivada")
conferir(VersaoPublicada.ler(json(url: bom, sha: nil))?.sha256 == nil, "sem sha256 ok")
conferir(VersaoPublicada.ler(json(url: bom, sha: "xyz")) == nil, "sha256 malformado recusa")
conferir(VersaoPublicada.ler(json(url: bom, tag: "beta-v2")) == nil, "tag ruim")
conferir(VersaoPublicada.ler(Data("lixo".utf8)) == nil, "json invalido")
conferir(VersaoPublicada.ler(Data("{}".utf8)) == nil, "sem arquivos")
for ruim in ["http://github.com/d/r/releases/download/v1/a.dmg",
             "https://github.com.evil.test/d/r/releases/download/v1/a.dmg",
             "https://evil.test/github.com/d/r/releases/download/v1/a.dmg",
             "https://github.com@evil.test/d/r/releases/download/v1/a.dmg",
             "https://github.com/d/r/archive/v1.zip",
             "https://github.com/d/r/releases/latest",
             "https://raw.githubusercontent.com/d/r/main/a.dmg"] {
    conferir(VersaoPublicada.ler(json(url: ruim)) == nil, "recusa \(ruim)")
}
for r in ["https://objects.githubusercontent.com/x", "https://release-assets.githubusercontent.com/x"] {
    conferir(VersaoPublicada.redirecionamentoPermitido(URL(string: r)!), "redirect ok \(r)")
}
for r in ["https://objects.githubusercontent.com.evil.test/x", "http://objects.githubusercontent.com/x",
          "https://evil.test/x"] {
    conferir(!VersaoPublicada.redirecionamentoPermitido(URL(string: r)!), "redirect recusa \(r)")
}
conferir(Atualizacao.maisNova("2.10.0", que: "2.9.3"), "maisNova")

// sha256: arquivo com rodape koly
let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var dados = Data(repeating: 7, count: 2000); dados.append(Data("koly".utf8)); dados.append(Data(repeating: 0, count: 508))
let arq = dir.appendingPathComponent("a.dmg"); try! dados.write(to: arq)
let certo = SHA256.hash(data: dados).map { String(format: "%02x", $0) }.joined()
conferir(BaixadorDeAtualizacao.pronto(arq, tamanho: nil, sha256: certo), "sha256 confere")
conferir(!BaixadorDeAtualizacao.pronto(arq, tamanho: nil, sha256: h64), "sha256 diferente recusa")
try? FileManager.default.removeItem(at: dir)
conferir(Atualizacao.enderecoDoAnuncio == "https://github.com/saimo-tv/saimo-downloads/releases/latest/download/versao.json",
         "endereco fixo do anuncio")
exit(falhas == 0 ? 0 : 1)
