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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/aie/__index.m3u8?sv=129&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292396-Y5Yoli4LGQ3J7yOTuPXE%2BvnA3yQAMLNAUdYTF3HbDgg%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Adult Swim",
        logo: "https://mondrian.claro.com.br/channels/inverse/adult-swim.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/adultswim/__index.m3u8?sv=10&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786290776-nJUghGmLjJRyjF0SPqaBgidgAOJiU3S97xh4hE2NE1I%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0072-tbx.vrioott.com/adultswimbr/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "7dc3b6abe08d573883365f7d0b09fcb8:7f68828b12e6d739bff28fe2b50e8c94"),
        ]),
    CatalogEntry(
        name: "Animal Planet",
        logo: "https://mondrian.claro.com.br/channels/inverse/animal-planet.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/animalplanet/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291576-cljMHYyJK3iEhKhqrwvs2DVTA0kXJMj71miu9g%2Bmv9w%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/3",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cartoon/__index.m3u8?sv=31&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786492570-yEMfkxGVCe7v1tyVjwD9gZ89%2BL%2FJf6Pm4pUvQ8LqU%2F4%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0013-tbx.vrioott.com/cartoonnetworkbr/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "9e21b82aa1b8593a8af31e78f016287d:726579be89fa97b3a7c5785f94a27c72"),
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
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/335",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://video46.mais.uol.com.br/live/281.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "f7cb42541fbc6043627e4ee025c18300:24843d82b079bbefb73100b887493400"),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history/__index.m3u8?sv=55&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291762-tHU51SX3yOLe0qe6%2BM0vDfNsino79JkgeziJXPObC5E%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "History 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/history-2.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/history2/__index.m3u8?sv=97&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786291713-XbODG62M9FkfenILPzk1Tg1OMEzEmII4kllJIMtsWxI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/44",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/megapix/__index.m3u8?sv=36&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292042-lEvGkdtu6aw2yTM0jTeV5jlkTa8hKgsAEz2Kqrsvsu8%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
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
            Source(url: "https://aovivo.maissbt.com/indexMobile.m3u8",
                   referer: "https://mais.sbt.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
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
            Source(url: "https://video37.mais.uol.com.br/live/279.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "5e8567bf0707bf910f611e5cf2ef352f:8b30ddee60bb9fe6653f1eb8c9b85d5d"),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sony/__index.m3u8?sv=62&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786408417-5jbaSSPBe88ByzCcAo3f6y4WaeKbPbezfqwb3pXoxvA%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Studio Universal",
        logo: "https://mondrian.claro.com.br/channels/inverse/studio-universal.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/studiouniversal/__index.m3u8?sv=153&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786408629-ttZQ50ex7Jw4GXXphI%2BVbOg5APRxPavlxoAW%2BCNOykY%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/74",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://qw.live.pv-cdn.net/OTTB/gru-nitro/live/clients/dash/enc/m7duvnk2bu/out/v1/d1ad69118b5647309b1eb7213affdb3d/cenc.mpd",
                   referer: "https://www.primevideo.com/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "4bbcff3289d457b4dd5dbdd21221de9a:c4906b9a9f8dda3c0725bddb8c497733"),
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
            Source(url: "https://0084-tbx.vrioott.com/telecineaction/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "3ac931934ee95f6e83bc549f89a13fed:844e6313c76c4e7f75058d1c8e593347"),
        ]),
    CatalogEntry(
        name: "Telecine Pipoca",
        logo: "https://mondrian.claro.com.br/channels/inverse/tc-pipoca.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepipoca/__index.m3u8?sv=58&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786492376-lVHrv7GkGdIq6AAU1c65luWS5GerVjL4DwRV0Ajf6x8%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0085-tbx.vrioott.com/telecinepipoca/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "514a45f76193549382c1017ca8a9387a:56bf5c4de8b0fd8f4566a5a55e14fb6b"),
        ]),
    CatalogEntry(
        name: "Telecine Premium",
        logo: "https://mondrian.claro.com.br/channels/inverse/tc-premium.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/telecinepremium/__index.m3u8?sv=79&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786292168-FKlxVeuJhXev%2F1KUUB5nexfVY5bv0OpgfJecX3Kk9q0%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0086-tbx.vrioott.com/telecinepremium/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "0f81d428f69f5b2e8e714cadcadaff83:d2b198091bf14b01effe589ecd0ee2ec"),
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
            Source(url: "https://video45.mais.uol.com.br/live/277.mpd",
                   referer: "https://painel.play.uol.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "ff12e06c66327cd35b99013b38dd4f84:08320e9a44185e55074ac435d8c9a856"),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/warner/__index.m3u8?sv=45&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786408187-kiwlPGYo%2BdoNAPFeEevo8dCwHVXiKq%2B%2BJBr%2FI5tNtFg%3D",
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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/foodnetwork/__index.m3u8?sv=173&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318587-jiNY6eM7XRD%2FkW0wXhwxSh6laUG3oM%2BKParp6FtaoDc%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/foodnetwork/__index.m3u8?sv=178&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786301641-I%2B8e4UfH7a84n9jbFrfVRTAvhHz0XGzIVx0gpToH7zI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0048-tbx.vrioott.com/foodnetworkbr/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "c0c8121d44265abb8bc5298a9adbe90b:33bb4825451547511755224a8cbf06b4"),
        ]),
    CatalogEntry(
        name: "Gloob",
        logo: "https://mondrian.claro.com.br/channels/inverse/gloob.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/gloob/__index.m3u8?sv=35&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786301449-TnMgF08Dd9XnKs8sugyFuOsAjSHmlVN5TN13pVqFhDk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0060-tbx.vrioott.com/gloob/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "0980bcf6ebf15aa4831e3f8a095fff79:14e23e425e82f18d4ff4466da098aa1b"),
        ]),
    CatalogEntry(
        name: "Globo SP",
        logo: "https://mondrian.claro.com.br/channels/inverse/globo.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/bobosp/__index.m3u8?sv=88&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786308190-ZJ9brWallKsnk%2F7UWQ%2FQTAGEXpmP%2FKcVaSUGn9znNbA%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/741",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Cartoonito",
        logo: "https://mondrian.claro.com.br/channels/inverse/cartoonito.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cartoonito/__index.m3u8?sv=114&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786317656-1XIQOrlNN%2BHazl3Wst%2F7IlT24vGk2bzQvu%2BVvw7czSQ%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/122",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Cinemax",
        logo: "https://mondrian.claro.com.br/channels/inverse/cinemax.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/cinemax/__index.m3u8?sv=89&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786317781-Zb0ihZRP%2Fd8xd9LFBPc%2BJkw8LPD7h%2BCIG49P8T5DB3w%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/9",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discovery/__index.m3u8?sv=8&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786317914-q0BTVDVdNa6OnGufXqIB18CL6Av9hu1qbjgZTCifu3s%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/12",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Home & Health",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-home-and-health.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoveryhomeihealth/__index.m3u8?sv=165&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786317976-YfEFqP5bEhiFUgUHTxJ2R6BLc3rxZAasmpQOjE1xx8M%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/14",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Kids",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-kids.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoverykids/__index.m3u8?sv=154&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318026-groDks79ir2Y%2Fkhwi%2FUklj48Q9TgNV6u8nXTUDyFtZA%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/15",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Discovery Theater",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-theater.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoverytheater/__index.m3u8?sv=198&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318156-eEfPQ8%2F6bq3VdNNjLimmnVYV9pJAsGVi%2BvdBpgx1uGk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0074-tbx.vrioott.com/discoverytheaterbr/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "7b00a834eae359df83472b10934ce21e:ea1780c7e02875ff7d025c5ad7f8d096"),
        ]),
    CatalogEntry(
        name: "Discovery World",
        logo: "https://mondrian.claro.com.br/channels/inverse/discovery-world.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/discoveryworld/__index.m3u8?sv=101&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318262-3PA%2BHb4nyzwzInWXdoGJEpIzuzxq4CopzX6sCTcr7uk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0102-tbx.vrioott.com/discoveryworldbr/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "9b182bbd1abc5a108a364bdb3f05ca4a:07b5b9ef7e4807e106b214755729d93a"),
        ]),
    CatalogEntry(
        name: "ESPN",
        logo: "https://mondrian.claro.com.br/channels/inverse/espn.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn/__index.m3u8?sv=12&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318392-QvKT%2FUp7bZQSZYJz6P10ssTqi7CQZwlTquxwquyZKOM%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0007-aws-da-mt.vrioott.com/0007_ESPN_DASH/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "6cd41235037836528a679d1f92e8e4a2:694916b4ae717c948504bafd5c7278ea"),
        ]),
    CatalogEntry(
        name: "ESPN 2",
        logo: "https://mondrian.claro.com.br/channels/inverse/espn-2.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn2/__index.m3u8?sv=141&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318445-zhWacyLIG8lLoYvlDCss2l3Uzb6bPtJB7boGnCgWXvI%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0011-aws-da-mt.vrioott.com/0011_ESPN_2_DASH/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "784c98de262634eca3680a0347fee6a8:4da2f3caee7a66ac25371d84136d2eaf"),
        ]),
    CatalogEntry(
        name: "ESPN 4",
        logo: "https://mondrian.claro.com.br/channels/inverse/espn-4.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/espn4/__index.m3u8?sv=166&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318524-FDNFOsKiw6lTQJ35mV3KKuwHL8%2Bg%2FeKqmq3oedHtH9s%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0040-aws-da-mt.vrioott.com/0040_ESPN_4_DASH/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "9f07d219385a301c9d4eff10151f502c:89870c6ac581c031247caf6dc9e5579d"),
        ]),
    CatalogEntry(
        name: "Gloobinho",
        logo: "https://mondrian.claro.com.br/channels/inverse/gloobinho.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/gloobinho/__index.m3u8?sv=129&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318782-D10ReLfV9K9Pf5Sm4bYoowgfG3kuv5taawFmvkqoD4c%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "https://0061-tbx.vrioott.com/gloobinho/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "ab29ae9d310c5bcd89af885553566756:4a8a50a8cad4761a22015f69d720fbf6"),
        ]),
    CatalogEntry(
        name: "HBO",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbo/__index.m3u8?sv=132&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786492099-MUqmGUjva9IbHeQRUp%2BYUm3aOWZlUj6pQOchl2bOPoc%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/41",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO2",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-2.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbo2/__index.m3u8?sv=130&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318898-K3ZqHfTFH1G%2BGiR8Cm9Rj%2F97Hz%2FArnNn7isruGQHqK0%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/39",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Family",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-family.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbofamily/__index.m3u8?sv=110&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786318990-VHr%2FSKUQMB04QL6bqlaqNJUjBnjWuqn%2BtRMC3XY30uw%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/40",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbomundi/__index.m3u8?sv=123&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319375-0KBZxAs709vCiKdjPn%2Bb%2B5W6MSguL8DqKgf04TSxglw%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Plus",
        logo: "https://mondrian.claro.com.br/channels/inverse/hboplus.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hboplus/__index.m3u8?sv=1&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319431-Pi9MnjfX4JxMUuxnHJgxq52SXIFzdeOKuVtwNVT6KM0%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/42",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Pop",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-pop.png",
        sources: [
            Source(url: "https://getcdn.clarocdn.com.br/Content/Channel/SPOMAXHD/dsc3/manifest.mpd",
                   referer: "https://www.clarotvmais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "1d0c9de86aa3375ab848fc728343f4a2:46cb51c3726930edb0e2b98382273f56"),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbopop/__index.m3u8?sv=157&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319479-lDYSgAj4ZFIepwV0vX8u9S0e7Ebxhf4BTv3EniTCBnY%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Signature",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-signature.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hbosignature/__index.m3u8?sv=160&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319526-INBbshGXlD9TpQbIrO2o%2B%2Bvh2AdOSYyq40%2Bxn2K8TP8%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/43",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HBO Xtreme",
        logo: "https://mondrian.claro.com.br/channels/inverse/hbo-xtreme.png",
        sources: [
            Source(url: "https://getcdn.clarocdn.com.br/Content/Channel/SPOMAPHD/dsc3/manifest.mpd",
                   referer: "https://www.clarotvmais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "88fbeafda45e3cb0a029e2e04152348a:40dd784747107960ed81ab3b5012c5f6"),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hboxtreme/__index.m3u8?sv=54&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319588-UdulgZyZ6RDlqovJ2z2GT922OIYzhtERsRLNIvGENhw%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "HGTV",
        logo: "https://mondrian.claro.com.br/channels/inverse/hgtv.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/hgtv/__index.m3u8?sv=19&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319632-e1qPFbo7TJi2Lby9%2BI9oTn0jZMeT0HApUMoTzAF%2FwJw%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/13",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Record",
        logo: "https://mondrian.claro.com.br/channels/inverse/record-tv.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/record/__index.m3u8?sv=56&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319751-ihJPWustFQ8fO9p1yyF%2BMusOyiKd5%2FAq0JfK%2FT7%2B2AY%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/726",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Space",
        logo: "https://mondrian.claro.com.br/channels/inverse/space.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/space/__index.m3u8?sv=32&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786319822-jZjECmMzIWG6zhTnKGLKJd%2BzLRKz4K5nb1etZg2KBOU%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/70",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "http://aguasdecoco.cdnxjp.space:80/03985093485/903482930834/84",
                   referer: nil,
                   userAgent: "Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
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
            Source(url: "https://0022-tbx.vrioott.com/tntseries/manifest.mpd",
                   referer: "https://www.skymais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "58d90559a4235ef98711a5b0ec652b7e:84942c1d33c0d96dc84623648f1137e9"),
        ]),
    CatalogEntry(
        name: "Universal TV",
        logo: "https://mondrian.claro.com.br/channels/inverse/universal.png",
        sources: [
            Source(url: "https://getcdn.clarocdn.com.br/Content/Channel/SPOUNVHD/dsc3/manifest.mpd",
                   referer: "https://www.clarotvmais.com.br/",
                   userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                   clearKey: "0110de67e8a43229a9afee5fbb1bf34c:14d17ea503859feb50f395a19491a2ea"),
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/universal/__index.m3u8?sv=60&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786320128-FxFFFQxrmw897iWMG7XhBfzLKd1XJ4nk1YU5W1ajEo4%3D",
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
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sexhot/__index.m3u8?sv=108&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786409275-3SbSGeICp%2BQQE1GjPHhT3%2BEEN2faTpnK3nkAYc1ZZ%2Fk%3D",
                   referer: nil,
                   userAgent: nil,
                   clearKey: nil),
        ]),
    CatalogEntry(
        name: "Sex Privé",
        logo: "https://mondrian.claro.com.br/channels/inverse/sexprive.png",
        sources: [
            Source(url: "https://p17-common-sign.dynamic.pages.cloudflareusercontent.com/tos-alisg-avt-0068/proxy?container=images&refresh=10&url=https://neosoro.gq/docs/sexprive/__index.m3u8?sv=155&cc=y&secure_uri=true&nu3zAQc9HC3GbwJq=1786409329-I1OhIzY4uS7zmKoJhWYDv0FInQCzunDEsQkyiw%2F%2Bm%2B4%3D",
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
