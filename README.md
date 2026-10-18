<div align="center">

<a href="https://saimo-tv.pages.dev"><img src="https://raw.githubusercontent.com/gabrielsaimo/gabrielsaimo/main/saimo-tv/banner.svg" alt="Saimo TV: canais ao vivo, filmes e séries em qualquer tela" width="100%"></a>

<h1>Saimo TV</h1>

### canais ao vivo, filmes e séries — na TV, no celular, no computador e no navegador

<p>
  <a href="https://github.com/gabrielsaimo/SaimoPlayer/releases/latest">
    <img src="https://img.shields.io/github/v/release/gabrielsaimo/SaimoPlayer?label=vers%C3%A3o" alt="Versão">
  </a>
  <a href="https://github.com/gabrielsaimo/SaimoPlayer/releases">
    <img src="https://img.shields.io/github/downloads/gabrielsaimo/SaimoPlayer/total?label=downloads" alt="Downloads">
  </a>
</p>

<p>
  <img src="https://img.shields.io/badge/Swift-FA7343?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Kotlin-7F52FF?logo=kotlin&logoColor=white" alt="Kotlin">
  <img src="https://img.shields.io/badge/Rust-000000?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/React-20232A?logo=react&logoColor=61DAFB" alt="React">
  <img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python">
</p>

</div>

<p align="center">
  Saimo TV: <a href="https://github.com/gabrielsaimo/SaimoTV-Android">TV Box</a> · <a href="https://github.com/gabrielsaimo/Saimo-Cell-V2">Celular</a> · <a href="https://github.com/gabrielsaimo/SaimoWin">Windows</a> · <b>Mac e catálogo</b> · <a href="https://github.com/gabrielsaimo/Saimo-TV">Site</a> · <a href="https://github.com/gabrielsaimo">todos os apps</a>
</p>

## Sobre

Este repositório é o centro do Saimo TV: o **app do Mac**, a **lista de canais e
o acervo publicados** (que todos os apps leem daqui), os scripts que mantêm esses
dados e o **release único** que distribui todos os apps.

