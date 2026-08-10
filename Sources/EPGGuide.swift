import SwiftUI

/// Full programme grid: channels down, time across — the layout people know
/// from a cable box, but scrollable, searchable and live.
struct EPGGuideView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject private var epg = EPGService.shared
    @ObservedObject private var posters = LogoLoader.shared
    @Environment(\.dismiss) private var dismiss

    @State private var jumpToNow = 0
    @State private var selected: Programme?
    @State private var selectedChannelName = ""

    private let rowHeight: CGFloat = 64
    private let nameWidth: CGFloat = 200
    private let rulerHeight: CGFloat = 34
    /// Points per minute — a half hour is a comfortable 120pt block.
    private let ppm: CGFloat = 4
    private let span: TimeInterval = 24 * 3600


    private var now: Date { epg.clock }

    private var channels: [Channel] { model.visibleChannels }

    /// The grid starts on the half hour before now, so "now" is always visible
    /// a little way in.
    private var origin: Date {
        let interval = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: (interval - 1800).rounded(.down) - (interval - 1800)
            .truncatingRemainder(dividingBy: 1800))
    }

    private var contentWidth: CGFloat { CGFloat(span / 60) * ppm }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            grid
            if let selected { detail(selected) }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 15, weight: .semibold))
            Text("Programação")
                .font(.headline)

            switch epg.state {
            case .loading:
                ProgressView().controlSize(.small)
                Text("carregando…").font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
            case .ready:
                Text("\(epg.matchedChannels) canais com guia")
                    .font(.caption).foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }

            Spacer()

            Button { jumpToNow += 1 } label: {
                Label("Agora", systemImage: "location.fill")
            }
            .help("Voltar ao horário atual")

            Button { epg.refresh(channels: model.channels) } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Atualizar guia")

            Button { dismiss() } label: { Image(systemName: "xmark") }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Grid

    private var contentHeight: CGFloat {
        rulerHeight + CGFloat(channels.count) * (rowHeight + 1)
    }

    /// The channel column lives outside the horizontal scroll, so it stays put
    /// while the timeline slides; both sit inside one vertical scroll, which
    /// keeps the rows aligned without any offset bookkeeping.
    private var grid: some View {
        // The vertical reader centres the channel being watched when the guide
        // opens: with dozens of rows, landing on the top of the list means
        // hunting for your own channel every time.
        ScrollViewReader { rows in
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(width: nameWidth, height: rulerHeight)
                    ForEach(channels) { channel in
                        channelCell(channel)
                            .frame(width: nameWidth, height: rowHeight)
                            .id(channel.id)
                        Divider().frame(width: nameWidth)
                    }
                }
                .background(.regularMaterial)

                Divider()

                ScrollViewReader { scroller in
                    ScrollView(.horizontal, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ruler.frame(width: contentWidth, height: rulerHeight)
                                ForEach(channels) { channel in
                                    row(for: channel)
                                    Divider().frame(width: contentWidth)
                                }
                            }
                            nowLine(height: contentHeight)
                            // Anchor used by the "Agora" button.
                            Color.clear
                                .frame(width: 1, height: 1)
                                .offset(x: max(0, nowX - 120))
                                .id("now")
                        }
                        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scroller.scrollTo("now", anchor: .leading)
                        }
                    }
                    .onChange(of: jumpToNow) { _, _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scroller.scrollTo("now", anchor: .leading)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard let selection = model.selection else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                rows.scrollTo(selection, anchor: .center)
            }
        }
        }
    }

    private var nowX: CGFloat {
        CGFloat(now.timeIntervalSince(origin) / 60) * ppm
    }

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<Int(span / 1800), id: \.self) { step in
                let time = origin.addingTimeInterval(Double(step) * 1800)
                VStack(alignment: .leading, spacing: 2) {
                    Text(time, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: step % 2 == 0 ? .semibold : .regular))
                        .foregroundStyle(step % 2 == 0 ? .primary : .secondary)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1, height: 8)
                }
                .padding(.leading, 6)
                .frame(width: 30 * ppm, alignment: .leading)
                .offset(x: CGFloat(step) * 30 * ppm)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func channelCell(_ channel: Channel) -> some View {
        HStack(spacing: 10) {
            ChannelIcon(channel: channel, size: 30)
            Text(channel.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selection = channel.id
            dismiss()
        }
        .background(model.selection == channel.id
                    ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func row(for channel: Channel) -> some View {
        let programmes = epg.programmes(for: channel)
        return ZStack(alignment: .topLeading) {
            if programmes.isEmpty {
                Text("sem guia para este canal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12)
                    .frame(height: rowHeight, alignment: .center)
            }
            ForEach(programmes) { programme in
                let x = CGFloat(programme.start.timeIntervalSince(origin) / 60) * ppm
                let full = CGFloat(programme.duration / 60) * ppm - 3
                // A programme already under way when the grid starts is clipped
                // at the left edge, not pushed right — otherwise it would sit
                // on top of the one that follows it.
                let clippedX = max(x, 0)
                let width = max(full - (clippedX - x), 24)
                if x + full > 0 && x < contentWidth {
                    block(programme, channel: channel)
                        .frame(width: width, height: rowHeight - 6)
                        .offset(x: clippedX, y: 3)
                }
            }
        }
        .frame(width: contentWidth, height: rowHeight, alignment: .topLeading)
    }

    private func block(_ programme: Programme, channel: Channel) -> some View {
        let live = programme.start <= now && programme.stop > now
        return VStack(alignment: .leading, spacing: 2) {
            Text(programme.title)
                .font(.system(size: 12, weight: live ? .semibold : .regular))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(programme.start, format: .dateTime.hour().minute())
                if !programme.category.isEmpty {
                    Text("· \(programme.category)").lineLimit(1)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if live {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(height: 3)
                        Capsule().fill(Color.red)
                            .frame(width: geo.size.width * programme.progress(at: now), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(live ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(live ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            selected = programme
            selectedChannelName = channel.name
        }
        .help(programme.desc.isEmpty ? programme.title : programme.desc)
    }

    private func nowLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: height)
            .offset(x: nowX)
            .allowsHitTesting(false)
    }

    // MARK: - Detail

    private func detail(_ programme: Programme) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let poster = programme.poster, let image = posters.image(for: poster) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 186, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(programme.title).font(.headline)
                    if let year = programme.year {
                        Text(year).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selected = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }

                if let subtitle = programme.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(selectedChannelName)
                    Text("·")
                    Text(programme.start, format: .dateTime.weekday().hour().minute())
                    Text("–")
                    Text(programme.stop, format: .dateTime.hour().minute())
                    if !programme.category.isEmpty { Text("·"); Text(programme.category) }
                    if let episode = programme.episodeLabel { Text("·"); Text(episode) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let credits = programme.credits {
                    Text(credits)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                if !programme.desc.isEmpty {
                    ScrollView {
                        Text(programme.desc)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 82)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial)
    }
}

