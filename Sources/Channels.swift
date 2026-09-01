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
            Source(url: "https://video39.mais.uol.com.br/live/267.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                   clearKey: "74481194bf32774e0cb44a1d71d6cc19:4bfd25bc9419f1c71e3ee8e6bf5ccf2a"),
        ]),
    CatalogEntry(
        name: "Adult Swim",
        logo: "https://mondrian.claro.com.br/channels/inverse/adult-swim.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/TRUTV_HD/720p_000093558.ts?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "AMC",
        logo: "https://mondrian.claro.com.br/channels/inverse/amc.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/amc/__index.m3u8?sv=135&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787791802-19E0T04G7LhoYwlfFJelb6WdUgMP6m04036lcJ1Yxcc%3D",
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
                   clearKey: "3b43a1fbcf57cfe04109fbc1b381ac79:a23de064124dfddeaf3c23490d96328b"),
        ]),
    CatalogEntry(
        name: "Cartoon Network",
        logo: "https://mondrian.claro.com.br/channels/inverse/cartoon-network.png",
        sources: [
            Source(url: "https://_______________________________________________________________.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cartoon/__index.m3u8?sv=84&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787689309-%2FssbacY0lf%2FaEdVkBHNWxAAcCUGhU2J8y9NgGnE440g%3D",
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
                   userAgent: "Mozilla/5.0 (Linux; U; Android 13; T610K Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.71 Mobile Safari/537.36 OPR/87.0.2254.75258",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "CNN Brasil",
        logo: "https://mondrian.claro.com.br/channels/inverse/cnn-brasil.png",
        sources: [
            Source(url: "https://amg01391-sbtinfast-amg01391c4-lg-br-4597.playouts.now.amagi.tv/playlist/amg01391-addigital-cnnbrasil-lgbr/playlist.m3u8",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; U; Android 13; T610K Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.71 Mobile Safari/537.36 OPR/87.0.2254.75258",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "CNN Brasil Money",
        logo: "https://mondrian.claro.com.br/channels/inverse/cnn-brasil-money.png",
        sources: [
            Source(url: "https://amg01391-amg01391c57-amgplt0026.playout.now3.amagi.tv/playlist/amg01391-amg01391c57-amgplt0026/playlist.m3u8",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; U; Android 13; T610K Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.71 Mobile Safari/537.36 OPR/87.0.2254.75258",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "E!",
        logo: "https://mondrian.claro.com.br/channels/inverse/e!.png",
        sources: [
            Source(url: "https://video49.mais.uol.com.br/live/4503.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "d021c9ff8ab94c1a583a0f5f2cc82725:7de3fcc29e3194b9c65282a42cb7bec6"),
        ]),
    CatalogEntry(
        name: "GE TV",
        logo: "https://mondrian.claro.com.br/channels/inverse/ge-tv.png",
        sources: [
            Source(url: "https://dfr80qz435crc.cloudfront.net/EFGH/Amagi/Globo/GE_Fast_BR/GE_Fast.m3u8",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; U; Android 13; T610K Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.71 Mobile Safari/537.36 OPR/87.0.2254.75258",
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
                   clearKey: "57ecd6a2086b99cc1d0452b102a7043b:11386090a315fc1e88427aeed4a60900"),
        ]),
    CatalogEntry(
        name: "Globoplay Novelas",
        logo: "https://mondrian.claro.com.br/channels/inverse/viva.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/ds9ertnhrl/out/v1/cb791b7362754ba1b87d9474ccd95fa3/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "eab4523b0358f3c59f1da92b3f478232:253ef14355d987d4076b4544e4741977"),
        ]),
    CatalogEntry(
        name: "GNT",
        logo: "https://mondrian.claro.com.br/channels/inverse/gnt.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/h9c8z9m1dq/out/v1/9b1b1aa15b4f471ea19674290554499e/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "4c4d19c8cda9e78bae924e07ce49cb04:4a3a155e480a67b81c5492befe07fa61"),
        ]),
    CatalogEntry(
        name: "History",
        logo: "https://mondrian.claro.com.br/channels/inverse/history-channel.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history/__index.m3u8?sv=135&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793059-f3m9JkdrjrQJxep1Ii5aqo1mnsxh3C9Hhd24xvNSqxs%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://video46.mais.uol.com.br/live/281.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "f7cb42541fbc6043627e4ee025c18300:24843d82b079bbefb73100b887493400"),
        ]),
    CatalogEntry(
        name: "History 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/history-2.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history2/__index.m3u8?sv=41&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793125-3Gtiog3L2lWYU21WxnFk1mORI7RK%2Bgrmq9nU0M4H%2F0w%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history2-sd/__index.m3u8?sv=41&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793125-qJ1cp%2FaZU0TB2TS53Hy%2F6OU3u1nHdGgLjGMnC94BSJA%3D",
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
                   userAgent: "Mozilla/5.0 (Linux; U; Android 13; T610K Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.71 Mobile Safari/537.36 OPR/87.0.2254.75258",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Megapix",
        logo: "https://mondrian.claro.com.br/channels/inverse/megapix.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/21ilsertww/out/v1/124c84cbafc745b6b2c47fc9be606727/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "cf8a2c054a3148309bce1039a9a5d603:9417daf3a25dff3f78d76c1ebb550654"),
        ]),
    CatalogEntry(
        name: "Multishow",
        logo: "https://mondrian.claro.com.br/channels/inverse/multishow.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/x7aaupxajb/out/v1/49d602c6294147a18d798ce6abbb6957/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "5a93ff790eca6f86ad6adb53929fe1c4:6664fa23d82cbfeaf5cdb2d662bec3b3"),
        ]),
    CatalogEntry(
        name: "Premiere 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-2.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/oy6rp0jwmf/out/v1/580ecf12bad24979baf8dd993dce053e/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "9dc40460c93087aea84d6315f08ecb64:f69c8d4624fddff4ca89bd0b31bdc4a7"),
        ]),
    CatalogEntry(
        name: "Premiere 3",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-3.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/6onrfniyry/out/v1/f23069c61dbf4e00890a40b705a84079/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "d23f7433798a652a7d4f6791d9e1036c:4942eebd598b5727c5cc484cc62b52e8"),
        ]),
    CatalogEntry(
        name: "Premiere 4",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-4.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/tirjor64kh/out/v1/fd2ed9916d994f09a3bd62b64141b9cb/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "e23365c2ad97870c871712b73f0d6195:58709c714320bb862dbd07270df81c94"),
        ]),
    CatalogEntry(
        name: "Premiere 5",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-5.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/1obktrybht/out/v1/08265453c8f64d9fbeb3cf43764403a8/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "332f62eb3cae824e98a4124da29a7d31:d1698cda3d040f9051125a61745b596b"),
        ]),
    CatalogEntry(
        name: "Premiere 6",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-6.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/0bmtb2fxcj/out/v1/b5f50c3632264d32bf857652f631b0fb/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "8bf16a4ba05bcc97e6259297e50be63d:8dd97d486cbdd15cc47ea8c41b264ebb"),
        ]),
    CatalogEntry(
        name: "Premiere 7",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-7.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/joij38hkop/out/v1/c920c9b42af24588a253530ed2cbd6eb/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "238f5cf32228c1877f8b939f5f9d7bd8:47571c93e4335b3d1590a5ae3f5c48ef"),
        ]),
    CatalogEntry(
        name: "Premiere 8",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere-8.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/2s8gkqz2id/out/v1/41da2546a9a34238b8615d3beb4ee600/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "19aec31e45751958c1d963435d725f33:fb24357e80520fd600dd43c1d8ce8a7a"),
        ]),
    CatalogEntry(
        name: "Premiere Clubes",
        logo: "https://mondrian.claro.com.br/channels/inverse/premiere.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/nelfyucw9a/out/v1/6ffb2c365ad14f88b154591beb43d1f6/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "56b79c1782b30e6b6fc973b0e8fd4104:fa38aaa865a57eda7c77444697ba8ed3"),
        ]),
    CatalogEntry(
        name: "SBT",
        logo: "https://mondrian.claro.com.br/channels/inverse/sbt.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/SBT_HD/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "SBT News",
        logo: "https://mondrian.claro.com.br/channels/inverse/sbt-news.png",
        sources: [
            Source(url: "https://sbtnews.maissbt.com/index.m3u8",
                   referer: "https://mais.sbt.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Sony Channel",
        logo: "https://mondrian.claro.com.br/channels/inverse/sony.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sony/__index.m3u8?sv=207&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787840421-CoMPQTpI1T81KNG3ezpJhbubzfOqOodNk9aR1CEItWw%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://video37.mais.uol.com.br/live/279.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "5e8567bf0707bf910f611e5cf2ef352f:8b30ddee60bb9fe6653f1eb8c9b85d5d"),
        ]),
    CatalogEntry(
        name: "Studio Universal",
        logo: "https://mondrian.claro.com.br/channels/inverse/studio-universal.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/studiouniversal/__index.m3u8?sv=9&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793443-Zlu3fC86O%2B%2FxXEhoyYY0lO7n%2FD6Ey7xed6N8%2FtOvBNE%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "SporTV",
        logo: "https://mondrian.claro.com.br/channels/inverse/sportv.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sportv1/__index.m3u8?sv=159&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786408554-MK0K7%2F0RIabb2i7ktFkDI1P2aEeyuwRUwvOxauQ5e1c%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "SporTV 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/sportv-2.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/dsa3hwuhd1/out/v1/631b48c8d9ea437e8309d1a4b55acef5/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "3de028eafb3b2caffec03be1c1c818b3:8fbdd8a9ae6748696bb13e547bb093fc"),
        ]),
    CatalogEntry(
        name: "SporTV 3",
        logo: "https://mondrian.claro.com.br/channels/inverse/sportv-3.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/6otiglnptp/out/v1/add7499679b0422cb6791f7701f95ecc/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "902e5ec0e3d05e665daa32fc23f4f59e:7b2322a273843921a43e2c61dac7cae3"),
        ]),
    CatalogEntry(
        name: "Telecine Action",
        logo: "https://mondrian.claro.com.br/channels/inverse/tc-action.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecineaction/__index.m3u8?sv=191&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786409777-6357MK63%2ByysgfFiZNfFK3mJeGmSWEVxX3ET2vato6g%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Telecine Pipoca",
        logo: "https://mondrian.claro.com.br/channels/inverse/tc-pipoca.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepipoca/__index.m3u8?sv=58&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786492376-lVHrv7GkGdIq6AAU1c65luWS5GerVjL4DwRV0Ajf6x8%3D",
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
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Universal Premiere",
        logo: "https://mondrian.claro.com.br/channels/inverse/universal-premiere.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/khnyllds8v/out/v1/1cf61b7a057e4ffdb31f6d82fb24c679/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "3531c1c49b8e63c0b94a8061154e0c58:90e91e6549d2061b793177c70d35e177"),
        ]),
    CatalogEntry(
        name: "Universal Reality",
        logo: "https://mondrian.claro.com.br/channels/inverse/universal-reality.png",
        sources: [
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/5ppjwg1ekb/out/v1/393342b545834c218745c3dd33661013/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "4b62d6103d99d62f8daca463d1c15430:2fd0079af0bf85289859fff7b8a4e30f"),
        ]),
    CatalogEntry(
        name: "Warner",
        logo: "https://mondrian.claro.com.br/channels/inverse/warner-channel.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/WARNER_HD/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
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
            Source(url: "https://p12-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/foodnetwork/__index.m3u8?sv=154&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787510790-oLglpNJTCmF4dMfrjs1DtdFDeq5mTV9g6bSMLrUWnT0%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Gloob",
        logo: "https://mondrian.claro.com.br/channels/inverse/gloob.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/gloob/__index.m3u8?sv=91&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793787-9h%2Bs%2B%2FRV9nGKt4Fclr9SyE2NXEr1j09Qx7tlNvn6FB0%3D",
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
    CatalogEntry(
        name: "Cartoonito",
        logo: "https://mondrian.claro.com.br/channels/inverse/cartoonito.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cartoonito/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792050-bykfcjcri4xlMawMEAbEK0ib1ZngaZ96MUudlmODfgk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Cinemax",
        logo: "https://mondrian.claro.com.br/channels/inverse/cinemax.png",
        sources: [
            Source(url: "https://p12-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cinemax/__index.m3u8?sv=66&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787510316-X70RycSXFaJIDV%2BwMOJkE%2Bdz%2FmNYSqg%2B2TU9KVeKl4Y%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Combate",
        logo: "https://mondrian.claro.com.br/channels/inverse/combate.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/combate/__index.m3u8?sv=180&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786317841-kasstfdIhiqSElnrlbwkM4AVYt3R8NSVQYvsaAz2vmc%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Channel",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discovery/__index.m3u8?sv=139&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792290-fJWwTtvayu87khQ1dLjP6IO6DYBxOFtm53vvQJV4G3U%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Home & Health",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-home-and-health.png",
        sources: [
            Source(url: "https://p12-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoveryhomeihealth/__index.m3u8?sv=29&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787510491-LXPCJR%2BIA5IcHXUlV%2FZ9bcvbmd%2FTzc2XQwKhkl1c7wc%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Kids",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-kids.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoverykids/__index.m3u8?sv=20&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792246-o4vHOJkg%2BDj4Caq%2FNBQ3IdIgxJpQ0cavj5QIWJuedCI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Theater",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-theater.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoverytheater/__index.m3u8?sv=135&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792363-9cDXDK11ov3pxrqmTh5xvDzwIlVxwFtcCbc%2BUklF%2BTM%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery World",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-world.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoveryworld/__index.m3u8?sv=136&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792469-Nwvl6a9j4BZymbR6g6UCqBuxq4SfH0dfrSki5m%2B%2BL%2Bg%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "ESPN",
        logo: "https://mondrian.claro.com.br/channels/inverse/espn.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318392-QvKT%2FUp7bZQSZYJz6P10ssTqi7CQZwlTquxwquyZKOM%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "ESPN 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/espn-2.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn2/__index.m3u8?sv=141&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318445-zhWacyLIG8lLoYvlDCss2l3Uzb6bPtJB7boGnCgWXvI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "ESPN 4",
        logo: "https://mondrian.claro.com.br/channels/inverse/espn-4.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn4/__index.m3u8?sv=166&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318524-FDNFOsKiw6lTQJ35mV3KKuwHL8%2Bg%2FeKqmq3oedHtH9s%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Gloobinho",
        logo: "https://mondrian.claro.com.br/channels/inverse/gloobinho.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/gloobinho/__index.m3u8?sv=79&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793838-tRD7tqVyKyrzRDnGYUPHk2%2Bj7uP%2B8BgM3QTmfsFiAd0%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/HBO/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO2",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-2.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/HBO2/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Family",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-family.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/HBO_FAMILY/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Mundi",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-mundi.png",
        sources: [
            Source(url: "https://getcdn.clarocdn.com.br/Content/Channel/SPOCMTHD/dsc1/manifest.mpd",
                   referer: "https://www.clarotvmais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "864d0001e28938b0be3e1c6d8dc110ea:87f36ec6e6747a587d1e6393f61c003a"),
        ]),
    CatalogEntry(
        name: "HBO Plus",
        logo: "https://mondrian.claro.com.br/channels/inverse/hboplus.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/HBO_PLUS/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Pop",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-pop.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbopop/__index.m3u8?sv=184&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792797-vFVR9HJei0AJ1XncxfiSBXWqecgVajCY7kDtx8DlYKE%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Signature",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-signature.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/HBO_SIGNATURE/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Xtreme",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-xtreme.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/HBO_EXTREME_HD/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HGTV",
        logo: "https://mondrian.claro.com.br/channels/inverse/hgtv.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hgtv/__index.m3u8?sv=110&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792996-HY%2FoZh3zHW%2BSz49EWOXZcgCnmpBuHFUXxm39Te5AY%2FU%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Record",
        logo: "https://mondrian.claro.com.br/channels/inverse/record-tv.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/record/__index.m3u8?sv=198&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793316-1%2F7AHwT%2BrGJghZvWrDk%2F0w53u6n8C02UvEtZOjNOawI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Space",
        logo: "https://mondrian.claro.com.br/channels/inverse/space.png",
        sources: [
            Source(url: "https://_______________________________________________________________.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/space/__index.m3u8?sv=99&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787689135-lMYR0Q44VqZ1jjexU8svYO9V4nwIWjpMyvQGLchfKlk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "TNT",
        logo: "https://mondrian.claro.com.br/channels/inverse/tnt.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/tnt/__index.m3u8?sv=86&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786320015-pLkZ%2FNdlgXV4jqtDYTJ51nEkLG8WRJkACfkgm5UMYF8%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "TNT Séries",
        logo: "https://mondrian.claro.com.br/channels/inverse/tnt-series.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/tntseries/__index.m3u8?sv=5&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786320066-hcnuxiV0uoL54pSnZai999RtJv4kuUlXop3OpOigZek%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Universal TV",
        logo: "https://mondrian.claro.com.br/channels/inverse/universal.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/universal/__index.m3u8?sv=145&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793650-GnrhkyMAFFyYcMrbYnyoK5iNJOpaR%2FxBaNSV1xhO1SY%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://getcdn.clarocdn.com.br/Content/Channel/SPOUNVHD/dsc3/manifest.mpd",
                   referer: "https://www.clarotvmais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "0110de67e8a43229a9afee5fbb1bf34c:14d17ea503859feb50f395a19491a2ea"),
        ]),
    CatalogEntry(
        name: "AMC Séries",
        logo: "https://mondrian.claro.com.br/channels/inverse/amc.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/amcseries/__index.m3u8?sv=47&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787791897-8Wm%2BGGutqxTv63fxI3XWxW194BK1noTzs%2FLdK3eauCs%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Turbo",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-turbo.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoveryturbo/__index.m3u8?sv=187&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787792423-HLnTQInVZdS8M8NMkNE9XAXOEhN26tz%2FkdWQ5xEMI7U%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "USA Network",
        logo: "https://mondrian.claro.com.br/channels/inverse/usa.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/usa/__index.m3u8?sv=162&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793737-hfQnyiPMhLyTb5vIRG%2BkDol7dTIZYzvZvAZewbE3vlc%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Bloomberg",
        logo: "https://mondrian.claro.com.br/channels/inverse/bloomberg.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/bloomberg/__index.m3u8?sv=140&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793922-WeDZahYYiI%2Bdr73LHvPediWhQmdj6dctBNCDi6f45Yk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "canal-brasil",
        logo: "https://api.reidoscanais.ooo/img/canalbrasil.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/canalbrasil/__index.m3u8?sv=155&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787791989-l5AGuGfDmmdtOq0t8pJFxsQmhh7Upxvn%2FDstVgjia5k%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "canal-off",
        logo: "https://api.reidoscanais.ooo/img/canaloff.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/off/__index.m3u8?sv=143&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793259-sSVLAlB%2FyEIDR1SYL1gWsDeonZz8E6h7esY7TXSA%2F94%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Telecine Fun",
        logo: "https://embedcanaisdetv.com/images/tcfun.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinefun/__index.m3u8?sv=164&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793521-AgfMEtyIf7thou7yDHByqO2ulZwFKnnFeMdLGfnXEMo%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Telecine Cult",
        logo: "https://embedcanaisdetv.com/images/tccult.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinecult/__index.m3u8?sv=97&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793482-yEwhUO%2BYTFWaVoO3aH%2FerazomyKF74oEBwlw%2BBW2CT8%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Telecine Touch",
        logo: "https://embedcanaisdetv.com/images/tctouch.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinetouch/__index.m3u8?sv=104&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793560-W9IjDsYoBCDmrZ35n%2FSbaXlsYhE84n%2Fd90%2B36hjStSI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "SONY Movies",
        logo: "https://api.reidoscanais.ooo/img/sonymovies.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sonymovies/__index.m3u8?sv=192&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787793366-cTNy2GtWbETsxXemEnMTs1INUxwZjhES5tp6LWV%2FkVU%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),

    CatalogEntry(
        name: "Globo",
        logo: "https://mondrian.claro.com.br/channels/inverse/globo.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/GLOBO_HD/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Tooncast",
        logo: "https://mondrian.claro.com.br/channels/inverse/tooncast.png",
        sources: [
            Source(url: "https://cdn-sp2.satlabscloud.com.br/TOONCAST/index.m3u8?token=ulDZjn1kAAan1kzoXmUL1B84gijOI6v7",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
]

/// Line-up that only exists once the viewer types the code.
///
/// It is kept apart from `catalog` rather than flagged inside it so nothing in
/// the interface has to know it exists: while locked, these channels are not in
/// the list at all, so there is no label, no gap and no count to notice.
private let restrictedCatalog: [CatalogEntry] = [
    CatalogEntry(
        name: "Sexy Hot",
        logo: "https://mondrian.claro.com.br/channels/inverse/sexy-hot.png",
        sources: [
            Source(url: "https://_______________________________________________________________.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sexhot/__index.m3u8?sv=6&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787689564-aM005g6E%2FYMgnoZgUnYEF28ouVUon%2FXBOI7lMLZShac%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Sex Privé",
        logo: "https://mondrian.claro.com.br/channels/inverse/sexprive.png",
        sources: [
            Source(url: "https://_______________________________________________________________.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sexprive/__index.m3u8?sv=54&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787689614-T5qTalNl2RblYNCOvkva1kwAqG1ahOhUp0YxwPPKWWE%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Playboy TV",
        logo: "https://mondrian.claro.com.br/channels/inverse/playboy-tv.png",
        sources: [
            Source(url: "https://xn--l---------------------------_________________________-2w85c.null-null.shop/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/playboytv/__index.m3u8?sv=48&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1787840278-pcqPCfDH7M3QsYXk1k6laCLQIhqLIrTK4YxaTqKUJVc%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
]

private func build(_ entries: [CatalogEntry]) -> [Channel] {
    entries.compactMap { entry in
        let variants = entry.sources.compactMap { s -> Variant? in
            guard let url = URL(string: s.url) else { return nil }
            // A chave é guardada como KID:CHAVE, porque o lado Android precisa
            // dos dois. O AVFoundation só usa a chave, que é a segunda metade.
            let key = s.clearKey.map { $0.split(separator: ":").map(String.init).last ?? $0 }
            return Variant(url: url, referer: s.referer,
                           userAgent: s.userAgent, clearKey: key)
        }
        guard !variants.isEmpty else { return nil }
        return Channel(name: entry.name,
                       variants: variants,
                       logo: entry.logo.flatMap(URL.init(string:)))
    }
}

let defaultChannels: [Channel] = build(catalog)
let restrictedChannels: [Channel] = build(restrictedCatalog)
