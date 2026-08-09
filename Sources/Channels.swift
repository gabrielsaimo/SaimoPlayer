import Foundation

/// Static channel line-up.
///
/// Each channel lists its sources in preference order: the curated HLS link
/// first, the one harvested from the shared list as a fallback. The proxy walks
/// the list and sticks to the first source that answers.
///
/// DASH sources and HLS carrying HEVC-in-TS are repackaged by the ffmpeg
/// gateway before AVFoundation sees them; DASH also carries its CENC ClearKey.
struct Source {
    let url: String
    let referer: String?
    let userAgent: String?
    let clearKey: String?
}

struct CatalogEntry {
    let name: String
    let logo: String?
    let sources: [Source]
}

private let catalog: [CatalogEntry] = [
    CatalogEntry(
        name: "A&E",
        logo: "https://mondrian.claro.com.br/channels/inverse/aee.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/aie/__index.m3u8?sv=129&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292396-Y5Yoli4LGQ3J7yOTuPXE%2BvnA3yQAMLNAUdYTF3HbDgg%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://video39.mais.uol.com.br/live/267.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                   clearKey: "4bfd25bc9419f1c71e3ee8e6bf5ccf2a"),
        ]),
    CatalogEntry(
        name: "Adult Swim",
        logo: "https://mondrian.claro.com.br/channels/inverse/adult-swim.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/adultswim/__index.m3u8?sv=10&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786290776-nJUghGmLjJRyjF0SPqaBgidgAOJiU3S97xh4hE2NE1I%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Animal Planet",
        logo: "https://mondrian.claro.com.br/channels/inverse/animal-planet.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/animalplanet/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291576-cljMHYyJK3iEhKhqrwvs2DVTA0kXJMj71miu9g%2Bmv9w%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Band",
        logo: "https://mondrian.claro.com.br/channels/inverse/band.png",
        sources: [
            Source(url: "https://video41.mais.uol.com.br/live/3361.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "a23de064124dfddeaf3c23490d96328b"),
        ]),
    CatalogEntry(
        name: "Cartoon Network",
        logo: "https://mondrian.claro.com.br/channels/inverse/cartoon-network.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cartoon/__index.m3u8?sv=107&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292306-acrlA6bT%2BIZ0DSCkZMH8EFCM%2BDEXQhTrgS8Q%2Fi7bwV4%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "CazéTV",
        logo: "https://m.media-amazon.com/images/G/01/LCXO_Station_Logos/s151990_lw_h8_aa._SL170_FMpng_.png",
        sources: [
            Source(url: "https://dfr80qz435crc.cloudfront.net/MNOP/Amagi/Caze/Caze_TV_BR/Caze_TV.m3u8",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "CNN Brasil",
        logo: "https://mondrian.claro.com.br/channels/inverse/cnn-brasil.png",
        sources: [
            Source(url: "https://amg01391-sbtinfast-amg01391c4-lg-br-4597.playouts.now.amagi.tv/playlist/amg01391-addigital-cnnbrasil-lgbr/playlist.m3u8",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "CNN Brasil Money",
        logo: "https://mondrian.claro.com.br/channels/inverse/cnn-brasil-money.png",
        sources: [
            Source(url: "https://amg01391-amg01391c57-amgplt0026.playout.now3.amagi.tv/playlist/amg01391-amg01391c57-amgplt0026/playlist.m3u8",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "E!",
        logo: "https://mondrian.claro.com.br/channels/inverse/e!.png",
        sources: [
            Source(url: "https://video49.mais.uol.com.br/live/4503.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "7de3fcc29e3194b9c65282a42cb7bec6"),
        ]),
    CatalogEntry(
        name: "GE TV",
        logo: "https://mondrian.claro.com.br/channels/inverse/ge-tv.png",
        sources: [
            Source(url: "https://dfr80qz435crc.cloudfront.net/EFGH/Amagi/Globo/GE_Fast_BR/GE_Fast.m3u8",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Globo RJ",
        logo: "https://mondrian.claro.com.br/channels/inverse/globo.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/boborj/__index.m3u8?sv=44&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291899-hGV11bG1ulIMifsBzTvVaZKkCLm227WfthQBbXp8w5g%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "GloboNews",
        logo: "https://mondrian.claro.com.br/channels/inverse/globonews.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/dsfrp5mjrb/out/v1/9fa07e663bc94e9f93c53726a558478a/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "11386090a315fc1e88427aeed4a60900"),
        ]),
    CatalogEntry(
        name: "Globoplay Novelas",
        logo: "https://mondrian.claro.com.br/channels/inverse/viva.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/ds9ertnhrl/out/v1/cb791b7362754ba1b87d9474ccd95fa3/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "253ef14355d987d4076b4544e4741977"),
        ]),
    CatalogEntry(
        name: "GNT",
        logo: "https://mondrian.claro.com.br/channels/inverse/gnt.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/h9c8z9m1dq/out/v1/9b1b1aa15b4f471ea19674290554499e/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "4a3a155e480a67b81c5492befe07fa61"),
        ]),
    CatalogEntry(
        name: "History",
        logo: "https://mondrian.claro.com.br/channels/inverse/history-channel.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history/__index.m3u8?sv=55&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291762-tHU51SX3yOLe0qe6%2BM0vDfNsino79JkgeziJXPObC5E%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://video46.mais.uol.com.br/live/281.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "24843d82b079bbefb73100b887493400"),
        ]),
    CatalogEntry(
        name: "History 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/history-2.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history2/__index.m3u8?sv=97&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291713-XbODG62M9FkfenILPzk1Tg1OMEzEmII4kllJIMtsWxI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Jovem Pan News",
        logo: "https://mondrian.claro.com.br/channels/inverse/jp-news-vertical.png",
        sources: [
            Source(url: "https://amg01391-sbtinfast-amg01391c3-lg-us-8995.playouts.now.amagi.tv/playlist/amg01391-addigital-jovempan-lgus/playlist.m3u8",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Megapix",
        logo: "https://mondrian.claro.com.br/channels/inverse/megapix.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/megapix/__index.m3u8?sv=36&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292042-lEvGkdtu6aw2yTM0jTeV5jlkTa8hKgsAEz2Kqrsvsu8%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/21ilsertww/out/v1/124c84cbafc745b6b2c47fc9be606727/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "9417daf3a25dff3f78d76c1ebb550654"),
        ]),
    CatalogEntry(
        name: "Multishow",
        logo: "https://mondrian.claro.com.br/channels/inverse/multishow.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/x7aaupxajb/out/v1/49d602c6294147a18d798ce6abbb6957/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "6664fa23d82cbfeaf5cdb2d662bec3b3"),
        ]),
    CatalogEntry(
        name: "Premiere 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-2.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/oy6rp0jwmf/out/v1/580ecf12bad24979baf8dd993dce053e/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "f69c8d4624fddff4ca89bd0b31bdc4a7"),
        ]),
    CatalogEntry(
        name: "Premiere 3",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-3.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/6onrfniyry/out/v1/f23069c61dbf4e00890a40b705a84079/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "4942eebd598b5727c5cc484cc62b52e8"),
        ]),
    CatalogEntry(
        name: "Premiere 4",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-4.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/tirjor64kh/out/v1/fd2ed9916d994f09a3bd62b64141b9cb/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "58709c714320bb862dbd07270df81c94"),
        ]),
    CatalogEntry(
        name: "Premiere 5",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-5.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/1obktrybht/out/v1/08265453c8f64d9fbeb3cf43764403a8/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "d1698cda3d040f9051125a61745b596b"),
        ]),
    CatalogEntry(
        name: "Premiere 6",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-6.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/0bmtb2fxcj/out/v1/b5f50c3632264d32bf857652f631b0fb/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "8dd97d486cbdd15cc47ea8c41b264ebb"),
        ]),
    CatalogEntry(
        name: "Premiere 7",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-7.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/joij38hkop/out/v1/c920c9b42af24588a253530ed2cbd6eb/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "47571c93e4335b3d1590a5ae3f5c48ef"),
        ]),
    CatalogEntry(
        name: "Premiere 8",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-8.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/2s8gkqz2id/out/v1/41da2546a9a34238b8615d3beb4ee600/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "fb24357e80520fd600dd43c1d8ce8a7a"),
        ]),
    CatalogEntry(
        name: "Premiere Clubes",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/nelfyucw9a/out/v1/6ffb2c365ad14f88b154591beb43d1f6/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "fa38aaa865a57eda7c77444697ba8ed3"),
        ]),
    CatalogEntry(
        name: "SBT",
        logo: "https://mondrian.claro.com.br/channels/inverse/sbt.png",
        sources: [
            Source(url: "https://aovivo.maissbt.com/indexMobile.m3u8",
                   referer: "https://mais.sbt.com.br/",
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "SBT News",
        logo: "https://mondrian.claro.com.br/channels/inverse/sbt-news.png",
        sources: [
            Source(url: "https://sbtnews.maissbt.com/index.m3u8",
                   referer: "https://mais.sbt.com.br/",
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Sony Channel",
        logo: "https://mondrian.claro.com.br/channels/inverse/sony.png",
        sources: [
            Source(url: "https://video37.mais.uol.com.br/live/279.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "8b30ddee60bb9fe6653f1eb8c9b85d5d"),
        ]),
    CatalogEntry(
        name: "SporTV 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/sportv-2.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/dsa3hwuhd1/out/v1/631b48c8d9ea437e8309d1a4b55acef5/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "8fbdd8a9ae6748696bb13e547bb093fc"),
        ]),
    CatalogEntry(
        name: "SporTV 3",
        logo: "https://mondrian.claro.com.br/channels/inverse/sportv-3.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/6otiglnptp/out/v1/add7499679b0422cb6791f7701f95ecc/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "7b2322a273843921a43e2c61dac7cae3"),
        ]),
    CatalogEntry(
        name: "Telecine Pipoca",
        logo: "https://mondrian.claro.com.br/channels/inverse/tc-pipoca.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepipoca/__index.m3u8?sv=19&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292214-lP96rLC%2BFMjwZq7332XNsUk1sMRP0nFGZe8RHZcF0fU%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Telecine Premium",
        logo: "https://mondrian.claro.com.br/channels/inverse/tc-premium.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepremium/__index.m3u8?sv=79&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292168-FKlxVeuJhXev%2F1KUUB5nexfVY5bv0OpgfJecX3Kk9q0%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "TV Brasil",
        logo: "https://mondrian.claro.com.br/channels/inverse/tv-brasil.png",
        sources: [
            Source(url: "https://tvbrasil-stream.ebc.com.br/index.m3u8",
                   referer: "https://aovivo.ebc.com.br/",
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Universal Premiere",
        logo: "https://mondrian.claro.com.br/channels/inverse/universal-premiere.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/khnyllds8v/out/v1/1cf61b7a057e4ffdb31f6d82fb24c679/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "90e91e6549d2061b793177c70d35e177"),
        ]),
    CatalogEntry(
        name: "Universal Reality",
        logo: "https://mondrian.claro.com.br/channels/inverse/universal-reality.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/5ppjwg1ekb/out/v1/393342b545834c218745c3dd33661013/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "2fd0079af0bf85289859fff7b8a4e30f"),
        ]),
    CatalogEntry(
        name: "Warner",
        logo: "https://mondrian.claro.com.br/channels/inverse/warner-channel.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/warner/__index.m3u8?sv=13&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786223551-oAHvAX%2FWguAlXkW9qd1ApBbvOIgbl7JhLTGmTSvqLWk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "IMPD",
        logo: nil,
        sources: [
            Source(url: "https://68882bdaf156a.streamlock.net/impd/ngrp:impd_all/chunklist_w1464410885_b2691072.m3u8",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Food Network",
        logo: "https://mondrian.claro.com.br/channels/inverse/food-network.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/foodnetwork/__index.m3u8?sv=178&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786301641-I%2B8e4UfH7a84n9jbFrfVRTAvhHz0XGzIVx0gpToH7zI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Gloob",
        logo: "https://mondrian.claro.com.br/channels/inverse/gloob.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/gloob/__index.m3u8?sv=35&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786301449-TnMgF08Dd9XnKs8sugyFuOsAjSHmlVN5TN13pVqFhDk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Globo SP",
        logo: "https://mondrian.claro.com.br/channels/inverse/globo.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/bobosp/__index.m3u8?sv=88&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786308190-ZJ9brWallKsnk%2F7UWQ%2FQTAGEXpmP%2FKcVaSUGn9znNbA%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
]

let defaultChannels: [Channel] = catalog.compactMap { entry in
    let variants = entry.sources.compactMap { s -> Variant? in
        guard let url = URL(string: s.url) else { return nil }
        return Variant(url: url, referer: s.referer,
                       userAgent: s.userAgent, clearKey: s.clearKey)
    }
    guard !variants.isEmpty else { return nil }
    return Channel(name: entry.name,
                   variants: variants,
                   logo: entry.logo.flatMap(URL.init(string:)))
}
