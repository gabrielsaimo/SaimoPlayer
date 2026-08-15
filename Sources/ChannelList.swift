import SwiftUI
import AppKit

/// The channel list, shared by the split-view sidebar and the detached window
/// so both stay identical.
struct ChannelListView: View {
    @ObservedObject var model: PlayerModel
    /// The detached window has no toolbar to hang the "+" menu on.
    var showsAddMenu: Bool = true

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.visibleChannels) { channel in
                ChannelRow(channel: channel,
                           isFavorite: model.isFavorite(channel),
                           toggleFavorite: { model.toggleFavorite(channel) })
                    .tag(channel.id)
                    .contextMenu {
                        if channel.variants.count > 1 {
                            Menu("Escolher Fonte") {
                                ForEach(Array(channel.variants.enumerated()), id: \.offset) { index, variant in
                                    Button(variant.label ?? "Fonte \(index + 1)") {
                                        model.playVariant(channel, index: index)
                                    }
                                }
                            }
                            Divider()
                        }
                        Button(model.isFavorite(channel) ? "Remover dos favoritos" : "Favoritar") {
                            model.toggleFavorite(channel)
                        }
                        Divider()
                        Button("Remover canal", role: .destructive) { model.removeChannel(channel) }
                    }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $model.search, placement: .sidebar, prompt: "Buscar canal")
        .toolbar {
            if showsAddMenu {
                ToolbarItem {
                    Menu {
                        Button("Importar lista .m3u…") { ChannelListActions.importList(into: model) }
                        Button("Adicionar URL…") { ChannelListActions.addByURL(into: model) }
                        Divider()
                        Button("Exportar playlist…") { model.exportPlaylist() }
                    } label: {
                        Label("Adicionar", systemImage: "plus")
                    }
                }
            }
        }
    }
}

@MainActor
enum ChannelListActions {
    static func importList(into model: PlayerModel) {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.message = "Selecione uma lista .m3u / .m3u8"
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        model.addChannels(M3UList.parse(text))
    }

    static func addByURL(into model: PlayerModel) {
        let alert = NSAlert()
        alert.messageText = "Adicionar canal"
        alert.informativeText = "Cole o URL do fluxo (.m3u8)."
        alert.addButton(withTitle: "Adicionar")
        alert.addButton(withTitle: "Cancelar")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 420, height: 56))
        stack.orientation = .vertical
        stack.spacing = 6
        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Nome"
        let urlField = NSTextField(string: "")
        urlField.placeholderString = "https://…/index.m3u8"
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(urlField)
        nameField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        urlField.widthAnchor.constraint(equalToConstant: 420).isActive = true
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else { return }
        let name = nameField.stringValue.isEmpty ? (url.host ?? "Novo canal") : nameField.stringValue
        model.addChannels([Channel(name: name, source: url)])
    }
}

/// Hosting view that acts on the very first click.
///
/// A normal window swallows the click that gives it focus, so every action in
/// a detached list would need two clicks. Accepting the first mouse event makes
/// the pair feel like one window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Panel that never takes key status away from the player.
final class NonStealingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Strip along the top of the list that drags the *player* window.
///
/// Letting the panel be dragged on its own meant reacting to its `didMove` and
/// pushing the player after it — which fights AppKit's own drag loop and comes
/// out stuttering. Handing the event to the parent lets AppKit drag the pair
/// natively: the child window follows its parent for free.
final class ParentDragStrip: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let parent = window?.parent else { return super.mouseDown(with: event) }
        parent.performDrag(with: event)
    }
}

/// Hosts the channel list in its own panel pinned to the left edge of the
/// player. It is a *child* window, so it travels with the player when that one
/// is dragged, and dragging the list brings the player along.
@MainActor
final class SidebarWindowController: NSObject, NSWindowDelegate {
    static let shared = SidebarWindowController()

    private var window: NSPanel?
    /// Held separately because AppKit drops the child-window link while the
    /// player is full screen, which would strand `window.parent` at nil.
    private weak var host: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private let width: CGFloat = 260
    /// Hairline of desk showing between the two windows.
    private let gap: CGFloat = 2
    /// How far the player was pushed right to fit the list, so closing it can
    /// give that space back instead of leaving the video off-centre.
    private var shiftApplied: CGFloat = 0

    private override init() { super.init() }

    var isOpen: Bool { window != nil }

