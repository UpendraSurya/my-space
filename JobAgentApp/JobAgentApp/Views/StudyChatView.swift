import SwiftUI

// MARK: - Study Chat View

struct StudyChatView: View {
    let initialNote: String?

    @StateObject private var vm = StudyChatViewModel()
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────── //
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask AI")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    if let note = initialNote {
                        Text("Context: \(note)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    } else {
                        Text("Searching across all your notes")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer()
                Button { vm.clear() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Theme.card)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .bottom)

            // ── Messages ──────────────────────────────────────────────── //
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {

                        if vm.messages.isEmpty {
                            chatEmptyState
                                .padding(.top, 40)
                        }

                        ForEach(vm.messages) { msg in
                            ChatBubble(message: msg)
                                .id(msg.id)
                        }

                        if vm.isThinking {
                            ThinkingBubble()
                                .id("thinking")
                        }
                    }
                    .padding(20)
                }
                .onChange(of: vm.messages.count) { _ in
                    withAnimation {
                        if let lastId = vm.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: vm.isThinking) { _ in
                    withAnimation {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }

            // ── Sources row ───────────────────────────────────────────── //
            if !vm.lastSources.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkMuted)
                    Text("Sources:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.inkMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(vm.lastSources, id: \.self) { src in
                                Text(src)
                                    .font(.system(size: 9, design: .monospaced))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accentSoft)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
            }

            // ── Input bar ─────────────────────────────────────────────── //
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your notes…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
                        }
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(inputText.isEmpty || vm.isThinking ? Theme.inkMuted : Theme.ink)
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isThinking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.card)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
        }
        .background(Theme.bg)
        .onAppear {
            inputFocused = true
            if let note = initialNote, !note.isEmpty {
                vm.primeContext(note: note)
            }
        }
    }

    // MARK: - Actions

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !vm.isThinking else { return }
        inputText = ""
        Task { await vm.send(text) }
    }

    // MARK: - Empty state

    var chatEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Theme.inkMuted)
            Text("Ask anything about your notes")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestionPrompts, id: \.self) { prompt in
                    Button {
                        inputText = prompt
                        sendMessage()
                    } label: {
                        HStack {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                            Text(prompt)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
    }

    var suggestionPrompts: [String] {
        if let note = initialNote {
            return [
                "Explain \(note) to me like I'm a beginner",
                "What are the key concepts in \(note)?",
                "Give me a quiz about \(note)",
            ]
        }
        return [
            "What did I learn about Python recently?",
            "Summarise my notes on SwiftUI",
            "What errors have I fixed and how?",
            "What projects am I currently working on?",
        ]
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: StudyChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isUser {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 28, height: 28)
                    Text("AI")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.card)
                }
                .padding(.top, 2)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if let attributed = try? AttributedString(markdown: message.content) {
                    Text(attributed)
                        .font(.system(size: 13))
                        .foregroundStyle(isUser ? Theme.card : Theme.ink)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(isUser ? Theme.ink : Theme.card)
                        .clipShape(
                            RoundedRectangle(cornerRadius: isUser ? 14 : 14)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isUser ? Color.clear : Theme.border, lineWidth: 1)
                        )
                } else {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(isUser ? Theme.card : Theme.ink)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(isUser ? Theme.ink : Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isUser ? Color.clear : Theme.border, lineWidth: 1)
                        )
                }
            }
            .frame(maxWidth: 480, alignment: isUser ? .trailing : .leading)

            if isUser {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("U")
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(Theme.inkSecondary)
                    )
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// MARK: - Thinking Indicator

struct ThinkingBubble: View {
    @State private var dotPhase = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Theme.ink).frame(width: 28, height: 28)
                Text("AI")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.card)
            }
            .padding(.top, 2)

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Theme.inkSecondary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotPhase == i ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
                            value: dotPhase
                        )
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        }
        .onAppear { dotPhase = 1 }
    }
}

// MARK: - ViewModel

@MainActor
class StudyChatViewModel: ObservableObject {
    @Published var messages: [StudyChatMessage] = []
    @Published var isThinking = false
    @Published var lastSources: [String] = []

    func primeContext(note: String) {
        // No-op: the context note title is sent implicitly via first message
    }

    func send(_ text: String) async {
        messages.append(StudyChatMessage(role: "user", content: text))
        isThinking = true
        lastSources = []

        do {
            let resp = try await StudyAPIClient.shared.chat(query: text, history: messages.dropLast())
            messages.append(StudyChatMessage(role: "assistant", content: resp.answer))
            lastSources = resp.sources
        } catch {
            messages.append(StudyChatMessage(
                role: "assistant",
                content: "**Error:** Could not reach the backend. Make sure the Python server is running (`python3 main.py`)."
            ))
        }
        isThinking = false
    }

    func clear() {
        messages = []
        lastSources = []
    }
}
