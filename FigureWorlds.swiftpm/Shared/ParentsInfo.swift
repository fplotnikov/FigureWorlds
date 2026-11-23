import SwiftUI
import SafariServices

// MARK: - Links (change these when the real pages are online)

/// Privacy policy shown to parents (also entered in App Store Connect).
let PRIVACY_URL = URL(string: "https://fplotnikov.github.io/figureshelf-web/privacy.html")!
/// Support / contact page (also entered in App Store Connect).
let SUPPORT_URL = URL(string: "https://fplotnikov.github.io/figureshelf-web/support.html")!

// MARK: - The quiet "i" button: press and hold 3 seconds

/// A small round "i" in the top bar. A short tap only shows "Hold for parents"; holding it
/// for 3 seconds (a ring fills while holding) opens the parents' sheet.
struct ParentsButton: View {
    @State private var holding = false
    @State private var progress: CGFloat = 0
    @State private var showHint = false
    @State private var showSheet = false
    private static let holdTime: Double = 3

    var body: some View {
        Image(systemName: "info")
            .font(.headline.weight(.semibold))
            .foregroundStyle(Palette.inkDisabled)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Palette.panel).shadow(color: .black.opacity(0.15), radius: 3, y: 1))
            .overlay(
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Palette.selected, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            )
            .frame(width: 52, height: 52)                 // comfortable target, small look
            .contentShape(Circle())
            .overlay(alignment: .bottom) {
                if showHint {
                    Text("Hold for parents")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.panel).shadow(color: .black.opacity(0.15), radius: 2, y: 1))
                        .fixedSize()
                        .offset(y: 30)
                        .transition(.opacity)
                }
            }
            .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 30) {
                progress = 0
                showSheet = true
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: Self.holdTime)) { progress = 1 }
                } else {
                    if progress < 1 { flashHint() }
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .accessibilityLabel("For parents. Press and hold for three seconds.")
            .sheet(isPresented: $showSheet) { ParentsSheet() }
    }

    private func flashHint() {
        withAnimation(.easeInOut(duration: 0.2)) { showHint = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.3)) { showHint = false }
        }
    }
}

// MARK: - The parents' sheet

struct ParentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var openURL: URL?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Palette.tile))
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("Close")
            }
            .padding([.top, .horizontal], 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Figure Shelf").font(.largeTitle.weight(.bold))
                        Text(version).font(.subheadline).foregroundStyle(Palette.inkDisabled)
                    }

                    Text("A calm toy shelf: pick a figure, change its colours and accessories, and watch it move. In “See in my room” the figure stands on your floor through the camera.")
                        .font(.body)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("No data collected", systemImage: "hand.raised.fill").font(.headline)
                        Text("No accounts, ads, tracking or purchases. The camera picture is only used live on this device for the room view; nothing is recorded, saved or sent.")
                            .font(.subheadline)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Palette.tile))

                    VStack(spacing: 12) {
                        linkButton("Privacy Policy", icon: "lock.shield", url: PRIVACY_URL)
                        linkButton("Support", icon: "questionmark.circle", url: SUPPORT_URL)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Credits").font(.headline)
                        Text("3D models made with Meshy AI. Sounds made for Figure Shelf. No data collected.")
                            .font(.subheadline)
                    }
                }
                .foregroundStyle(Palette.ink)
                .padding(24)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .sheet(item: $openURL) { url in
            SafariView(url: url).ignoresSafeArea()
        }
    }

    private func linkButton(_ title: String, icon: String, url: URL) -> some View {
        Button { openURL = url } label: {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Palette.inkDisabled)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.panel).shadow(color: .black.opacity(0.08), radius: 3, y: 1))
            .foregroundStyle(Palette.ink)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The links open inside the app (Safari view), so a child is never sent out to the browser.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
