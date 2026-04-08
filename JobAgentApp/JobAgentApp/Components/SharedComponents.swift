import SwiftUI

// MARK: - Theme  (beige / black — Claude inspired)

enum Theme {
    // Backgrounds
    static let bg             = Color(hex: "#F5F0E8")   // warm cream page bg
    static let card           = Color(hex: "#FDFAF4")   // near-white card surface
    static let surface        = Color(hex: "#EDE6D6")   // beige panel / sidebar
    static let surfaceHover   = Color(hex: "#E4DCCA")   // slightly darker on hover

    // Ink (text / icons)
    static let ink            = Color(hex: "#1A1705")   // warm near-black
    static let inkSecondary   = Color(hex: "#7A6E58")   // warm mid-brown
    static let inkMuted       = Color(hex: "#B0A48A")   // light tan

    // Accent (Claude's warm orange-amber)
    static let accent         = Color(hex: "#C8963E")   // amber
    static let accentSoft     = Color(hex: "#F0DEB8")   // pale amber tint

    // Semantic
    static let border         = Color(hex: "#D8CEB8")   // tan divider
    static let green          = Color(hex: "#4A7C59")   // muted forest green
    static let red            = Color(hex: "#9B3A2E")   // muted terracotta
    static let purple         = Color(hex: "#5C4A8A")   // muted indigo
    static let teal           = Color(hex: "#3A6B6B")   // muted teal
}

// MARK: - Color hex init
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Back to home
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("US")
                        .font(.system(size: 18, weight: .black, design: .serif))
                        .italic()
                    Spacer()
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider()
                .background(Theme.border)
                .padding(.horizontal, 12)

            // Label
            HStack {
                Text("JOB APPLICATIONS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Nav items
            VStack(spacing: 2) {
                ForEach(SidebarTab.allCases) { tab in
                    SidebarItem(tab: tab, isSelected: appState.selectedTab == tab) {
                        appState.selectedTab = tab
                    }
                }
            }
            .padding(.top, 4)

            Spacer()

            Divider()
                .background(Theme.border)
                .padding(.horizontal, 12)

            // Run pipeline button
            Button {
                Task { await appState.runPipeline() }
            } label: {
                HStack(spacing: 8) {
                    if appState.isPipelineRunning {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(Theme.card)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                    }
                    Text(appState.isPipelineRunning ? "Running…" : "Run Pipeline")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(appState.isPipelineRunning ? Theme.inkMuted : Theme.ink)
                .foregroundStyle(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(appState.isPipelineRunning || !appState.isBackendOnline)
            .padding(14)
        }
        .background(Theme.surface)
    }
}

struct SidebarItem: View {
    let tab: SidebarTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.inkSecondary)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

// MARK: - Backend status badge

struct BackendStatusBadge: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(appState.isBackendOnline ? Theme.green : Theme.red)
                .frame(width: 6, height: 6)
            Text(appState.isBackendOnline ? "Backend Online" : "Backend Offline")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Job status badge

struct JobStatusBadge: View {
    let status: String

    private var statusEnum: JobStatus { JobStatus(rawValue: status) ?? .new }

    private var badgeColor: Color {
        switch statusEnum {
        case .new:          return Theme.inkMuted
        case .analyzed:     return Theme.accent
        case .cv_tailored, .ats_optimized: return Color(hex: "#7A6020")
        case .ready:        return Theme.green
        case .applied:      return Theme.teal
        case .interviewing: return Theme.purple
        case .offer:        return Color(hex: "#3A6B3A")
        case .rejected:     return Theme.red
        case .skipped:      return Theme.inkMuted
        }
    }

    var body: some View {
        Text(statusEnum.displayName)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12))
            .foregroundStyle(badgeColor)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(badgeColor.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - ATS ring

struct ATSRing: View {
    let score: Float
    let size: CGFloat

    private var color: Color {
        if score >= 75 { return Theme.green }
        if score >= 55 { return Theme.accent }
        return Theme.red
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: CGFloat(score / 100))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)
            VStack(spacing: 0) {
                Text("\(Int(score))")
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("ATS")
                    .font(.system(size: size * 0.14))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Score bar

struct ScoreBar: View {
    let label: String
    let score: Float
    let maxScore: Float
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Text("\(String(format: "%.1f", score))/\(String(format: "%.0f", maxScore))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.12))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score / maxScore), height: 5)
                        .animation(.easeInOut(duration: 0.6), value: score)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if let action {
                Button(actionLabel, action: action)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Flow layout (for skill chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth + size.width > containerWidth {
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: containerWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
