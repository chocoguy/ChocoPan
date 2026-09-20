import SwiftData
import Foundation


enum ChocoPanModelContainer {
    static let schema = Schema([
        LibrarySource.self,
        Anime.self,
        AnimeEpisode.self,
        ChocoPanSettings.self,
    ])

    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(
            "ChocoPan",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            print("ChocoPan: failed to open the persistent store (\(error)). Falling back to an in-memory store.")
            return inMemoryContainer()
        }
    }()

    /// In-memory container for SwiftUI previews and tests.
    static let preview: ModelContainer = inMemoryContainer()

    private static func inMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ChocoPan: could not create an in-memory model container: \(error)")
        }
    }
}
