import SwiftUI
import Combine
import ARKit

// MARK: - Shelf screen

struct ContentView: View {
    @StateObject private var state = ShelfState()
    @AppStorage("figureShelf.tab") private var tab: ChooserTab = .animals

    private let roomSupported = ARWorldTrackingConfiguration.isSupported

    /// Swipe down on the menu: chooser away (actions stay) -> actions away too, the shelf
    /// fills the screen. Swipe up (or tap the pill / handle) brings it back a step at a time.
    @State private var level: MenuLevel = .full
    @State private var dragDown: CGFloat = 0
    private var fullScreen: Bool { level == .hidden }
    private var swipe: some Gesture { menuSheetSwipe(level: $level, dragDown: $dragDown) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Group {
                    // Only one RealityKit view at a time: the shelf view is taken down while
                    // the room (camera) view is open, so the camera picture is never blocked.
                    if state.showingRoom {
                        Color(uiColor: UIColor(hex: 0xF3EEE6))
                    } else {
                        StageView(
                            mode: .shelf,
                            look: state.look,
                            actionRequest: state.actionRequest,
                            keepGoing: state.keepGoing,
                            resetViewID: state.resetViewID,
                            onTurned: { if !state.viewTurned { state.viewTurned = true } }
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: fullScreen ? 0 : 28, style: .continuous))
                .padding(.horizontal, fullScreen ? 0 : 16)
                .padding(.top, fullScreen ? 0 : 8)
                .ignoresSafeArea(edges: fullScreen ? .all : [])

                HStack(spacing: 10) {
                    UndoButton(state: state)
                    ResetButton(state: state)
                    SoundButton()
                    ParentsButton()
                    Spacer()
                    if roomSupported {
                        Button {
                            state.showingRoom = true
                        } label: {
                            ViewThatFits(in: .horizontal) {
                                Label("See in my room", systemImage: "camera.viewfinder").padding(.horizontal, 18)
                                Label("My room", systemImage: "camera.viewfinder").padding(.horizontal, 14)
                                Image(systemName: "camera.viewfinder").padding(.horizontal, 14)
                            }
                            .font(.headline)
                            .lineLimit(1)
                            .frame(height: 52)
                            .background(Palette.selected, in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(SoftPressStyle())
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                if fullScreen {
                    VStack {
                        Spacer()
                        ShowMenuPill { level = .actions }
                            .padding(.bottom, 8)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            if !fullScreen {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        MenuHandle(color: Palette.inkDisabled) { if level == .actions { level = .full } }
                        ActionBar(state: state)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(swipe)
                    if level == .full {
                        ChooserPanel(state: state, tab: $tab, tabSwipe: swipe)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .offset(y: max(0, dragDown))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.45), value: level)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dragDown)
        .onAppear {
            // Launch options for making store screenshots (only from the launch arguments, never saved):
            // -figureShelf.menuLevel 0|1|2 and -figureShelf.autoplay dance|jump|run|spin|wave
            let d = UserDefaults.standard
            if d.object(forKey: "figureShelf.menuLevel") != nil,
               let l = MenuLevel(rawValue: d.integer(forKey: "figureShelf.menuLevel")) { level = l }
            if let a = d.string(forKey: "figureShelf.autoplay"), let action = FigureAction(rawValue: a) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { state.play(action) }
            }
        }
        .fullScreenCover(isPresented: $state.showingRoom) {
            RoomView(state: state, tab: $tab)
        }
    }
}

// MARK: - Two-step menu (room and shelf)

/// Swipe down steps the menu: everything -> only the action buttons -> hidden.
/// Swipe up on the action buttons brings everything back; a hidden menu comes back from its pill.
enum MenuLevel: Int { case hidden, actions, full }

/// Swipe down (distance or a quick flick) hides the menu like a sheet; the menu follows the finger.
/// Only clearly vertical drags count, so sideways drags (turning the figure) are left alone.
func menuSheetSwipe(level: Binding<MenuLevel>, dragDown: Binding<CGFloat>,
                    onEnd: @escaping () -> Void = {}) -> some Gesture {
    DragGesture(minimumDistance: 16)
        .onChanged { g in
            if g.translation.height > abs(g.translation.width) { dragDown.wrappedValue = g.translation.height }
        }
        .onEnded { g in
            let down = g.translation.height > abs(g.translation.width)
            let up = -g.translation.height > abs(g.translation.width)
            if down && (g.translation.height > 80 || g.predictedEndTranslation.height > 200) {
                level.wrappedValue = level.wrappedValue == .full ? .actions : .hidden    // one step down
            } else if up && (g.translation.height < -50 || g.predictedEndTranslation.height < -150) {
                level.wrappedValue = .full                                             // all back
            }
            onEnd()
            dragDown.wrappedValue = 0
        }
}

/// The pill a hidden menu leaves behind: tap it or swipe up on it to get the action buttons back.
struct ShowMenuPill: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Capsule().fill(Palette.inkDisabled).frame(width: 36, height: 5)
                Label("Show menu", systemImage: "chevron.up")
                    .font(.headline)
            }
            .padding(.horizontal, 26)
            .frame(minWidth: 180, minHeight: 60)
            .background(Capsule().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 5, y: 2))
            .foregroundStyle(Palette.ink)
        }
        .buttonStyle(SoftPressStyle())
        .padding(.top, 30)                       // a bigger area to swipe up on
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { g in
            if g.translation.height < -30 || g.predictedEndTranslation.height < -80 { action() }
        })
    }
}

