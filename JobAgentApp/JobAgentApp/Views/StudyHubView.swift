import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Study Hub

struct StudyHubView: View {
    @StateObject private var vm = StudyHubViewModel()
    @State private var showChat = false
    @State private var showUpload = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // ── Sidebar: note list + search ──────────────────────────────
            VStack(spacing: 0) {
                studySidebar
            }
            .background(Theme.bg)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 300)
        } detail: {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if let note = vm.selectedNote {
                    NoteDetailView(note: note, onChat: { showChat = true })
                } else {
                    studyEmptyState
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        Task { await vm.reindex() }
                    } label: {
                        Label("Reindex", systemImage: "arrow.clockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Re-scan and re-index all dev notes")

                    Button {
                        showUpload = true
                    } label: {
                        Label("Upload File", systemImage: "paperclip")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Upload a file to extract as a dev note")

                    Button {
                        showChat = true
                    } label: {
                        Label("Ask AI", systemImage: "bubble.left.and.bubble.right")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Chat with AI about your notes")
                }
            }
        }
        .background(Theme.bg)
        .sheet(isPresented: $showChat) {
            StudyChatView(initialNote: vm.selectedNote?.title)
                .frame(minWidth: 600, minHeight: 500)
        }
        .sheet(isPresented: $showUpload) {
            UploadFileSheet { title, topic, url in
                await vm.uploadFile(url: url, title: title, topic: topic)
                showUpload = false
            }
            .frame(minWidth: 460, minHeight: 320)
        }
        .task { await vm.loadNotes() }
    }

    // MARK: - Sidebar

    var studySidebar: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Study Hub")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("\(vm.displayedNotes.count) notes")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(Theme.border)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkMuted)
                TextField("Search notes…", text: $vm.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .onChange(of: vm.searchQuery) {
                        Task { await vm.search() }
                    }
                if !vm.searchQuery.isEmpty {
                    Button { vm.searchQuery = ""; vm.searchResults = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Topic filter chips
            if !vm.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        TopicChip(label: "All", selected: vm.selectedTopic == nil) {
                            vm.selectedTopic = nil
                        }
                        ForEach(vm.topics, id: \.self) { topic in
                            TopicChip(label: topic, selected: vm.selectedTopic == topic) {
                                vm.selectedTopic = vm.selectedTopic == topic ? nil : topic
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 6)
            }

            Divider().background(Theme.border)

            // Notes list
            if vm.isLoading {
                Spacer()
                ProgressView().tint(Theme.accent)
                Spacer()
            } else if vm.displayedNotes.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: vm.searchQuery.isEmpty ? "doc.text" : "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.inkMuted)
                    Text(vm.searchQuery.isEmpty ? "No notes found" : "No results")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.displayedNotes) { note in
                            NoteRow(note: note, isSelected: vm.selectedNote?.noteId == note.noteId)
                                .onTapGesture {
                                    Task { await vm.selectNote(note) }
                                }
                            Divider().background(Theme.border).padding(.leading, 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    var studyEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Theme.inkMuted)
            Text("Select a note to read")
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
            Text("Or search to find something specific")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkMuted)
            HStack(spacing: 12) {
                Button("Ask AI") { showChat = true }
                    .buttonStyle(StudyButtonStyle(accent: true))
                Button("Upload File") { showUpload = true }
                    .buttonStyle(StudyButtonStyle())
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: StudyNote
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(note.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if !note.topic.isEmpty {
                    Text(note.topic)
                        .font(.system(size: 9, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.accentSoft)
                        .foregroundStyle(Theme.inkSecondary)
                        .clipShape(Capsule())
                }
                Spacer()
                if !note.date.isEmpty {
                    Text(note.date.prefix(10))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.accentSoft : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Note Detail

struct NoteDetailView: View {
    let note: StudyNoteContent
    let onChat: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Note header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.system(size: 24, weight: .bold, design: .serif))
                                .foregroundStyle(Theme.ink)
                            HStack(spacing: 8) {
                                if !note.topic.isEmpty {
                                    Label(note.topic, systemImage: "tag")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                if !note.date.isEmpty {
                                    Label(note.date.prefix(10), systemImage: "calendar")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            onChat()
                        } label: {
                            Label("Ask AI", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.ink)
                        .foregroundStyle(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .buttonStyle(.plain)
                    }

                    if !note.tags.isEmpty {
                        FlowLayout(spacing: 5) {
                            ForEach(note.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Theme.surface)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(20)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))

                // Note content — rendered as markdown
                MarkdownView(text: note.content)
                    .padding(20)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }
            .padding(24)
        }
        .background(Theme.bg)
    }
}

// MARK: - Markdown View (simple)

struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Topic Chip

struct TopicChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(selected ? Theme.ink : Theme.surface)
                .foregroundStyle(selected ? Theme.card : Theme.inkSecondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? Theme.ink : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Upload File Sheet

struct UploadFileSheet: View {
    let onUpload: (String, String, URL) async -> Void

    @State private var title = ""
    @State private var topic = "general"
    @State private var pickedURL: URL? = nil
    @State private var isUploading = false
    @State private var errorMsg: String? = nil
    @Environment(\.dismiss) private var dismiss

    let topics = ["general", "python", "javascript", "frontend", "swift", "ml", "data", "devops"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Upload File as Dev Note")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)

            // File picker
            VStack(alignment: .leading, spacing: 8) {
                Text("FILE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2).foregroundStyle(Theme.inkMuted)

                Button {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.pdf, .text, .plainText,
                                                  UTType(filenameExtension: "md")!,
                                                  UTType(filenameExtension: "docx") ?? .data]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK {
                        pickedURL = panel.url
                        if title.isEmpty {
                            title = panel.url?.deletingPathExtension().lastPathComponent ?? ""
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "paperclip")
                        Text(pickedURL?.lastPathComponent ?? "Choose file…")
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Theme.surface)
                .foregroundStyle(pickedURL == nil ? Theme.inkMuted : Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                .buttonStyle(.plain)
            }

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTE TITLE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2).foregroundStyle(Theme.inkMuted)
                TextField("Note title…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(9)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))
            }

            // Topic
            VStack(alignment: .leading, spacing: 6) {
                Text("TOPIC")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2).foregroundStyle(Theme.inkMuted)
                Picker("", selection: $topic) {
                    ForEach(topics, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let err = errorMsg {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.red)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(StudyButtonStyle())
                Spacer()
                Button {
                    guard let url = pickedURL else { return }
                    isUploading = true
                    errorMsg = nil
                    Task {
                        await onUpload(title, topic, url)
                        isUploading = false
                    }
                } label: {
                    if isUploading {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Extract & Save Note")
                    }
                }
                .disabled(pickedURL == nil || isUploading)
                .buttonStyle(StudyButtonStyle(accent: true))
            }
        }
        .padding(24)
        .background(Theme.bg)
    }
}

// MARK: - Button Style

struct StudyButtonStyle: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(accent ? Theme.ink : Theme.surface)
            .foregroundStyle(accent ? Theme.card : Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent ? Theme.ink : Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - ViewModel

@MainActor
class StudyHubViewModel: ObservableObject {
    @Published var notes: [StudyNote] = []
    @Published var searchResults: [StudySearchResult]? = nil
    @Published var selectedNote: StudyNoteContent? = nil
    @Published var isLoading = false
    @Published var searchQuery = ""
    @Published var selectedTopic: String? = nil

    private var searchTask: Task<Void, Never>? = nil

    var displayedNotes: [StudyNote] {
        var base: [StudyNote]
        if let results = searchResults {
            // Map search results back to StudyNote shape
            base = results.map { r in
                StudyNote(
                    noteId: r.noteId,
                    title: r.title,
                    preview: r.snippet,
                    tags: r.tags,
                    topic: r.topic,
                    date: r.date,
                    path: ""
                )
            }
        } else {
            base = notes
        }
        if let topic = selectedTopic {
            base = base.filter { $0.topic == topic }
        }
        return base
    }

    var topics: [String] {
        let all = notes.compactMap { $0.topic.isEmpty ? nil : $0.topic }
        return Array(Set(all)).sorted()
    }

    func loadNotes() async {
        isLoading = true
        do {
            notes = try await StudyAPIClient.shared.listNotes()
        } catch {
            // Backend might not be running yet
            notes = []
        }
        isLoading = false
    }

    func search() async {
        searchTask?.cancel()
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = nil
            return
        }
        // Debounce
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let resp = try await StudyAPIClient.shared.search(query: searchQuery)
                searchResults = resp.results
            } catch {
                searchResults = nil
            }
        }
    }

    func selectNote(_ note: StudyNote) async {
        do {
            selectedNote = try await StudyAPIClient.shared.getNote(note.noteId)
        } catch {
            // Fallback: build a minimal content view from what we have
            selectedNote = StudyNoteContent(
                noteId: note.noteId,
                title: note.title,
                content: note.preview,
                tags: note.tags,
                topic: note.topic,
                date: note.date,
                path: note.path
            )
        }
    }

    func reindex() async {
        isLoading = true
        do {
            _ = try await StudyAPIClient.shared.reindex()
            await loadNotes()
        } catch {
            isLoading = false
        }
    }

    func uploadFile(url: URL, title: String, topic: String) async {
        do {
            _ = try await StudyAPIClient.shared.uploadFile(fileURL: url, title: title, topic: topic)
            await loadNotes()
        } catch {
            // silently fail for now
        }
    }
}
