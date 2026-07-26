import SwiftUI

struct HJHarborView: View {
    @EnvironmentObject var store: HJStore

    var body: some View {
        ZStack {
            HJTheme.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Harbor Jam")
                                .font(HJTheme.display(30))
                                .foregroundColor(HJTheme.navy)
                            Text("Clear every berth, one tap at a time")
                                .font(HJTheme.body(13))
                                .foregroundColor(HJTheme.inkSoft)
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            HJStarIcon(size: 20, filled: true)
                            Text("\(store.totalStars())")
                                .font(HJTheme.mono(15))
                                .foregroundColor(HJTheme.navy)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(HJTheme.cardBG))
                    }
                    .padding(.top, 8)

                    ForEach(HJCatalog.chapters, id: \.index) { chapter in
                        chapterCard(chapter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
    }

    @ViewBuilder
    private func chapterCard(_ chapter: HJChapterDef) -> some View {
        let unlocked = store.isChapterUnlocked(chapter.index)
        let stars = HJAchievements.chapterStars(store.save, chapter: chapter.index)
        if unlocked {
            NavigationLink(destination: HJLevelGridView(chapter: chapter)) {
                chapterCardBody(chapter, stars: stars, unlocked: true)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            chapterCardBody(chapter, stars: stars, unlocked: false)
        }
    }

    private func chapterCardBody(_ chapter: HJChapterDef, stars: Int, unlocked: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(unlocked ? HJTheme.navy : HJTheme.navy.opacity(0.25))
                    .frame(width: 52, height: 52)
                if unlocked {
                    HJWaveShape()
                        .stroke(HJTheme.seafoam, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .frame(width: 30, height: 20)
                } else {
                    HJLockShape()
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 22, height: 22)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.name)
                    .font(HJTheme.display(17))
                    .foregroundColor(HJTheme.navy)
                Text(unlocked ? chapter.tagline : "Unlocks at \(chapter.starsToUnlock) stars")
                    .font(HJTheme.body(12))
                    .foregroundColor(HJTheme.inkSoft)
                // star progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HJTheme.navy.opacity(0.12))
                        Capsule().fill(HJTheme.sunGold)
                            .frame(width: geo.size.width * CGFloat(stars) / 60.0)
                    }
                }
                .frame(height: 6)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(stars)/60")
                    .font(HJTheme.mono(13))
                    .foregroundColor(HJTheme.navy)
                HJStarIcon(size: 13, filled: stars > 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(HJTheme.cardBG))
        .opacity(unlocked ? 1 : 0.75)
    }
}

struct HJLevelGridView: View {
    @EnvironmentObject var store: HJStore
    var chapter: HJChapterDef

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    var body: some View {
        ZStack {
            HJTheme.cream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Text(chapter.name)
                        .font(HJTheme.display(24))
                        .foregroundColor(HJTheme.navy)
                        .padding(.top, 8)
                    Text(chapter.tagline)
                        .font(HJTheme.body(13))
                        .foregroundColor(HJTheme.inkSoft)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(0..<HJCatalog.levelsPerChapter, id: \.self) { level in
                            levelCell(level)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 110)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func levelCell(_ level: Int) -> some View {
        let unlocked = store.isLevelUnlocked(chapter: chapter.index, level: level)
        let record = store.record(for: chapter.index, level: level)
        if unlocked {
            NavigationLink(destination: gameDestination(level)) {
                levelCellBody(level, record: record, unlocked: true)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            levelCellBody(level, record: record, unlocked: false)
        }
    }

    @ViewBuilder
    private func gameDestination(_ level: Int) -> some View {
        // No onNext: there is no in-place "next level" navigation, so a "Continue"
        // button would only duplicate "Back" while implying it advances a level.
        if let game = HJGameView(mode: .campaign(chapter: chapter.index, level: level),
                                 store: store,
                                 title: "\(chapter.name) · \(level + 1)") {
            game.environmentObject(store)
        } else {
            Text("Level unavailable")
                .font(HJTheme.body(15))
                .foregroundColor(HJTheme.inkSoft)
        }
    }

    private func levelCellBody(_ level: Int, record: HJLevelRecord?, unlocked: Bool) -> some View {
        VStack(spacing: 5) {
            if unlocked {
                Text("\(level + 1)")
                    .font(HJTheme.mono(18))
                    .foregroundColor(HJTheme.navy)
                HJStarsRow(stars: record?.stars ?? 0, size: 9)
            } else {
                HJLockShape()
                    .stroke(HJTheme.navy.opacity(0.4), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 64, height: 58)
        .background(RoundedRectangle(cornerRadius: 12).fill(unlocked ? HJTheme.cardBG : HJTheme.navy.opacity(0.06)))
    }
}
