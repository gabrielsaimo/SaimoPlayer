# Catálogos fixos e mudança de GitHub

## Como é agora

Os apps **não leem o GitHub**. Leem dois endereços fixos, que são arquivos
estáticos no Cloudflare Pages (não passam pelo Worker, então não contam como
pedido e a banda é de graça):

| Link | O que serve | Quem lê |
|---|---|---|
| `https://saimo-canais.pages.dev/` | `catalogo.txt`, `canais.txt`, `restritos.txt`, `radios.txt`, `versao.json` | todos os apps, o site e o monitor |
| `https://saimo-filmes.pages.dev/` | espelho exato de `vod/` (acervo, capas, fichas, destaques, novidades, imdb…) | todos os apps e o site |

`versao.json` é o que os apps leem para saber que há versão nova e de onde baixar
(link do release, tamanho e SHA-256 de cada arquivo). Quem o escreve é o
`release.sh`, depois de os arquivos existirem.

Mudar de GitHub não muda nenhum endereço que um app usa.

## De onde os links são alimentados

`scripts/publicar_catalogos.sh` monta `arquivos-gerados/publico/{canais,filmes}` a
partir deste repositório e envia com `wrangler pages deploy` (só vai o que
mudou). Ele roda em três lugares, e um cobre o outro:

1. `atualizar_tudo.sh` (agendado no Mac às 11h e 18h): no começo, para os canais,
   e no fim, para tudo.
2. O fluxo `publicar-catalogos.yml` (GitHub Actions), a cada push que mexe em
   `catalogo.txt`, `canais.txt`, `restritos.txt`, `versao.json` ou `vod/**` — é ele
   que publica uma troca de ordem das fontes feita pelo painel do monitor.
3. `release.sh`, ao anunciar uma versão nova.

Fora do `vod/` não sobe nada de `mgeb/` e `fenix/` (entradas dos geradores, com
arquivos acima do limite de 25 MB do Pages).

Autenticação: `CLOUDFLARE_API_TOKEN` (permissão **Cloudflare Pages: Edit**) ou o
`wrangler login` desta máquina. No GitHub, é o segredo `CLOUDFLARE_API_TOKEN` do
repositório (mais `CLOUDFLARE_ACCOUNT_ID`).

## Mudar para outro GitHub

Tudo está em `scripts/migrar-github.sh NOVO_DONO` — por padrão só **simula**; com
`--executar` faz de verdade, etapa por etapa (`--etapa N`). Antes:

1. Criar a conta (ou organização) nova no GitHub e `gh auth login` com ela.
2. Criar o token da Cloudflare (acima) e `export CLOUDFLARE_API_TOKEN=…`.
3. Opcional, para o espelho do GitHub antigo: um token fine-grained da conta
   antiga, só com "Contents: Read and write" no repositório antigo,
   `export LEGADO_TOKEN=…`.

O script cria os repositórios (código **privado**; só `saimo-downloads`, que
guarda os APK/DMG/zip, é público — a atualização precisa baixar sem login), envia
o histórico inteiro, deixa o antigo como remote `legado`, guarda os segredos,
troca o repositório fixo do monitor e atualiza os links dos READMEs.

### O GitHub antigo continua vivo (a ponte)

Os apps até a 2.3.x leem o catálogo e as atualizações **direto do GitHub antigo**.
Até esse pessoal atualizar, o antigo precisa continuar recebendo:

- o catálogo: o fluxo `espelhar-legado.yml` (segredo `LEGADO_TOKEN`) e o
  `git push legado` do `atualizar_tudo.sh` empurram do novo para o antigo;
- as versões: `release.sh` publica o mesmo release nos dois (principal e
  `legado`). A 2.4.0 publicada no antigo é a que leva as instalações antigas
  para uma versão que lê `versao.json`.

Aposente o antigo só quando o painel do monitor (aba Versões) mostrar que quase
ninguém está em 2.3.x e antes disso.

### O site

O site (`saimo-tv.pages.dev`) é um projeto Pages ligado ao GitHub antigo, e a
Cloudflare não deixa trocar o repositório de um projeto. A troca é apagar e
recriar o mesmo nome e publicar por upload direto (`Saimo-TV/scripts/publicar_site.sh`):
~1 minuto fora do ar. Passo a passo em `Saimo-TV/docs/TROCA-DO-SITE.md`. Pode
ser feita a qualquer hora, antes ou depois do resto.

## Voltar atrás

Nada é apagado. Se algo der errado: os apps 2.3.x seguem no GitHub antigo, e os
dois links podem ser republicados a qualquer momento com
`./scripts/publicar_catalogos.sh`.
