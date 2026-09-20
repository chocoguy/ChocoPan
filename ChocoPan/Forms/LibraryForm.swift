import SwiftData
import SwiftUI

struct LibraryForm: View {
    @Query private var librarySources: [LibrarySource]
    @Query(sort: \Anime.shownTitle) private var anime: [Anime]

    @State private var isFilteringReview = false
    @State private var isBannerDismissed = false

    private let navigation = LibraryNavigation.shared

    private var reviewCount: Int {
        anime.count { $0.metadataState.needsAttention }
    }

    private var visible: [Anime] {
        let present = anime.filter { $0.missingSince == nil }
        return isFilteringReview ? present.filter { $0.metadataState.needsAttention } : present
    }

    var body: some View {
        Group {
            if librarySources.isEmpty {
                NoLibrarySourceView()
            } else {
                library
            }
        }
        .onChange(of: navigation.wantsReviewFilter) { _, wants in
            guard wants else { return }
            isFilteringReview = true
            isBannerDismissed = false
            navigation.wantsReviewFilter = false
        }
    }

    private var library: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if reviewCount > 0 && !isBannerDismissed {
                    ReviewNeededBanner(count: reviewCount, isFiltering: $isFilteringReview) {
                        isBannerDismissed = true
                        isFilteringReview = false
                    }
                }

                if visible.isEmpty {
                    ContentUnavailableView(
                        "Nothing to show",
                        systemImage: "film.stack",
                        description: Text("No shows match the current filter.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 44) {
                        ForEach(visible) { show in
                            AnimeCard(anime: show)
                        }
                    }
                }
            }
            .padding(60)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: AnimeCard.posterWidth), spacing: 36, alignment: .top)]
    }
}

#Preview {
    LibraryForm()
        .modelContainer(ChocoPanModelContainer.preview)
}
