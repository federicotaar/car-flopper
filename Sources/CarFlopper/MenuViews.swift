import SwiftUI

// MARK: - Menu flow: title -> create/join -> lobby

struct MenuView: View {
    @State private var nickname: String = UserDefaults.standard.string(forKey: "carflopper.nick") ?? ""
    @State private var joinCode: String = ""
    @State private var busy = false
    @State private var error: String?
    var onEnter: (GameSession) -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer().frame(height: 30)
                    Text("CAR FLOPPER")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("fix wrecked cars with your friends")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    garageCard

                    VStack(spacing: 12) {
                        TextField("your nickname", text: $nickname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                            .onChange(of: nickname) { _, v in
                                UserDefaults.standard.set(v, forKey: "carflopper.nick")
                            }

                        Button(action: createRoom) {
                            Label("CREATE GARAGE", systemImage: "plus")
                                .font(.headline.weight(.heavy))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.orange, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                        }
                        .disabled(busy || nickname.trimmingCharacters(in: .whitespaces).isEmpty)

                        HStack {
                            TextField("CODE", text: $joinCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.title3, design: .monospaced).weight(.bold))
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                                .onChange(of: joinCode) { _, v in
                                    joinCode = String(v.uppercased().filter("ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains).prefix(4))
                                }
                            Button(action: joinRoom) {
                                Text("JOIN")
                                    .font(.headline.weight(.heavy))
                                    .padding(.horizontal, 22).padding(.vertical, 14)
                                    .background(joinCode.count == 4 ? Color.green : Color.gray, in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(.black)
                            }
                            .disabled(busy || joinCode.count != 4 || nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, 28)

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if busy { ProgressView().tint(.white) }
                    Spacer()
                }
            }
        }
    }

    private var garageCard: some View {
        VStack(spacing: 8) {
            Text("YOUR GARAGE")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 14) {
                ForEach(Array(GameContent.cars.enumerated()), id: \.offset) { i, car in
                    VStack(spacing: 4) {
                        Image(systemName: UnlockStore.isUnlocked(i) ? "car.fill" : "lock.fill")
                            .font(.title2)
                            .foregroundStyle(UnlockStore.isUnlocked(i) ? .green : .gray)
                        Text(car.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 28)
    }

    private func createRoom() {
        busy = true; error = nil
        Task {
            do {
                let code = try await RoomClient.createRoom()
                try enter(code: code)
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func joinRoom() {
        busy = true; error = nil
        Task {
            do {
                if try await RoomClient.roomExists(joinCode) {
                    try enter(code: joinCode)
                } else {
                    self.error = NetError.roomNotFound.localizedDescription
                }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }

    private func enter(code: String) throws {
        let s = GameSession(code: code, name: nickname.trimmingCharacters(in: .whitespaces))
        try s.connect()
        onEnter(s)
    }
}

// MARK: - Lobby

struct LobbyView: View {
    @ObservedObject var vm: GameViewModel
    var onStart: () -> Void
    var onLeave: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer().frame(height: 40)
                Text("GARAGE CODE")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.6))
                Text(vm.roomCode.isEmpty ? "...." : vm.roomCode)
                    .font(.system(size: 64, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.green)
                    .tracking(10)
                Text("share it with your friends")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.players) { p in
                        HStack(spacing: 10) {
                            Circle().fill(Color(GameContent.playerColor(p.color))).frame(width: 14, height: 14)
                            Text(p.name).foregroundStyle(.white)
                            if p.id == vm.session.myId { Text("(you)").foregroundStyle(.white.opacity(0.5)) }
                            if p.id == vm.hostId { Image(systemName: "crown.fill").foregroundStyle(.yellow) }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 40)

                // car pick (host chooses start car among locally unlocked)
                HStack(spacing: 12) {
                    ForEach(Array(GameContent.cars.enumerated()), id: \.offset) { i, car in
                        Button { vm.pickCar(i) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: UnlockStore.isUnlocked(i) ? "car.fill" : "lock.fill")
                                Text(car.name).font(.caption2)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(i == vm.carIndex ? Color.orange.opacity(0.5) : Color.white.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                        }
                        .disabled(!vm.isHost || !UnlockStore.isUnlocked(i))
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
                if vm.isHost {
                    Button(action: onStart) {
                        Text("START FIXING")
                            .font(.headline.weight(.heavy))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                    .padding(.horizontal, 40)
                    .disabled(vm.players.isEmpty)
                } else {
                    Text("waiting for the host to start...")
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button("leave", action: onLeave)
                    .foregroundStyle(.red.opacity(0.8))
                Spacer().frame(height: 20)
            }
        }
    }
}
