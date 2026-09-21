<div align="center">

# Saimo TV

### entretenimento em todos os dispositivos

<p>
  <a href="https://github.com/royopa/SaimoPlayer/releases/latest">
    <img src="https://img.shields.io/github/v/release/royopa/SaimoPlayer?label=vers%C3%A3o" alt="Versão">
  </a>
  <a href="https://github.com/royopa/SaimoPlayer/releases">
    <img src="https://img.shields.io/github/downloads/royopa/SaimoPlayer/total?label=downloads" alt="Downloads">
  </a>
  <a href="https://github.com/royopa/SaimoPlayer/stargazers">
    <img src="https://img.shields.io/github/stars/royopa/SaimoPlayer?label=estrelas" alt="Estrelas">
  </a>
  <a href="https://github.com/royopa/SaimoPlayer/issues">
    <img src="https://img.shields.io/github/issues/royopa/SaimoPlayer?label=issues" alt="Issues">
  </a>
</p>

<p>
  <img src="https://img.shields.io/badge/Swift-FA7343?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-0D96F6?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/FFmpeg-007808?logo=ffmpeg&logoColor=white" alt="FFmpeg">
  <img src="https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Windows-0078D4?logo=windows&logoColor=white" alt="Windows">
</p>

</div>

## Sobre

O **Saimo TV** é uma aplicação **multiplataforma** para assistir canais ao vivo, filmes, séries e conteúdo VOD, com foco em experiência completa de reprodução e navegação de catálogo em pt-BR.

Este repositório concentra o **cliente principal**, catálogos, playlists, scripts de manutenção e automações. Outros clientes do ecossistema podem existir em projetos relacionados.

## Plataformas

| Plataforma | Formato de distribuição |
| --- | --- |
| macOS | DMG |
| Android TV | APK |
| Android (celular) | APK |
| Windows | ZIP |

## Recursos principais

- TV ao vivo com suporte a múltiplas fontes
- EPG (guia eletrônico de programação)
- Catálogo VOD para filmes e séries
- Favoritos
- Fontes alternativas com fallback
- Seleção de qualidade de vídeo
- Seleção de áudio e legendas
- Tela cheia
- Picture in Picture (PiP)
- AirPlay
- Chromecast
- Google TV
- Processamento com FFmpeg quando necessário

## Demonstração

Para manter a documentação organizada, capturas de tela e mídias de demonstração podem ser adicionadas em:

- `docs/images/`

> Este README não referencia screenshots inexistentes.

## Downloads

- Última versão: [Releases mais recentes](https://github.com/royopa/SaimoPlayer/releases/latest)
- Histórico completo: [Todas as releases](https://github.com/royopa/SaimoPlayer/releases)

Versão mais recente conhecida: **1.6.3**.

## Arquitetura do projeto

```text
SaimoPlayer/
├── Sources/             # Cliente principal em Swift/SwiftUI
├── vod/                 # Dados e índices de VOD
├── *.m3u                # Playlists
├── canais.txt           # Lista de canais
├── catalogo.txt         # Catálogo principal
├── restritos.txt        # Conteúdo restrito/filtrado
├── build.sh             # Build do app macOS
├── make_dmg.sh          # Empacotamento DMG
├── bundle_ffmpeg.py     # Inclusão/empacotamento do FFmpeg
└── release.sh           # Automação de release
```

## Tecnologias

- **Swift** e **SwiftUI** no cliente principal
- **Python** nos scripts de manutenção e automação de dados
- **FFmpeg** para fluxos e compatibilidade de mídia
- Distribuição para **macOS**, **Android** e **Windows**

## Desenvolvimento

Comandos existentes no projeto:

```bash
./build.sh
```

Compila o aplicativo macOS.

```bash
./make_dmg.sh
```

Gera o instalador DMG.

```bash
./release.sh
./release.sh 1.6.3
./release.sh 1.6.3 --rascunho
```

Publica a release usando a versão atual ou versão explícita, com opção de criar como rascunho.

## Catálogos e dados

Arquivos e listas são usados para abastecer canais e VOD:

- Playlists `.m3u`
- `canais.txt`
- `catalogo.txt`
- `restritos.txt`
- Estrutura em `vod/`

Scripts Python auxiliam atualização, limpeza de links, geração de catálogo e manutenção operacional.

## Avisos importantes

- Fontes externas podem ficar indisponíveis sem aviso.
- Distribuição e uso de conteúdo devem respeitar direitos autorais e direitos de distribuição.
- Não inclua dados privados, tokens, credenciais ou URLs sensíveis em catálogos e scripts.
- Arquivos de catálogo grandes exigem cuidado em alterações para evitar inconsistências.

## Contribuição

Contribuições são bem-vindas via issues e pull requests. Prefira mudanças objetivas, com validação dos scripts e dos dados alterados.

## Licença

Não há licença explícita declarada neste repositório no momento.

## Autor

Projeto Saimo TV e colaboradores.
