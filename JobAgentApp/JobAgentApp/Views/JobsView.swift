import SwiftUI

struct JobsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedJobId: Int?

    private var filteredJobs: [JobSummary] {
        searchText.isEmpty ? appState.jobs :
        appState.jobs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.company.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // ── Left: list ───────────────────────────────────────────
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.inkMuted)
                        .font(.system(size: 13))
                    TextField("Search jobs…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                }
                .padding(10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(["all","new","analyzed","ready","applied","rejected"], id: \.self) { s in
                            FilterChip(label: s, isSelected: appState.statusFilter == s) {
                                Task { await appState.applyStatusFilter(s) }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)

                Divider().background(Theme.border)

                if appState.isLoadingJobs {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredJobs.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "briefcase")
                            .font(.system(size: 28))
                            .foregroundStyle(Theme.inkMuted)
                        Text("No jobs found")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                        Text("Run the pipeline to search for jobs.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredJobs, id: \.id, selection: $selectedJobId) { job in
                        JobRowView(job: job).tag(job.id)
                            .listRowBackground(selectedJobId == job.id ? Theme.accentSoft : Theme.card)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bg)
                }
            }
            .background(Theme.bg)
            .frame(minWidth: 280, maxWidth: 360)

            // ── Right: detail ────────────────────────────────────────
            Group {
                if let jobId = selectedJobId {
                    JobDetailView(jobId: jobId)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.inkMuted)
                        Text("Select a job to view details")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
                }
            }
        }
        .task { await appState.refreshJobs() }
    }
}

// MARK: - Job Row

struct JobRowView: View {
    let job: JobSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(job.company)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(job.matchPercent)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(matchColor(job.matchScore))
                    if let ats = job.atsScore {
                        Text("\(Int(ats))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            HStack(spacing: 6) {
                JobStatusBadge(status: job.status)
                if let src = job.source {
                    Text(src)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.surfaceHover)
                        .clipShape(Capsule())
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func matchColor(_ s: Float) -> Color {
        s >= 0.75 ? Theme.green : s >= 0.5 ? Theme.accent : Theme.inkMuted
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isSelected ? Theme.ink : Theme.surface)
                .foregroundStyle(isSelected ? Theme.card : Theme.inkSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Job Detail

struct JobDetailView: View {
    @EnvironmentObject var appState: AppState
    let jobId: Int

    @State private var job: JobDetail?
    @State private var application: ApplicationInfo?
    @State private var atsScore: ATSScoreDetail?
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
            } else if let job {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // Header card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(job.title)
                                        .font(.system(size: 20, weight: .bold, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                    HStack(spacing: 6) {
                                        Text(job.company)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Theme.inkSecondary)
                                        if let loc = job.location {
                                            Text("·").foregroundStyle(Theme.border)
                                            Label(loc, systemImage: "location")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Theme.inkMuted)
                                        }
                                    }
                                }
                                Spacer()
                                if let ats = atsScore {
                                    ATSRing(score: ats.totalScore, size: 68)
                                }
                            }
                            HStack(spacing: 8) {
                                JobStatusBadge(status: job.status)
                                Text("\(Int(job.matchScore * 100))% match")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Theme.green.opacity(0.1))
                                    .foregroundStyle(Theme.green)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(18)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))

