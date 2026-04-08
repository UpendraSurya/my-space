import SwiftUI

// MARK: - Home Screen (entry point)
struct HomeView: View {
    @State private var selectedProfile: AppProfile? = nil
    @State private var animateInitials = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {

                    // ── "US" initials header ──────────────────────────────
                    VStack(spacing: 6) {
                        HStack(alignment: .bottom, spacing: 2) {
                            Text("U")
                                .font(.system(size: 96, weight: .black, design: .serif))
                                .italic()
                                .foregroundStyle(Theme.ink)
                                .offset(y: animateInitials ? 0 : -20)
                                .opacity(animateInitials ? 1 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: animateInitials)

                            Text("S")
                                .font(.system(size: 96, weight: .black, design: .serif))
                                .italic()
                                .foregroundStyle(Theme.ink)
                                .offset(y: animateInitials ? 0 : -20)
                                .opacity(animateInitials ? 1 : 0)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.22), value: animateInitials)
                        }

                        Text("Upendra Surya")
                            .font(.system(size: 15, weight: .medium, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.inkSecondary)
                            .opacity(animateInitials ? 1 : 0)
                            .animation(.easeIn(duration: 0.4).delay(0.5), value: animateInitials)

                        Rectangle()
                            .fill(Theme.inkSecondary.opacity(0.25))
                            .frame(height: 1)
                            .padding(.horizontal, 48)
                            .padding(.top, 16)
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 32)

                    // ── Subtitle ──────────────────────────────────────────
                    Text("YOUR PERSONAL HUB")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Theme.inkSecondary)
                        .opacity(animateInitials ? 1 : 0)
                        .animation(.easeIn(duration: 0.4).delay(0.6), value: animateInitials)
                        .padding(.bottom, 32)

                    // ── Profile cards grid ────────────────────────────────
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 20),
                                      GridItem(.flexible(), spacing: 20)],
                            spacing: 20
                        ) {
                            ForEach(AppProfile.allProfiles) { profile in
                                NavigationLink(value: profile) {
                                    ProfileCard(profile: profile)
                                }
                                .buttonStyle(.plain)
                            }

                            // "Add new" placeholder card
                            AddNewCard()
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                    }
                }
            }
            .onAppear { animateInitials = true }
            .navigationDestination(for: AppProfile.self) { profile in
                profile.destination
            }
        }
    }
}

// MARK: - Profile card

struct ProfileCard: View {
    let profile: AppProfile
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Pixel art area
            ZStack {
                Rectangle()
                    .fill(profile.cardColor)
                    .frame(height: 160)

                PixelArtView(pixels: profile.pixelArt,
                             pixelColor: Theme.ink,
                             accentColor: profile.accentColor)
                    .frame(width: 80, height: 80)
            }

            // Label area
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(profile.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(hovered ? Theme.ink.opacity(0.5) : Theme.border, lineWidth: hovered ? 2 : 1)
        )
        .shadow(color: Theme.ink.opacity(hovered ? 0.12 : 0.05), radius: hovered ? 16 : 6, y: hovered ? 6 : 2)
        .scaleEffect(hovered ? 1.025 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
    }
}

// MARK: - Add new card

struct AddNewCard: View {
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .foregroundStyle(Theme.inkSecondary.opacity(0.4))

                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.inkSecondary.opacity(hovered ? 0.9 : 0.5))

                    Text("Add Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.inkSecondary.opacity(hovered ? 0.9 : 0.5))
                }
            }
            .frame(height: 220)
        }
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: hovered)
        .onHover { hovered = $0 }
    }
}

// MARK: - Profile model

