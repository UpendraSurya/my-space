import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                if let err = appState.errorMessage {
                    ErrorBanner(message: err) { appState.errorMessage = nil }
                }

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dashboard")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(Date().formatted(date: .long, time: .omitted))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    Button {
                        Task { await appState.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))
                }

                // Stats grid
                if let s = appState.stats {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        StatCard(title: "Total Jobs",     value: "\(s.totalJobs)",    icon: "briefcase.fill",      color: Theme.accent)
                        StatCard(title: "Ready to Apply", value: "\(s.readyJobs)",    icon: "checkmark.circle",    color: Theme.green)
                        StatCard(title: "Avg ATS Score",  value: "\(Int(s.avgAtsScore))", icon: "speedometer",    color: atsColor(s.avgAtsScore))
                        StatCard(title: "CVs Generated",  value: "\(s.cvsGenerated)", icon: "doc.text.fill",      color: Theme.purple)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        StatCard(title: "New",      value: "\(s.newJobs)",      icon: "sparkles",        color: Theme.accent)
                        StatCard(title: "Analyzed", value: "\(s.analyzedJobs)", icon: "magnifyingglass", color: Theme.teal)
                        StatCard(title: "Applied",  value: "\(s.appliedJobs)",  icon: "paperplane",      color: Theme.purple)
                    }
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                // Pipeline log
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Pipeline Log") {
                        Task { await appState.refreshPipelineStatus() }
                    }
                    PipelineLogView()
                }
                .padding(16)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
            }
            .padding(24)
        }
        .background(Theme.bg)
    }

    private func atsColor(_ score: Float) -> Color {
        if score >= 75 { return Theme.green }
        if score >= 55 { return Theme.accent }
        return Theme.red
    }
}

struct PipelineLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.pipelineLog.isEmpty {
            Text("No pipeline runs yet. Press Run Pipeline to start.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
                .frame(maxWidth: .infinity, minHeight: 50)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(appState.pipelineLog.reversed()) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(entry.timestamp.suffix(8)))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.inkMuted)
                                .frame(width: 70, alignment: .leading)

                            Text("[\(entry.stage)]")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(stageColor(entry.stage))
                                .frame(width: 90, alignment: .leading)

                            Text(entry.message)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
    }

    private func stageColor(_ stage: String) -> Color {
        switch stage {
        case "job_finder":    return Theme.accent
        case "job_analyzer":  return Theme.teal
        case "cv_tailor":     return Color(hex: "#7A5A20")
        case "ats_optimizer": return Theme.purple
        default:              return Theme.green
        }
    }
}
