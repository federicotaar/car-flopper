import SwiftUI

@main
struct CarFlopperApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
    }
}

struct RootView: View {
    @StateObject private var flow = FlowModel()

    var body: some View {
        switch flow.screen {
        case .menu:
            MenuView { session in flow.enterLobby(session: session) }
        case .lobby:
            if let vm = flow.vm {
                LobbyView(vm: vm, onStart: { vm.startGame() }, onLeave: { flow.leave() })
            }
        case .game:
            if let vm = flow.vm {
                GameView(vm: vm, onLeave: { flow.leave() })
            }
        }
    }
}

@MainActor
final class FlowModel: ObservableObject {
    enum Screen { case menu, lobby, game }
    @Published var screen: Screen = .menu
    var vm: GameViewModel?

    func enterLobby(session: GameSession) {
        let vm = GameViewModel(session: session)
        self.vm = vm
        self.screen = .lobby
        // watch phase flips to move between lobby and game
        Task { [weak self, weak vm] in
            var lastPhase = "lobby"
        while let vm, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if vm.phase != lastPhase {
                    lastPhase = vm.phase
                    if vm.phase == "play" || vm.phase == "complete" { self?.screen = .game }
                    if vm.phase == "lobby" { self?.screen = .lobby }
                }
                if vm.connectionError != nil { self?.leave(); return }
            }
        }
    }

    func leave() {
        vm?.leave()
        vm = nil
        screen = .menu
    }
}