                        // Actions
                        HStack(spacing: 8) {
                            ActionButton(icon: "safari", label: "Open URL", color: Theme.accent) {
                                if let url = URL(string: job.url) { NSWorkspace.shared.open(url) }
                            }
                            if let app = application {
                                if let pdf = app.cvPath, !pdf.isEmpty {
                                    ActionButton(icon: "doc.fill", label: "View CV", color: Theme.purple) {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: pdf))
                                    }
                                } else if let tex = app.texPath {
                                    ActionButton(icon: "doc.text", label: "View .tex", color: Theme.inkSecondary) {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: tex))
                                    }
                                }
                            }
                            ActionButton(icon: "checkmark.circle.fill", label: "Applied", color: Theme.green) {
                                Task { await appState.setJobStatus(jobId, status: "applied"); await reload() }
                            }
                            ActionButton(icon: "xmark.circle", label: "Skip", color: Theme.inkMuted) {
                                Task { await appState.setJobStatus(jobId, status: "skipped") }
                            }
                        }

                        // Tab strip + content
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(Array(["Description", "Analysis", "ATS Score"].enumerated()), id: \.offset) { i, label in
                                    Button { selectedTab = i } label: {
                                        Text(label)
                                            .font(.system(size: 12, weight: selectedTab == i ? .semibold : .regular))
                                            .padding(.horizontal, 16).padding(.vertical, 9)
                                            .background(selectedTab == i ? Theme.accentSoft : Color.clear)
                                            .foregroundStyle(selectedTab == i ? Theme.ink : Theme.inkSecondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer()
                            }
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Divider().background(Theme.border)

                            Group {
                                switch selectedTab {
                                case 0: DescriptionTab(description: job.rawDescription ?? "No description.")
                                case 1: AnalysisTab(analysis: job.analysis)
                                case 2: ATSDetailTab(score: atsScore)
                                default: EmptyView()
                                }
                            }
                            .padding(16)
                        }
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
                    }
                    .padding(20)
                }
                .background(Theme.bg)
            }
        }
        .task { await reload() }
        .id(jobId)
    }

    func reload() async {
        isLoading = true
        async let jd  = try? APIClient.shared.jobDetail(jobId)
        async let app = try? APIClient.shared.application(for: jobId)
        async let ats = try? APIClient.shared.atsScore(for: jobId)
        job = await jd
        application = await app
        atsScore = await ats
        isLoading = false
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab Content

struct DescriptionTab: View {
    let description: String
    var body: some View {
        ScrollView {
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 380)
    }
}

struct AnalysisTab: View {
    let analysis: JobAnalysis?
    var body: some View {
        if let a = analysis {
            VStack(alignment: .leading, spacing: 14) {
                if let s = a.summary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUMMARY").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkMuted)
                        Text(s).font(.system(size: 13)).foregroundStyle(Theme.ink).textSelection(.enabled)
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    if let skills = a.requiredSkills, !skills.isEmpty { SkillChips(title: "REQUIRED", skills: skills, color: Theme.accent) }
                    if let tech = a.techStack, !tech.isEmpty { SkillChips(title: "TECH STACK", skills: tech, color: Theme.teal) }
                }
                if let resp = a.keyResponsibilities, !resp.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RESPONSIBILITIES").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkMuted)
                        ForEach(resp.prefix(5), id: \.self) { r in
                            HStack(alignment: .top, spacing: 6) {
                                Rectangle().fill(Theme.accent).frame(width: 3, height: 3).padding(.top, 6)
                                Text(r).font(.system(size: 12)).foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
                HStack(spacing: 20) {
                    if let s = a.seniorityLevel { LabeledValue(label: "Level", value: s.capitalized) }
                    if let y = a.experienceYearsRequired { LabeledValue(label: "Experience", value: "\(y) yrs") }
                    if let r = a.isRemote { LabeledValue(label: "Remote", value: r ? "Yes" : "No") }
                }
            }
        } else {
            Text("Not yet analyzed. Run the pipeline.")
                .font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
        }
    }
}

struct ATSDetailTab: View {
    let score: ATSScoreDetail?
    var body: some View {
        if let s = score {
            VStack(alignment: .leading, spacing: 14) {
                Text("Total Score: \(String(format: "%.1f", s.totalScore))/100")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                ScoreBar(label: "Keyword Match (40%)",  score: s.keywordScore,    maxScore: 25, color: Theme.accent)
                ScoreBar(label: "Formatting (30%)",     score: s.formattingScore, maxScore: 25, color: Theme.green)
                ScoreBar(label: "Relevance (20%)",      score: s.relevanceScore,  maxScore: 25, color: Theme.purple)
                ScoreBar(label: "Completeness (10%)",   score: s.completenessScore, maxScore: 25, color: Theme.teal)
            }
        } else {
            Text("No ATS score yet. Run the pipeline to generate a tailored CV.")
                .font(.system(size: 13)).foregroundStyle(Theme.inkSecondary)
        }
    }
}

// MARK: - Helpers

struct SkillChips: View {
    let title: String; let skills: [String]; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Theme.inkMuted)
            FlowLayout(spacing: 4) {
                ForEach(skills.prefix(10), id: \.self) { s in
                    Text(s).font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(color.opacity(0.1)).foregroundStyle(color)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct LabeledValue: View {
    let label: String; let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.inkMuted)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
        }
    }
}
