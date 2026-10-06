import Foundation

struct EventTeam: Decodable, Identifiable {
    var id: String { name }
    let name: String
    let image: String
}

struct EventTeams: Decodable {
    let home: EventTeam?
    let away: EventTeam?
}

struct EventLeague: Decodable {
    let name: String
    let image: String?
}

struct Event: Decodable, Identifiable {
    let id: Int
    let slug: String
    let title: String
    let league: EventLeague?
    let teams: EventTeams?
    let time_start: String
    let time_end: String
    let players: [String]
    
    var channelSlug: String? {
        guard let firstPlayer = players.first, let url = URL(string: firstPlayer) else { return nil }
        return url.lastPathComponent
    }
}

@MainActor
final class EventsService: ObservableObject {
    static let shared = EventsService()
    
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var error: String?
    
    func loadEvents() async {
        guard events.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        guard let url = URL(string: "https://embedtv.cc/api/events") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            self.events = try decoder.decode([Event].self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

import SwiftUI

struct EventsView: View {
    @ObservedObject var model: PlayerModel
    @StateObject private var service = EventsService.shared
    
    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 18)]
    
    var body: some View {
        Group {
            if service.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Carregando eventos...")
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let error = service.error {
                VStack {
                    Spacer()
                    Text("Erro: \(error)")
                        .foregroundStyle(.red)
                    Button("Tentar Novamente") {
                        Task { await service.loadEvents() }
                    }
                    .padding()
                    Spacer()
                }
            } else if service.events.isEmpty {
                VStack {
                    Spacer()
                    Text("Nenhum evento no momento")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(service.events) { event in
                            EventCell(event: event) {
                                playEvent(event)
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .task {
            await service.loadEvents()
        }
    }
    
    private func playEvent(_ event: Event) {
        guard let slug = event.channelSlug else { return }
        model.playChannel(bySlug: slug)
        VodEstado.shared.secao = nil
    }
}

struct EventCell: View {
    let event: Event
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                
                VStack(spacing: 12) {
                    HStack {
                        if let homeImage = event.teams?.home?.image, let url = URL(string: homeImage) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.clear
                            }
                            .frame(width: 40, height: 40)
                        }
                        
                        Text("X")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        if let awayImage = event.teams?.away?.image, let url = URL(string: awayImage) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Color.clear
                            }
                            .frame(width: 40, height: 40)
                        }
                    }
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            
            Text(event.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2, reservesSpace: true)
                .foregroundStyle(.white)
            
            if let league = event.league?.name {
                Text(league)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .help(event.title)
    }
}