Versão atual: **2.0.0** — [notas da versão](https://github.com/gabrielsaimo/SaimoPlayer/releases/tag/v2.0.0).

## Os apps

| Plataforma | Onde está o código | Download |
|---|---|---|
| TV Box / Android TV / Google TV | [SaimoTV-Android](https://github.com/gabrielsaimo/SaimoTV-Android) | `SaimoTV.apk` |
| Celular Android | [Saimo-Cell-V2](https://github.com/gabrielsaimo/Saimo-Cell-V2) | `SaimoCell.apk` |
| Windows | [SaimoWin](https://github.com/gabrielsaimo/SaimoWin) | `SaimoTV-Instalador.msi` |
| macOS | este repositório (`Sources/`) | `SaimoTV.dmg` |
| Navegador | [Saimo-TV](https://github.com/gabrielsaimo/Saimo-TV) | <https://saimo-tv.pages.dev> |

Os instaladores saem juntos em
[Releases](https://github.com/gabrielsaimo/SaimoPlayer/releases/latest).

### De onde o app Mac lê catálogos e atualizações

O app não aponta para o GitHub: usa dois endereços estáveis, definidos num só
lugar (`Sources/Enderecos.swift`), para o repositório poder mudar de conta sem
quebrar quem já instalou.

- `https://saimo-canais.pages.dev/`: `catalogo.txt`, `canais.txt`,
  `restritos.txt`, `radios.txt` e `versao.json`.
- `https://saimo-filmes.pages.dev/`: espelho da pasta `vod/` (índice, filmes,
  séries, destaques, fichas, gêneros, imdb).

A atualização lê `versao.json` (`arquivos.mac.url`, `bytes`, `sha256`). O app só
aceita um instalador `https` em `github.com/<dono>/<repo>/releases/download/…`
(redirecionando apenas para a CDN do GitHub) e recusa o arquivo se o SHA-256
não bater. Se `versao.json` não puder ser lido, é como "sem atualização".
`scripts/testar_versao.sh` testa isso sem rede.

## O que todos têm

- Canais ao vivo com várias fontes por canal e troca automática quando uma cai
- Ao vivo nunca pausa, em nenhum app: pausa só existe em filme e série
- Guia de programação (meuguia.tv, guiadetv e feeds XMLTV)
- Filmes, séries, animes e doramas com ficha, elenco e episódios
- Pular abertura e recapitulação com tempos do [TheIntroDB](https://theintrodb.org)
- Próximo episódio nos créditos e continuar de onde parou
- O episódio seguinte (automático, botão ou painel; na tela da série vai no topo da escolha) toca pela
  mesma fonte que vinha tocando: a do mesmo provedor, senão a da mesma posição,
  senão a ordem de sempre; as outras ficam de reserva (`FontePreferida.swift`)
- Favoritos, busca, áudio, legendas e qualidade; filmes e séries ganham legendas do
  OpenSubtitles (pt-BR, pt-PT, inglês, espanhol) com ajuste de sincronia, sem chave
  nem cadastro (`Sources/Legendas.swift`)

## App do Mac

SwiftUI + AVFoundation. O AVFoundation não abre DASH nem HEVC em TS, então o app
tem um proxy HTTP local (`ProxyServer.swift`) e um ffmpeg embutido
(`Remuxer.swift`) que remontam o que ele recusa. Também tem PiP, AirPlay e
Chromecast (`Cast.swift`).

Layout (`Tema.swift`, `BarraDoTopo.swift`, `Fileiras.swift`, `TelasDoAcervo.swift`,
`AoVivo.swift`): o mesmo da TV Box, refeito para mouse, teclado e janela de
qualquer tamanho, com Liquid Glass no macOS 26 (material translúcido no 15).
No topo, a barra de vidro com o ícone, as abas (Buscar, Início, Ao vivo, Eventos,
On Demand, Favoritos, Rádios), a engrenagem dos ajustes e o relógio; a aba aberta
é uma cápsula que desliza até a escolhida, e ⌘1 a ⌘8 (menu Ir) levam a cada uma.
O app abre no Início (ou no último canal, se os Ajustes mandarem):

- Início, On Demand, as páginas de Filmes, Séries, Animes e Doramas, Eventos e
  Rádios são telas em fileiras: o título sob o ponteiro em destaque no alto, com
  nota, ano, temporadas, gêneros, sinopse e a imagem larga dele ao fundo; as
  fileiras correm para o lado (setas de vidro aparecem com o mouse sobre elas).
  Início: Continue assistindo, Ao vivo agora (cartões largos com logo, selo e o
  programa no ar), Favoritos e os destaques. On Demand: cartões das quatro
  categorias com colagem de capas, Continue assistindo, destaques, filmes por
  gênero e o "de A a Z" de cada uma. Cada categoria tem Lançamentos, uma fileira
  por gênero com "Ver todos" e "Todos de A a Z".
- A grade de A a Z (e Favoritos) tem as letras numa coluna de vidro, gênero,
  ordem (A a Z ou mais novos primeiro) e busca no alto.
- Ao vivo é o vídeo com a lista de canais de vidro à esquerda (⇧⌘L ou o botão da
  barra de controles): número, logo, nome, programa e progresso, categorias em
  pílulas e busca; no canto, o cartão do programa no ar. Controles, barra do
  tempo de filme e painel de episódios também são de vidro. A lista em janela
  separada continua nos Ajustes.
- Eventos: o jogo sob o ponteiro em destaque e fileiras por horário, com selo
  (ao vivo com placar ou horário), logo da liga, escudos e canal.
- Rádios (`Radios.swift`, `TelaRadios.swift`): a mesma lista da TV
  (`vod/radios.txt`), em fileiras de ouvidas por último, por estilo e de A a Z;
  a que toca aparece no alto com o equalizador e na barra do topo. Toca num
  player só dela, e o ao vivo volta (e a rádio para) ao abrir Ao vivo.
- Buscar: filmes, séries, animes, doramas e canais enquanto se digita, sem
  ligar para acento, com as buscas recentes.
- Ajustes: reprodução, o que abrir ao iniciar, lista em janela separada,
  importar/adicionar/exportar canais, guia e atualização.

Na 2.0: botão de pular abertura, cartão do próximo episódio (Return assiste,
Esc dispensa), troca de fonte quando o arquivo "termina" cedo demais e abertura
no último canal assistido.

Abertura (`Abertura.swift`): ao abrir, a animação do logo (`abertura/abertura-h.mp4`,
copiada para o app pelo `build.sh`) cobre a janela inteira, barra de título e
controles inclusive, sem som e com o fundo já no azul-marinho dela para não
piscar. O último canal abre por baixo, mudo, e a lista de canais espera a
abertura sair. Clique ou qualquer tecla pula; no fim, esmaece para o app. Se o
vídeo não começar em 1,5 s, a abertura sai da frente.

Multi tela (`MultiTela.swift`): dois canais ao vivo lado a lado, pelo botão da
barra de controles ou em Vídeo > Multi tela. Só a tela ativa (borda colorida)
tem som e é ela que a lista e as setas trocam; cada uma mantém a troca de fonte.
Abrir o acervo (filmes, séries etc.) para o ao vivo nas duas telas, e fechá-lo
volta ao último canal.

Episódios sem sair do vídeo (`PainelEpisodios.swift`): com um episódio no ar, o
botão de episódios da barra de controles (ou a tecla E) abre um painel ao lado,
com o vídeo tocando por trás. Ele abre na temporada em que se está, com o episódio
no ar marcado e à vista; troca de temporada pelo seletor; cada linha tem nome,
imagem e duração (TMDB), progresso e a marca de assistido. Um clique troca de
episódio pelo mesmo caminho do próximo episódio; Esc ou clicar fora fecha. No
acervo, a série que está tocando abre rolada até o episódio no ar, marcado.

Série no acervo (`SerieTela.swift`): como na TV Box, ficha e episódios numa tela
só. Imagem larga ao fundo, capa, logo do título (TMDB), selos, gêneros e
sinopse; embaixo, temporadas em pílulas (e Dublado/Legendado quando há os dois)
e os episódios em cartões com a imagem da cena, nome, resumo, duração, progresso
e a marca de assistido, com setas para andar na fileira. Abre na temporada em
que se está, com o episódio a continuar marcado; o botão grande diz "Continuar
T2 E3" e toca ele. O elenco segue embaixo, como na ficha.

Central de Controle (`TocandoAgora.swift`): o que está no ar aparece no "tocando
agora" do macOS e nos apps que o leem. Canal ao vivo vai com a logo e o programa
do guia; filme e episódio com a logo do título do TMDB (ou a capa, sem logo),
nome do episódio, duração e posição. Pausar, pular 10 s e arrastar a posição
valem só em filme e série; ao vivo não pausa.

Atualização (`Atualizacao.swift`, `BaixadorDeAtualizacao.swift`): achada uma
versão nova, o DMG baixa por trás para o cache do app, retomando se a rede cair
e conferido pelo tamanho e o SHA-256 que o GitHub publica. O convite mostra o
andamento; "Atualizar agora" abre o DMG e fecha o app, e é só arrastar o Saimo
TV para Aplicativos. Se o download falhar, o botão abre a página da versão.

Eventos (`Events.swift`, seção Eventos do acervo): a mesma tela do TV Box. Junta a
agenda da embedtv e a do monitor (`/v1/eventos`: jogos da CazéTV, Disney+, Prime,
Paramount+, GOAT, ge tv, N Sports e SportyNet, sem repetir) com os placares da ESPN (23 ligas, buscados juntos) e mostra só
os jogos que passam num canal da lista (adultos fora; encerrados saem), agrupados
em Ao vivo agora, Começa em breve, Hoje mais tarde, Amanhã e Próximos dias. Cada
cartão traz liga, horário ou "AO VIVO" com o tempo de jogo, escudos, placar e o
canal; clicar abre o canal ao vivo. Só busca com a tela aberta e o app na
frente: na hora ao abrir (se a última busca tem mais de um minuto) e depois a cada
três minutos.

### Telemetria por amostra

O monitor é cobrado por pedido, então só uma fatia estável dos aparelhos fala
com ele (`Amostra.swift`, `Telemetria.swift`). A conta é a mesma do servidor
(`amostrado` no `worker.js`): FNV-1a de 32 bits sobre o `deviceId` em
minúsculas, e entra quem tem `hash % 10000 < amostraPct * 100`. O percentual
vem de `telemetria.json` (arquivo estático do monitor, de graça), relido no
máximo uma vez por dia e guardado; sem leitura vale 5%. O `/v1/hello` também
pode mandar `amostraPct`/`amostra`.

- Fora da amostra: nada vai ao monitor (nem olá, nem batida, nem evento), menos
  o relatório de quebra (`crash`), que vale de todos.
- Na amostra: como antes, mas a batida extra (pausa, troca de título, parada)
  sai no máximo uma a cada 30 s; a do relógio segue o `heartbeatSeconds` do
  olá, e a do fechamento sai sempre.
- `/v1/fontes` (servidores desligados): no máximo uma leitura por hora, com a
  última lista boa guardada — reabrir o app dentro da hora não pergunta de novo.
- `/v1/eventos`: ver Eventos acima.

Teste da conta: `./scripts/testar_amostra.sh`.

Saimo Connect (`SaimoConnect.swift`, `ConnectHls.swift`, `Historico.swift`): o
celular com o app Saimo acha e controla o Mac do mesmo jeito que a TV Box, pelo
mesmo protocolo, na porta 8999. O Mac aparece na varredura da rede (`GET /info`)
e no Bonjour (`_saimotv._tcp`) como "Saimo TV - Mac (nome do computador)".
Celular novo só entra depois de alguém clicar Permitir no aviso que aparece na
janela; aprovado uma vez, fica lembrado (Ajustes > Saimo Connect mostra o
endereço, quantos estão autorizados e esquece todos). Pelo celular dá para trocar
de canal (lista, setas, canal +/−, número), ligar a multi tela e escolher a tela
ativa, trocar de fonte, abrir filme ou episódio do acervo, pausar e avançar,
mudar o volume e escolher de qual tela o Mac toca o som. O estado do que está no
ar vai para o celular a cada mudança, com a fonte de verdade de cada tela, e o
celular pode tocar o som de uma tela (ou das duas) no fone, junto com a imagem.
Os números do controle escolhem canal pelo número da lista e não passam pelo
teclado: o código dos extras continua só no teclado do Mac.

O acerto do som é uma régua de tempo comum. Canal com marca de horário
(EXT-X-PROGRAM-DATE-TIME) usa a hora real; canal sem marca passa, no proxy do
próprio Mac, pela régua do `Historico` (porte do da TV Box): a lista guarda os
últimos dois minutos e ganha uma marca sintética contínua por trecho, contada
pela duração real e ancorada no relógio do Mac. O player do Mac toca essa lista,
então a data que o AVPlayer informa já é o instante na régua, e o celular recebe
a mesma lista (mesmas marcas para os mesmos trechos) pelo `GET /hls`. Enquanto
algum celular ouve, o Mac manda a cada segundo onde cada tela está (`pos`);
filme usa a posição. Canal remontado pelo ffmpeg (HEVC em TS, DASH) não tem
régua: o celular toca o som sem o acerto fino.

```bash
./build.sh        # monta build/Saimo TV.app
./make_dmg.sh     # gera o DMG
```

## Dados publicados

Os apps baixam daqui (via raw do GitHub):

- `catalogo.txt` — a lista de canais, com fontes em ordem de preferência. Cada
  fonte pode ter um `nome:` ("Temporada 3", "Legendado") que os apps mostram no
  lugar de "Fonte N"; nos canais 24h ele sai das listas M3U pelo
  `nomear_fontes.py`
- `vod/` — índice e pedaços do acervo de filmes e séries, destaques e fichas
  (gêneros, capas e ids do TMDB)
- `vod/destaques.txt` — as fileiras da tela inicial, uma linha por título:
  `tipo	título	letra	ano	capa	trailer`. O sexto campo é opcional: um
  trailer direto (`.mp4` ou `.m3u8`, nunca página do YouTube), que o TV Box e
  o celular tocam sem som no destaque do topo
- `vod/radios.txt` — as rádios, `nome|endereço|logo`, com o logo opcional.
  Mantida à mão: `gerar_vod.py` preserva o arquivo ao remontar o acervo

Scripts principais:

| Script | Faz |
|---|---|
| `atualizar_tudo.sh` | roda a atualização do acervo duas vezes por dia, às 11h e às 18h (launchd no Mac; o GitHub Actions faz a parte da RedeFlix às 11h17) |
| `gerar_vod.py`, `gerar_generos.py`, `gerar_destaques.py` | geram o acervo, as fichas e as fileiras |
| `atualizar_redeflix.py`, `atualizar_frostview.py` | trazem fontes novas de cada origem; o do FrostView troca a fonte que a API não devolve mais pela nova |
| `atualizar_nixplay.py` | a lista principal de filmes e séries (nixplay, conta só de filmes e séries, sem canais): baixa a M3U, casa cada fonte com o título do acervo pelo id do TMDB e grava em `arquivos-gerados/nixplay/`; o `gerar_vod.py` põe essas fontes em primeiro em cada título e acrescenta os títulos que faltavam. Roda dentro do `atualizar_tudo.sh` |
| `gerar_imdb.py` | publica o id do IMDb de cada título em `vod/imdb/` (fragmentos de 8 KB), para as legendas dos apps |
| `dublar_legendados.py` | procura o dublado do que o acervo só tem legendado (roda dentro do `atualizar_tudo.sh`; `--dublados` refaz tudo) |
| `limpar_fontes.py`, `remove_dead_links.py` | tiram fontes mortas |
| `limpar_canais.py` | testa cada fonte de canal como o app pede, confirma a falha uma segunda vez e, com `--aplicar`, tira as mortas (canal sem fonte sai); erro passageiro (429, 5xx) não mata fonte |
| `fontes_hls.py` | troca as fontes `.ts` das contas Xtream pelo HLS do mesmo canal (`/live/.../ID.m3u8`): o `.ts` é cortado pelo servidor a cada poucos segundos e o canal recarrega; o HLS fica estável |
| `medir_fontes_local.py` | mede a resolução das fontes com ffprobe; `--sem-qualidade` só as que não têm, até duas por servidor |
| `medir_resolucao.py` | mede as fontes HLS pela playlist mestre |
| `fontes-mortas.txt` | fontes do acervo fora do ar (URLs e `servidor: host`); o `gerar_vod.py` tira delas e título sem fonte viva sai. Vem do `testar_fontes_vod.py` |
| `ordenar_fontes.py` | o fallback1.nexustvplay nunca é a primeira opção de um canal que tem outra fonte: fica em segundo, logo depois da primeira fonte de outro servidor ligado no monitor (com `--testar`, a primeira que responde agora); nos canais 24 horas o vivlar.me vem na frente. Rodar depois de qualquer script que mexa no catálogo |
| `nomear_fontes.py` | dá nome às fontes do catálogo a partir das listas M3U ("[S03]" vira "Temporada 3"), para os canais 24h mostrarem a temporada |
| `testar_fontes_vod.py` | testa as fontes do acervo: qualidade de cada uma e quais saíram do ar (só relatório, em `arquivos-gerados/fontes-vod/`) |

## Publicar uma versão

```bash
./release.sh 2.0.0              # marca a versão e publica
./release.sh 2.0.0 --rascunho   # cria como rascunho
```

O script grava a versão no `Info.plist` e no Gradle da TV, monta o DMG, o APK da
TV (assinado com a chave de sempre, para atualizar por cima), o instalador do
Windows e inclui o APK do celular se ele estiver montado. As notas saem de
`build/release/NOTAS.md` quando esse arquivo existe.

Pré-requisitos: repositórios irmãos em `../SaimoTV-Android`, `../SaimoWin` e
`../Saimo-Cell-V2`; JDK 17; `wixl` (`brew install msitools`); `gh` logado.

## Avisos

- Fontes externas podem sair do ar sem aviso; o sistema de fontes reserva existe
  por isso.
- Respeite direitos autorais e de distribuição do conteúdo.
- Não coloque tokens, credenciais ou dados pessoais em catálogos e scripts.
