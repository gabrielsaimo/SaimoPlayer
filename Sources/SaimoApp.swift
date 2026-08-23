import SwiftUI
import AppKit

/// Closing the window quits: this is a single-window player, and leaving it
/// running with no window would keep the proxy and any ffmpeg session alive
/// with nothing on screen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Remuxer.shared.stopAll()
    }
}

@main
struct SaimoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = PlayerModel.shared

    init() {
        do {
            try ProxyServer.shared.start()
        } catch {
            Log.shared.write("falha ao subir proxy: \(error)")
        }
        PlayerModel.shared.installKeyMonitor()
    }

    var body: some Scene {
        WindowGroup("Saimo TV") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Reprodução") {
                Button(model.isPlaying ? "Pausar" : "Tocar") { model.togglePlayPause() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Ir ao vivo") { model.jumpToLive() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Recarregar fluxo") { model.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Canal anterior") { model.step(-1) }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button("Próximo canal") { model.step(1) }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Divider()
                Button(model.isMuted ? "Ativar som" : "Silenciar") { model.isMuted.toggle() }
                    .keyboardShortcut("m", modifiers: .command)
                Button("Aumentar volume") { model.nudgeVolume(0.05) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Diminuir volume") { model.nudgeVolume(-0.05) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }

            CommandGroup(after: .sidebar) {
                Button(model.detachedList ? "Lista junto à janela" : "Lista em janela separada") {
                    model.detachedList.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }

            CommandMenu("Guia") {
                Button("Programação") { model.showGuide = true }
                Button("Filmes e Séries") { model.showVod = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .keyboardShortcut("g", modifiers: .command)
                Button("Atualizar guia") { EPGService.shared.refresh(channels: model.channels) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }

            CommandMenu("Vídeo") {
                Button("Picture in Picture") { model.togglePiP() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!model.isPiPPossible)
                Button("Tela cheia") { model.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                Button(model.fillScreen ? "Ajustar à tela" : "Preencher tela") {
                    model.fillScreen.toggle()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Button(model.alwaysOnTop ? "Não manter à frente" : "Manter à frente") {
                    model.alwaysOnTop.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button(model.showStats ? "Ocultar estatísticas" : "Mostrar estatísticas") {
                    model.showStats.toggle()
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}
