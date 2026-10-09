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

Todos os arquivos saem juntos em
[Releases](https://github.com/gabrielsaimo/SaimoPlayer/releases/latest), e cada
app procura a versão nova ali e se oferece para atualizar.

## O que todos têm

- Canais ao vivo com várias fontes por canal e troca automática quando uma cai
- Ao vivo nunca pausa, em nenhum app: pausa só existe em filme e série
- Guia de programação (meuguia.tv, guiadetv e feeds XMLTV)
- Filmes, séries, animes e doramas com ficha, elenco e episódios
- Pular abertura e recapitulação com tempos do [TheIntroDB](https://theintrodb.org)
- Próximo episódio nos créditos e continuar de onde parou
- Favoritos, busca, áudio, legendas e qualidade; filmes e séries ganham legendas do
  OpenSubtitles (pt-BR, pt-PT, inglês, espanhol) com ajuste de sincronia, sem chave
  nem cadastro (`Sources/Legendas.swift`)

## App do Mac

SwiftUI + AVFoundation. O AVFoundation não abre DASH nem HEVC em TS, então o app
tem um proxy HTTP local (`ProxyServer.swift`) e um ffmpeg embutido
(`Remuxer.swift`) que remontam o que ele recusa. Também tem PiP, AirPlay e
Chromecast (`Cast.swift`).

Na 2.0: botão de pular abertura, cartão do próximo episódio (Return assiste,
Esc dispensa), troca de fonte quando o arquivo "termina" cedo demais e abertura
no último canal assistido.

```bash
./build.sh        # monta build/Saimo TV.app
./make_dmg.sh     # gera o DMG
```

## Dados publicados

Os apps baixam daqui (via raw do GitHub):

- `catalogo.txt` — a lista de canais, com fontes em ordem de preferência
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
| `atualizar_tudo.sh` | roda a atualização diária do acervo, às 11h (launchd no Mac; o GitHub Actions faz a parte da RedeFlix às 11h17) |
| `gerar_vod.py`, `gerar_generos.py`, `gerar_destaques.py` | geram o acervo, as fichas e as fileiras |
| `atualizar_redeflix.py`, `atualizar_frostview.py`, `atualizar_fenix.py` | trazem fontes novas de cada origem |
| `gerar_imdb.py` | publica o id do IMDb de cada título em `vod/imdb/` (fragmentos de 8 KB), para as legendas dos apps |
| `dublar_legendados.py` | procura o dublado do que o acervo só tem legendado (roda dentro do `atualizar_tudo.sh`; `--dublados` refaz tudo) |
| `limpar_fontes.py`, `remove_dead_links.py` | tiram fontes mortas |
| `medir_fontes_local.py`, `medir_resolucao.py` | medem as fontes dos canais |
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