    func toggle(model: PlayerModel) {
        if isOpen { close() } else { open(model: model) }
    }

    func open(model: PlayerModel, attempt: Int = 0) {
        guard window == nil else { return }
        guard let parent = playerWindow else {
            // At first launch `onAppear` fires before the window is on screen.
            guard attempt < 20 else {
                Log.shared.write("lista: janela do player não encontrada")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                SidebarWindowController.shared.open(model: model, attempt: attempt + 1)
            }
            return
        }

        let panel = NonStealingPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: parent.frame.height),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.title = "Canais"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.delegate = self

        let hostView = FirstMouseHostingView(
            rootView: NavigationStack { ChannelListView(model: model, showsAddMenu: false) }
                .frame(minWidth: width))
        panel.contentView = hostView

        let dragStrip = ParentDragStrip()
        dragStrip.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(dragStrip)
        NSLayoutConstraint.activate([
            dragStrip.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            dragStrip.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            dragStrip.topAnchor.constraint(equalTo: hostView.topAnchor),
            dragStrip.heightAnchor.constraint(equalToConstant: 28),
        ])

        window = panel
        host = parent

        // Full screen fills the display. A child window beside it has nowhere
        // to go, and every attempt to accommodate one — nudging the player,
        // hiding and restoring it around the transition — fought AppKit's own
        // animation and left the video displaced. The list simply does not open
        // while full screen, and closes on the way in.
        guard !parent.styleMask.contains(.fullScreen) else {
            window = nil
            host = nil
            model.detachedList = false
            return
        }
        makeRoomOnTheLeft(for: parent)
        parent.addChildWindow(panel, ordered: .above)
        sync()
        panel.orderFront(nil)

        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: parent, queue: .main) { _ in
                Task { @MainActor in SidebarWindowController.shared.sync() }
            })
        }
        // Full screen fills the display, so a panel beside it would land off
        // the edge; it is hidden for the duration and restored on exit.
        observers.append(center.addObserver(
            forName: NSWindow.willEnterFullScreenNotification, object: parent, queue: .main) { _ in
                Task { @MainActor in
                    PlayerModel.shared.detachedList = false
                }
            })
    }

    func close() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        window = nil
        restorePlayerPosition()
        host = nil
    }

    /// Moving either window emits `didMove` *asynchronously*, so a plain
    /// re-entrancy flag does not hold: the echo arrives after the call that set
    /// it has already returned, and each echo nudges the pair again. A short
    /// deadline swallows the echoes instead.
    private var suppressUntil = Date.distantPast

    private func suppressEchoes() {
        suppressUntil = Date().addingTimeInterval(0.2)
    }

    private var offset: CGFloat { width + gap }

    /// Slides the player right when it sits too close to the screen edge for
    /// the list to fit beside it — otherwise the panel opens off-screen.
    private func makeRoomOnTheLeft(for parent: NSWindow) {
        guard let screen = parent.screen ?? NSScreen.main else { return }
        let limit = screen.visibleFrame.minX
        let deficit = limit - (parent.frame.minX - offset)
        guard deficit > 0 else { return }

        var target = parent.frame
        target.origin.x += deficit
        // Shrink instead of pushing the player off the right edge.
        let overflow = target.maxX - screen.visibleFrame.maxX
        if overflow > 0 { target.size.width = max(720, target.width - overflow) }
        parent.setFrame(target, display: true)
        shiftApplied = deficit
    }

    /// Gives back what `makeRoomOnTheLeft` took.
    private func restorePlayerPosition() {
        guard shiftApplied > 0, let parent = host,
              !parent.styleMask.contains(.fullScreen) else { shiftApplied = 0; return }
        var target = parent.frame
        target.origin.x -= shiftApplied
        parent.setFrame(target, display: true)
        shiftApplied = 0
    }

    /// Keeps the panel flush against the player's left edge and the same height.
    private func sync() {
        guard Date() >= suppressUntil, let window, let parent = host else { return }
        suppressEchoes()
        window.setFrame(NSRect(x: parent.frame.minX - offset, y: parent.frame.minY,
                               width: width, height: parent.frame.height),
                        display: true)
    }

    /// Hidden while the player is full screen, without losing the child link.
    private var playerWindow: NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0.parent == nil && !($0 is NSPanel)
                && $0.styleMask.contains(.titled)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        PlayerModel.shared.detachedList = false
    }
}
