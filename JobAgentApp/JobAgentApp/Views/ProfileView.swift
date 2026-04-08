import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @State private var editMode = false
    @State private var draft = ProfileDraft()
    @State private var newSkill = ""
    @State private var saveSuccess = false

    struct ProfileDraft {
        var name = ""; var email = ""; var phone = ""
        var linkedin = ""; var github = ""; var skills: [String] = []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                // Header
                HStack {
                    Text("Profile")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if saveSuccess {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.green)
                            .transition(.opacity)
                    }
                    Button(editMode ? "Save" : "Edit") {
                        if editMode { Task { await saveProfile() } }
                        else { loadDraft(); editMode = true }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(editMode ? Theme.green.opacity(0.12) : Theme.surface)
                    .foregroundStyle(editMode ? Theme.green : Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(editMode ? Theme.green.opacity(0.3) : Theme.border, lineWidth: 1))
                    .buttonStyle(.plain)

                    if editMode {
                        Button("Cancel") { editMode = false }
                            .font(.system(size: 13))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Theme.surface)
                            .foregroundStyle(Theme.inkSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                            .buttonStyle(.plain)
                    }
                }

                // Contact card
                VStack(alignment: .leading, spacing: 14) {
                    Text("CONTACT INFORMATION")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2).foregroundStyle(Theme.inkMuted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ProfileField(label: "Full Name",  icon: "person.fill",  value: $draft.name,     isEditing: editMode)
                        ProfileField(label: "Email",      icon: "envelope",     value: $draft.email,    isEditing: editMode)
                        ProfileField(label: "Phone",      icon: "phone",        value: $draft.phone,    isEditing: editMode)
                        ProfileField(label: "LinkedIn",   icon: "link",         value: $draft.linkedin, isEditing: editMode)
                        ProfileField(label: "GitHub",     icon: "chevron.left.forwardslash.chevron.right", value: $draft.github, isEditing: editMode)
                    }
                }
                .padding(18)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))

                // Skills
                VStack(alignment: .leading, spacing: 12) {
                    Text("SKILLS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2).foregroundStyle(Theme.inkMuted)

                    if draft.skills.isEmpty {
                        Text("No skills added yet.")
                            .font(.system(size: 12)).foregroundStyle(Theme.inkMuted)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(draft.skills, id: \.self) { skill in
                                HStack(spacing: 4) {
                                    Text(skill)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                    if editMode {
                                        Button {
                                            draft.skills.removeAll { $0 == skill }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8))
                                                .foregroundStyle(Theme.inkSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.accentSoft)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            }
                        }
                    }

                    if editMode {
                        HStack(spacing: 8) {
                            TextField("Add a skill…", text: $newSkill)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .padding(8)
                                .background(Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))
                                .onSubmit { addSkill() }
                            Button("Add", action: addSkill)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Theme.ink)
                                .foregroundStyle(Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))

                // CV template
                VStack(alignment: .leading, spacing: 10) {
                    Text("CV TEMPLATE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2).foregroundStyle(Theme.inkMuted)
                    Text("Edit your LaTeX template to set your base CV content.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSecondary)
                    Button {
                        let path = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Documents/GitHub/YOLO-project/job-application-agent/cv_templates/base_template.tex")
                        NSWorkspace.shared.open(path)
                    } label: {
                        Label("Open base_template.tex", systemImage: "doc.text")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.surface)
                    .foregroundStyle(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .buttonStyle(.plain)
                }
                .padding(18)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
            }
            .padding(24)
        }
        .background(Theme.bg)
        .task { loadDraftFromState() }
    }

    private func loadDraftFromState() {
        guard let p = appState.profile else { return }
        draft.name = p.name ?? ""; draft.email = p.email ?? ""
        draft.phone = p.phone ?? ""; draft.linkedin = p.linkedin ?? ""
        draft.github = p.github ?? ""; draft.skills = p.skills ?? []
    }

    private func loadDraft() { loadDraftFromState() }

    private func addSkill() {
        let s = newSkill.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty && !draft.skills.contains(s) { draft.skills.append(s) }
        newSkill = ""
    }

    private func saveProfile() async {
        guard var p = appState.profile else { return }
        p = UserProfile(id: p.id, name: draft.name, email: draft.email,
                        phone: draft.phone, linkedin: draft.linkedin,
                        github: draft.github, skills: draft.skills)
        await appState.saveProfile(p)
        editMode = false
        withAnimation { saveSuccess = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveSuccess = false }
    }
}

struct ProfileField: View {
    let label: String; let icon: String
    @Binding var value: String; let isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkMuted)
            if isEditing {
                TextField(label, text: $value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .padding(7)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
            } else {
                Text(value.isEmpty ? "—" : value)
                    .font(.system(size: 13))
                    .foregroundStyle(value.isEmpty ? Theme.inkMuted : Theme.ink)
            }
        }
    }
}