/// The grab handle at the top of a menu: swipe it down to make the menu smaller.
struct MenuHandle: View {
    var color: Color = Palette.panel
    let tap: () -> Void
    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: 44, height: 6)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .accessibilityLabel("Swipe down to make the menu smaller, up to show it all")
    }
}

// MARK: - Room (AR) screen

struct RoomView: View {
    @ObservedObject var state: ShelfState
    @Binding var tab: ChooserTab
    @State private var placed = false
    @State private var cameraOff = false
    /// The bottom menu slides away after 15 s without a touch; any touch brings it back.
    /// Swipe down steps the menu: everything -> only the action buttons -> hidden. Swipe up
    /// (or tap the pill) brings it back. Only the menu itself changes it, not touches on the room.
    @State private var level: MenuLevel = .full
    private var menuHidden: Bool { level == .hidden }
    @State private var lastTouch = Date()
    /// The "pinch / twist" tip shows for 5 s after the figure lands on the floor.
    @State private var showTip = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            StageView(
                mode: .room,
                look: state.look,
                actionRequest: state.actionRequest,
                keepGoing: state.keepGoing,
                onPlacedChange: { now in
                    placed = now
                    if now { showTipForAWhile() }
                },
                onCameraOff: { cameraOff = true },
                turnRequest: state.turnRequest,
                onTouch: { touched() }
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Button {
                        state.showingRoom = false
                    } label: {
                        ViewThatFits(in: .horizontal) {
                            Label("Back to shelf", systemImage: "house.fill").padding(.horizontal, 18)
                            Label("Shelf", systemImage: "house.fill").padding(.horizontal, 14)
                        }
                            .font(.headline)
                            .lineLimit(1)
                            .frame(height: 52)
                            .background(Capsule().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                            .foregroundStyle(Palette.ink)
                    }
                    .buttonStyle(SoftPressStyle())
                    Spacer()
                    SoundButton()
                    ResetButton(state: state)
                    UndoButton(state: state)
                }
                .simultaneousGesture(TapGesture().onEnded { touched() })

                if let tip = tipText {
                    Text(tip)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                        .foregroundStyle(Palette.ink)
                        .transition(.opacity)
                }

                Spacer()

                if menuHidden {
                    ShowMenuPill { showMenu(.actions) }
                        .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        VStack(spacing: 10) {
                            // grab handle: swipe the menu down to see the room
                            MenuHandle { if level == .actions { showMenu(.full) } }
                            TurnButtons(state: state)
                            ActionBar(state: state)
                        }
                        .simultaneousGesture(sheetSwipe)
                        if level == .full {
                            ChooserPanel(state: state, tab: $tab, compact: true, tabSwipe: sheetSwipe)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .offset(y: max(0, dragDown))
                    .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in touched() })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(16)
        }
        .animation(.easeInOut(duration: 0.45), value: level)
        .animation(.easeInOut(duration: 0.6), value: tipText)
        .onReceive(tick) { now in
            // one step every 15 s without a touch: full -> actions only -> hidden
            if level != .hidden, now.timeIntervalSince(lastTouch) > 15 {
                level = level == .full ? .actions : .hidden
                lastTouch = now
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: dragDown)
        .onChange(of: state.look) { _, _ in touched() }
        .onChange(of: state.actionRequest) { _, _ in touched() }
    }

