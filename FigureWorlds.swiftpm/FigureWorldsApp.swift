import SwiftUI

@main
struct FigureWorldsApp: App {
    init() {
        RealModelLibrary.shared.preloadAll()
    }

    var body: some Scene {
        WindowGroup {
            WorldScreen()
                .preferredColorScheme(.light)   // the toy palette is designed for light mode
        }
    }
}