struct AppProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let cardColor: Color
    let accentColor: Color
    let pixelArt: [[Int]]   // 0=transparent, 1=dark, 2=accent

    static func == (lhs: AppProfile, rhs: AppProfile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    @ViewBuilder
    var destination: some View {
        switch id {
        case "jobs":
            ContentView()
        case "study":
            StudyHubView()
        default:
            ComingSoonView(profile: self)
        }
    }

    // ── Pixel art patterns (0=empty, 1=dark, 2=accent) ──────────────

    static let briefcaseArt: [[Int]] = [
        [0,0,1,1,1,1,1,1,0,0],
        [0,0,1,0,0,0,0,1,0,0],
        [1,1,1,1,1,1,1,1,1,1],
        [1,0,0,0,0,0,0,0,0,1],
        [1,0,0,1,1,1,1,0,0,1],
        [1,0,0,1,2,2,1,0,0,1],
        [1,0,0,1,1,1,1,0,0,1],
        [1,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,1],
        [1,1,1,1,1,1,1,1,1,1],
    ]

    static let chartArt: [[Int]] = [
        [0,0,0,0,0,0,1,0,0,0],
        [0,0,0,0,0,0,1,0,0,0],
        [0,0,0,0,1,0,1,0,0,0],
        [0,0,0,0,1,0,1,0,2,0],
        [0,1,0,0,1,0,1,0,2,0],
        [0,1,0,1,1,0,1,0,2,0],
        [0,1,1,1,1,1,1,1,2,0],
        [1,1,1,1,1,1,1,1,1,1],
        [0,0,0,0,0,0,0,0,0,0],
        [1,1,1,1,1,1,1,1,1,1],
    ]

    static let bookArt: [[Int]] = [
        [0,1,1,1,1,1,0,0,1,1],
        [1,1,2,2,2,1,0,1,1,2],
        [1,0,2,0,0,1,0,1,0,2],
        [1,0,2,0,0,1,0,1,0,2],
        [1,0,2,0,0,1,0,1,0,2],
        [1,0,2,0,0,1,0,1,0,2],
        [1,1,2,2,2,1,0,1,1,2],
        [0,1,1,1,1,1,0,0,1,1],
        [0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0],
    ]

    static let clockArt: [[Int]] = [
        [0,0,1,1,1,1,1,1,0,0],
        [0,1,0,0,0,0,0,0,1,0],
        [1,0,0,0,0,1,0,0,0,1],
        [1,0,0,0,0,1,0,0,0,1],
        [1,0,0,0,0,1,0,0,0,1],
        [1,0,2,2,2,1,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,1],
        [1,0,0,0,0,0,0,0,0,1],
        [0,1,0,0,0,0,0,0,1,0],
        [0,0,1,1,1,1,1,1,0,0],
    ]

    // ── All profiles ─────────────────────────────────────────────────

    static let allProfiles: [AppProfile] = [
        AppProfile(
            id: "jobs",
            name: "Job Applications",
            description: "Autonomous CV tailoring\n& job search pipeline",
            cardColor: Color(hex: "#2A2A2A"),
            accentColor: Color(hex: "#C8963E"),
            pixelArt: briefcaseArt
        ),
        AppProfile(
            id: "finance",
            name: "Finance Tracker",
            description: "Budgets, expenses\n& savings goals",
            cardColor: Color(hex: "#1C2A1C"),
            accentColor: Color(hex: "#6DBF67"),
            pixelArt: chartArt
        ),
        AppProfile(
            id: "study",
            name: "Study Hub",
            description: "Notes, flashcards\n& learning tracker",
            cardColor: Color(hex: "#1A1A2E"),
            accentColor: Color(hex: "#7B9FD4"),
            pixelArt: bookArt
        ),
        AppProfile(
            id: "habits",
            name: "Habit Tracker",
            description: "Daily routines\n& progress streaks",
            cardColor: Color(hex: "#2A1A10"),
            accentColor: Color(hex: "#E8925A"),
            pixelArt: clockArt
        ),
    ]
}

// MARK: - Coming soon placeholder

struct ComingSoonView: View {
    let profile: AppProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                PixelArtView(pixels: profile.pixelArt,
                             pixelColor: Theme.ink,
                             accentColor: profile.accentColor)
                    .frame(width: 100, height: 100)

                Text(profile.name)
                    .font(.system(size: 28, weight: .black, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.ink)

                Text("Coming soon")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Theme.inkSecondary)

                Button("← Back") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