    private var tipText: String? {
        if cameraOff { return "Camera is off. You can turn it on in Settings." }
        if !placed { return "Move your phone slowly to find the floor." }
        return showTip ? "Tap the floor to move me. Pinch to resize, twist to turn." : nil
    }

    @State private var dragDown: CGFloat = 0

    private var sheetSwipe: some Gesture {
        menuSheetSwipe(level: $level, dragDown: $dragDown) { lastTouch = Date() }
    }

    /// Any touch keeps the shown menu awake for another 15 s.
    private func touched() {
        lastTouch = Date()          // keeps the menu awake; only the pill brings a hidden menu back
    }

    /// From the pill (tap or swipe up): one step up, to the action buttons.
    private func showMenu(_ to: MenuLevel = .full) {
        lastTouch = Date()
        level = to
    }

    private func showTipForAWhile() {
        showTip = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            showTip = false
        }
    }
}

/// Two calm round buttons that turn the figure a little (easier than a two-finger twist).
struct TurnButtons: View {
    @ObservedObject var state: ShelfState

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            ForEach([(Float(1), "arrow.counterclockwise"), (Float(-1), "arrow.clockwise")], id: \.1) { dir, icon in
                Button {
                    state.turn(by: dir * .pi / 4)
                } label: {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(SoftPressStyle())
                .accessibilityLabel(dir > 0 ? "Turn left" : "Turn right")
            }
        }
    }
}

// MARK: - Undo

struct UndoButton: View {
    @ObservedObject var state: ShelfState

    var body: some View {
        Button {
            state.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                .foregroundStyle(state.canUndo ? Palette.ink : Palette.inkDisabled)
        }
        .buttonStyle(SoftPressStyle())
        .disabled(!state.canUndo)
        .accessibilityLabel("Undo")
    }
}

// MARK: - Reset

/// Takes off everything, Normal color, stops, turns back. No question asked: Undo brings it back.
struct ResetButton: View {
    @ObservedObject var state: ShelfState

    var body: some View {
        Button {
            state.reset()
        } label: {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                .foregroundStyle(state.isDefault ? Palette.inkDisabled : Palette.ink)
        }
        .buttonStyle(SoftPressStyle())
        .disabled(state.isDefault)
        .accessibilityLabel("Start fresh")
    }
}

// MARK: - Sound on / off

struct SoundButton: View {
    @AppStorage(SoundBoard.storageKey) private var soundOn = true

    var body: some View {
        Button {
            soundOn.toggle()
            if !soundOn { SoundBoard.shared.stopAll() }
        } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Circle().fill(Palette.panel).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(soundOn ? "Sound on" : "Sound off")
    }
}

// MARK: - Actions

struct ActionBar: View {
    @ObservedObject var state: ShelfState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FigureAction.allCases) { action in
                Button {
                    state.play(action)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 24, weight: .semibold))
                        Text(action.name)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Palette.action, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(Palette.actionInk)
                }
                .buttonStyle(SoftPressStyle())
            }

            Button {
                if state.keepGoing { state.stop() } else { state.keepGoing = true }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: state.keepGoing ? "repeat.circle.fill" : "repeat")
                        .font(.system(size: 24, weight: .semibold))
                    Text(state.keepGoing ? "Stop" : "Again")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(state.keepGoing ? Palette.selected : Palette.tile,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(state.keepGoing ? .white : Palette.ink)
            }
            .buttonStyle(SoftPressStyle())
            .accessibilityLabel(state.keepGoing ? "Stop repeating" : "Keep repeating")
        }
    }
}

