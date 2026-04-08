import SwiftUI

struct TrackerView: View {
    @EnvironmentObject var appState: AppState

    private let columns    = ["applied", "interviewing", "offer", "rejected"]
    private let labels     = ["Applied", "Interviewing", "Offer 🎉", "Rejected"]
    private let colors: [Color] = [Theme.teal, Theme.purple, Theme.green, Theme.red]

    private func jobs(for status: String) -> [JobSummary] {
        appState.jobs.filter { $0.status == status }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tracker")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 24).padding(.top, 24)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(zip(columns, labels).enumerated()), id: \.offset) { i, pair in
                        KanbanColumn(title: pair.1, color: colors[i], jobs: jobs(for: pair.0))
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.bg)
        .task { await appState.refreshJobs() }
    }
}

struct KanbanColumn: View {
    let title: String
    let color: Color
    let jobs: [JobSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(jobs.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14).padding(.top, 14)

            if jobs.isEmpty {
                Text("Nothing here yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .padding(.horizontal, 14)
            } else {
                ForEach(jobs) { job in
                    KanbanCard(job: job, color: color)
                }
            }

            Spacer(minLength: 14)
        }
        .frame(width: 230)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }
}

struct KanbanCard: View {
    let job: JobSummary
    let color: Color
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(job.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(job.company)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
            HStack {
                if let ats = job.atsScore {
                    Text("ATS \(Int(ats))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button {
                    if let url = URL(string: job.url) { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 10)
    }
}
