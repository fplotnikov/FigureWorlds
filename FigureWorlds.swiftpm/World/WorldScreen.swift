import SwiftUI

/// The whole app: the village fills the screen, with a few big round buttons on top.
/// Nothing is locked, nothing to read, nothing to finish.
struct WorldScreen: View {
    @StateObject private var me = ShelfState(storageKey: "figureWorlds.look")
    @StateObject private var friend = ShelfState(storageKey: "figureWorlds.friend", defaultLook: WorldScreen.friendStart)
    @StateObject private var controls = WorldControls()
    @State private var showCharacters = false
    @State private var showActions = false
    @State private var showMap = false
    @State private var tab: ChooserTab = .animals

    static var friendStart: Look {
        var look = Look()
        look.animal = .fox
        return look
    }

    var body: some View {
        ZStack {
            WorldView(look: me.look, friendLook: friend.look, actionRequest: me.actionRequest,
                      keepGoing: me.keepGoing, controls: controls)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    RoundButton(symbol: "map.fill", highlighted: showMap, label: "Map") {
                        withAnimation(.spring(duration: 0.3)) { showMap.toggle() }
                    }
                    Spacer()
                    SoundButton()
                }
                Spacer()
                if showActions {
                    ActionBar(state: me)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(Palette.panel.opacity(0.96))
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 2))
                        .frame(maxWidth: 560)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(alignment: .bottom, spacing: 14) {
                    CharacterButton(animal: me.look.animal) { showCharacters = true }
                    RoundButton(symbol: "figure.dance", highlighted: showActions, label: "Moves") {
                        withAnimation(.easeInOut(duration: 0.25)) { showActions.toggle() }
                    }
                    Spacer()
                    if controls.canUndoTidy {
                        RoundButton(symbol: "arrow.uturn.backward", label: "Put things back where they were") {
                            controls.undoTidy()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    RoundButton(symbol: "sparkles", label: "Tidy up") { controls.tidyUp() }
                    RoundButton(symbol: "camera.rotate", label: "Look behind the animal") { controls.recenter() }
                }
                .animation(.easeInOut(duration: 0.2), value: controls.canUndoTidy)
            }
            .padding(16)

            if showMap {
                MapPicker(current: controls.scene) { place in
                    withAnimation(.easeInOut(duration: 0.25)) { showMap = false }
                    controls.go(to: place)
                } close: {
                    withAnimation(.easeInOut(duration: 0.25)) { showMap = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .sheet(isPresented: $showCharacters) {
            CharacterSheet(me: me, friend: friend, tab: $tab)
        }
        .onChange(of: showCharacters) { _, open in
            controls.chooserOpen = open
        }
        .onChange(of: controls.wardrobeRequest) { _, _ in
            // A wardrobe was opened: show the outfits (accessories) for his animal.
            tab = .extras
            showCharacters = true
        }
        .onAppear {
            let state = me
            controls.stopActing = { [weak state] in state?.stop() }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

/// The map: one big picture button per place. Tap one to go there; tap outside to close.
struct MapPicker: View {
    let current: SceneKind
    let choose: (SceneKind) -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { close() }
            ViewThatFits {
                HStack(spacing: 18) { tiles }
                VStack(spacing: 18) { tiles }
                // Smaller screens: two columns.
                LazyVGrid(columns: [GridItem(.fixed(120), spacing: 18), GridItem(.fixed(120), spacing: 18)], spacing: 18) { tiles }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Palette.panel.opacity(0.97))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4))
            .padding(24)
        }
    }

    @ViewBuilder private var tiles: some View {
        ForEach(SceneKind.allCases) { place in
            Button {
                SoundBoard.shared.pop()
                choose(place)
            } label: {
                Text(place.emoji)
                    .font(.system(size: 58))
                    .frame(width: 120, height: 120)
                    .background(Circle().fill(Color(UIColor(hex: place.sky))))
                    .overlay(Circle().stroke(place == current ? Palette.selected : Color.clear, lineWidth: 5))
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel(place.name)
            .accessibilityAddTraits(place == current ? .isSelected : [])
        }
    }
}

struct RoundButton: View {
    let symbol: String
    var highlighted = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
                .background(Circle().fill(highlighted ? Palette.selected : Palette.panel)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                .foregroundStyle(highlighted ? Color.white : Palette.ink)
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(label)
    }
}

struct CharacterButton: View {
    let animal: Animal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Animals without an emoji show their little rendered picture.
            Group {
                if let emoji = animal.emoji {
                    Text(emoji).font(.system(size: 34))
                } else if let picture = animal.thumbnail {
                    Image(uiImage: picture).resizable().scaledToFit().padding(6)
                } else {
                    Text("🙂").font(.system(size: 34))
                }
            }
                .frame(width: 68, height: 68)
                .background(Circle().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                .overlay(Circle().stroke(Palette.selected, lineWidth: 3))
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel("Change animal")
    }
}

/// The Figure Shelf chooser, for his animal or for the friend.
struct CharacterSheet: View {
    @ObservedObject var me: ShelfState
    @ObservedObject var friend: ShelfState
    @Binding var tab: ChooserTab
    @State private var forFriend = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                whoButton(me.look.animal, friend: false, selected: !forFriend, label: "My animal") { forFriend = false }
                whoButton(friend.look.animal, friend: true, selected: forFriend, label: "Friend") { forFriend = true }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Palette.selected))
                        .foregroundStyle(.white)
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel("Done")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            ScrollView {
                if forFriend {
                    ChooserPanel(state: friend, tab: $tab)
                } else {
                    ChooserPanel(state: me, tab: $tab)
                }
            }
        }
        .background(Palette.panel)
        .presentationDetents([.medium, .large])
    }

    private func whoButton(_ animal: Animal, friend: Bool, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if friend { Text("🤝") }
                // Animals without an emoji show their little rendered picture.
                if let emoji = animal.emoji {
                    Text(emoji)
                } else if let picture = animal.thumbnail {
                    Image(uiImage: picture).resizable().scaledToFit().frame(width: 40, height: 40)
                } else {
                    Text("🙂")
                }
            }
                .font(.system(size: 30))
                .frame(width: 92, height: 58)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Palette.selected.opacity(0.22) : Palette.tile))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Palette.selected : Color.clear, lineWidth: 3))
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