// MARK: - Chooser (animals, colors, extras)

enum ChooserTab: String, CaseIterable, Identifiable {
    case animals, colors, extras
    var id: String { rawValue }
    var title: String {
        switch self {
        case .animals: "Animals"
        case .colors: "Colors"
        case .extras: "Accessories"
        }
    }
    var symbol: String {
        switch self {
        case .animals: "pawprint.fill"
        case .colors: "paintpalette.fill"
        case .extras: "sparkles"
        }
    }
}

struct ChooserPanel<Swipe: Gesture>: View {
    @ObservedObject var state: ShelfState
    @Binding var tab: ChooserTab
    var compact = false
    /// Room view: swiping down on the tab row hides the menu (the grids keep their own scrolling).
    var tabSwipe: Swipe?

    private var tileSize: CGFloat { compact ? 72 : 88 }

    var body: some View {
        VStack(spacing: 10) {
            tabRow
            content
        }
        .padding(16)
        .background(Palette.panel)
    }

    @ViewBuilder private var tabRow: some View {
        if let tabSwipe {
            tabs.simultaneousGesture(tabSwipe)
        } else {
            tabs
        }
    }

    private var tabs: some View {
            HStack(spacing: 8) {
                ForEach(ChooserTab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        Label(t.title, systemImage: t.symbol)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(tab == t ? Palette.ink : Palette.tile, in: Capsule())
                            .foregroundStyle(tab == t ? .white : Palette.ink)
                    }
                    .buttonStyle(SoftPressStyle())
                }
            }
    }

    @ViewBuilder private var content: some View {
            if tab == .animals {
                AnimalGrid(state: state, compact: compact)
            } else if tab == .extras {
                WearGrid(state: state, compact: compact)
            } else {
                VStack(spacing: 10) {
                    colorRow
                    if RealModelLibrary.supportsPatterns(state.look.animal) { patternRow }
                }
            }
    }

    /// Patterns over the colour (toy animals only): each tile shows the pattern on the
    /// chosen colour.
    private var patternRow: some View {
        let c = state.look.skin.colors(for: state.look.animal)
        let main = Color(uiColor: c.main)
        let mark: Color = c.main.lightness < 0.6 ? .white.opacity(0.9) : .black.opacity(0.45)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Pattern.allCases) { pattern in
                    Tile(label: pattern.name, selected: state.look.pattern == pattern, size: tileSize) {
                        ZStack {
                            Circle().fill(main)
                            if pattern != .plain {
                                Image(systemName: pattern.symbol)
                                    .font(.system(size: tileSize * 0.22, weight: .bold))
                                    .foregroundStyle(mark)
                            }
                        }
                        .frame(width: tileSize * 0.5, height: tileSize * 0.5)
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    } action: { state.choose(pattern: pattern) }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    private var colorRow: some View {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        do {
                            ForEach(Skin.allCases) { skin in
                                let c = skin.colors(for: state.look.animal)
                                Tile(label: skin.name, selected: state.look.skin == skin, size: tileSize) {
                                    ZStack {
                                        Circle().fill(Color(uiColor: c.main))
                                        Circle().fill(Color(uiColor: c.belly)).scaleEffect(0.45).offset(y: tileSize * 0.08)
                                    }
                                    .frame(width: tileSize * 0.5, height: tileSize * 0.5)
                                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                                } action: { state.choose(skin: skin) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
    }
}

private extension UIColor {
    /// 0 (black) ... 1 (white), how light the colour looks.
    var lightness: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}

extension ChooserPanel where Swipe == DragGesture {
    /// The shelf screen: no swipe on the tab row.
    init(state: ShelfState, tab: Binding<ChooserTab>, compact: Bool = false) {
        self.init(state: state, tab: tab, compact: compact, tabSwipe: nil)
    }
}

/// All animals and creatures at once, in two small groups, so nothing hides off-screen.
struct AnimalGrid: View {
    @ObservedObject var state: ShelfState
    var compact = false

    private var spacing: CGFloat { compact ? 6 : 8 }

    var body: some View {
        GeometryReader { geo in
            let columns = 6
            let size = floor((geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(AnimalGroup.allCases.filter { !Animal.all(in: $0).isEmpty }) { group in
                    Text(group.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                        .padding(.leading, 2)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: spacing), count: columns),
                              alignment: .leading, spacing: spacing) {
                        ForEach(Animal.all(in: group)) { animal in
                            Tile(label: animal.name, selected: state.look.animal == animal, size: size,
                                 cornerRadius: 14, labelFont: .system(size: 10, weight: .semibold)) {
                                if let emoji = animal.emoji {
                                    Text(emoji).font(.system(size: size * 0.45))
                                } else if let image = animal.thumbnail {
                                    Image(uiImage: image).resizable().scaledToFit()
                                } else {
                                    Circle().fill(Color(uiColor: animal.mainColor)).padding(size * 0.12)
                                }
                            } action: { state.choose(animal: animal) }
                        }
                    }
                }
            }
            .padding(.bottom, 4)
            }
        }
        .frame(height: gridHeight)
    }

    /// Height for two headings plus the tile rows (1 row of animals, 2 of creatures),
    /// using the phone's width so the grid never needs to scroll.
    private var gridHeight: CGFloat { Self.height(compact: compact) }

    static func height(compact: Bool) -> CGFloat {
        let spacing: CGFloat = compact ? 6 : 8
        let width = UIScreen.main.bounds.width - (compact ? 64 : 32)
        let size = floor((width - spacing * 5) / 6)
        // the panel shows about three rows with their headings; more scrolls up and down
        let rows = 4, groups = 3
        return CGFloat(rows) * size + CGFloat(rows - 1 + 2 * groups) * spacing + CGFloat(groups) * 16
    }
}

/// Hats, glasses, masks and neck things: one of each can be worn. Tap again to take off.
/// Scrolls up and down if it is taller than the panel (never sideways).
struct WearGrid: View {
    @ObservedObject var state: ShelfState
    var compact = false

    private var spacing: CGFloat { compact ? 6 : 8 }
    private let columns = 6

    var body: some View {
        GeometryReader { geo in
            let size = floor((geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(WearSlot.allCases) { slot in
                        Text(slot.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                            .padding(.leading, 2)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: spacing), count: columns),
                                  alignment: .leading, spacing: spacing) {
                            Tile(label: "None", selected: state.look.wearing(slot) == nil, size: size,
                                 cornerRadius: 14, labelFont: .system(size: 10, weight: .semibold)) {
                                Image(systemName: "circle.slash").font(.system(size: size * 0.32))
                                    .foregroundStyle(Palette.ink.opacity(0.45))
                            } action: { state.takeOff(slot) }
                            ForEach(Wearable.all(in: slot)) { item in
                                Tile(label: item.name, selected: state.look.wearing(slot) == item, size: size,
                                     cornerRadius: 14, labelFont: .system(size: 10, weight: .semibold)) {
                                    Text(item.emoji).font(.system(size: size * 0.4))
                                } action: { state.toggle(item) }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(height: AnimalGrid.height(compact: compact))
    }
}

struct Tile<Content: View>: View {
    let label: String
    let selected: Bool
    let size: CGFloat
    var cornerRadius: CGFloat = 20
    var labelFont: Font = .caption.weight(.semibold)
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                content()
                    .frame(height: size * 0.6)
                Text(label)
                    .font(labelFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: size, height: size)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(selected ? Palette.selected : .clear, lineWidth: size < 70 ? 3 : 4)
            )
            .animation(.easeInOut(duration: 0.2), value: selected)
        }
        .buttonStyle(SoftPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Button style

/// A small, calm press effect. No sounds, no haptics.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
