import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // MARK: - Published state
    @Published var stats: AppStats?
    @Published var jobs: [JobSummary] = []
    @Published var selectedJobId: Int?
    @Published var selectedTab: SidebarTab = .dashboard
    @Published var isBackendOnline: Bool = false
    @Published var isLoadingJobs: Bool = false
    @Published var isPipelineRunning: Bool = false
    @Published var pipelineLog: [PipelineLogEntry] = []
    @Published var errorMessage: String?
    @Published var statusFilter: String = "all"
    @Published var profile: UserProfile?

    private var pollingTask: Task<Void, Never>?

    init() {
        Task { await startUp() }
    }

    // MARK: - Startup

    private func startUp() async {
        isBackendOnline = await APIClient.shared.health()
        if isBackendOnline {
            await refreshAll()
            startPolling()
        } else {
            errorMessage = "Backend offline. Run: python3 api/server.py"
            // Poll for backend coming online
            Task {
                while !isBackendOnline {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    isBackendOnline = await APIClient.shared.health()
                }
                await refreshAll()
                startPolling()
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                await refreshStats()
                await refreshPipelineStatus()
            }
        }
    }

    // MARK: - Data refresh

    func refreshAll() async {
        await refreshStats()
        await refreshJobs()
        await refreshProfile()
        await refreshPipelineStatus()
    }

    func refreshStats() async {
        guard isBackendOnline else { return }
        do {
            stats = try await APIClient.shared.stats()
        } catch {
            // silently ignore stats errors
        }
    }

    func refreshJobs() async {
        guard isBackendOnline else { return }
        isLoadingJobs = true
        defer { isLoadingJobs = false }
        do {
            jobs = try await APIClient.shared.jobs(status: statusFilter == "all" ? nil : statusFilter)
            errorMessage = nil
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshProfile() async {
        guard isBackendOnline else { return }
        profile = try? await APIClient.shared.profile()
    }

    func refreshPipelineStatus() async {
        guard isBackendOnline else { return }
        if let log = try? await APIClient.shared.pipelineStatus() {
            isPipelineRunning = log.running
            pipelineLog = log.log
        }
    }

    // MARK: - Actions

    func runPipeline() async {
        guard isBackendOnline, !isPipelineRunning else { return }
        do {
            try await APIClient.shared.runPipeline()
            isPipelineRunning = true
            errorMessage = nil
            // Poll faster while running
            Task {
                for _ in 0..<60 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await refreshPipelineStatus()
                    await refreshStats()
                    if !isPipelineRunning { break }
                }
                await refreshJobs()
            }
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setJobStatus(_ jobId: Int, status: String) async {
        do {
            try await APIClient.shared.updateStatus(jobId: jobId, status: status)
            // Update local state immediately
            if let idx = jobs.firstIndex(where: { $0.id == jobId }) {
                // Re-fetch just that job's status by refreshing
                await refreshJobs()
                await refreshStats()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyStatusFilter(_ status: String) async {
        statusFilter = status
        await refreshJobs()
    }

    func saveProfile(_ updated: UserProfile) async {
        do {
            try await APIClient.shared.updateProfile(updated)
            profile = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
