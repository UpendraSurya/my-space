import Foundation

// MARK: - API Response Models

struct JobSummary: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let company: String
    let location: String?
    let salary: String?
    let url: String
    let source: String?
    let status: String
    let matchScore: Float
    let foundDate: String?
    let hasApplication: Bool
    let atsScore: Float?

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, salary, url, source, status
        case matchScore = "match_score"
        case foundDate = "found_date"
        case hasApplication = "has_application"
        case atsScore = "ats_score"
    }

    var statusEnum: JobStatus { JobStatus(rawValue: status) ?? .new }
    var matchPercent: String { "\(Int(matchScore * 100))%" }
}

struct JobDetail: Identifiable, Codable {
    let id: Int
    let title: String
    let company: String
    let location: String?
    let salary: String?
    let url: String
    let source: String?
    let status: String
    let matchScore: Float
    let rawDescription: String?
    let analysis: JobAnalysis?
    let foundDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, company, location, salary, url, source, status
        case matchScore = "match_score"
        case rawDescription = "raw_description"
        case analysis
        case foundDate = "found_date"
    }
}

struct JobAnalysis: Codable {
    let requiredSkills: [String]?
    let preferredSkills: [String]?
    let techStack: [String]?
    let keyResponsibilities: [String]?
    let seniorityLevel: String?
    let experienceYearsRequired: Int?
    let isRemote: Bool?
    let summary: String?
    let redFlags: [String]?

    enum CodingKeys: String, CodingKey {
        case requiredSkills = "required_skills"
        case preferredSkills = "preferred_skills"
        case techStack = "tech_stack"
        case keyResponsibilities = "key_responsibilities"
        case seniorityLevel = "seniority_level"
        case experienceYearsRequired = "experience_years_required"
        case isRemote = "is_remote"
        case summary
        case redFlags = "red_flags"
    }
}

struct AppStats: Codable {
    let totalJobs: Int
    let newJobs: Int
    let analyzedJobs: Int
    let readyJobs: Int
    let appliedJobs: Int
    let avgAtsScore: Float
    let cvsGenerated: Int

    enum CodingKeys: String, CodingKey {
        case totalJobs = "total_jobs"
        case newJobs = "new_jobs"
        case analyzedJobs = "analyzed_jobs"
        case readyJobs = "ready_jobs"
        case appliedJobs = "applied_jobs"
        case avgAtsScore = "avg_ats_score"
        case cvsGenerated = "cvs_generated"
    }
}

struct ApplicationInfo: Codable {
    let id: Int
    let jobId: Int
    let cvPath: String?
    let texPath: String?
    let atsScore: Float?
    let status: String?
    let createdDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case jobId = "job_id"
        case cvPath = "cv_path"
        case texPath = "tex_path"
        case atsScore = "ats_score"
        case status
        case createdDate = "created_date"
    }
}

struct ATSScoreDetail: Codable {
    let totalScore: Float
    let keywordScore: Float
    let formattingScore: Float
    let relevanceScore: Float
    let completenessScore: Float
    let breakdown: [String: Float]?

    enum CodingKeys: String, CodingKey {
        case totalScore = "total_score"
        case keywordScore = "keyword_score"
        case formattingScore = "formatting_score"
        case relevanceScore = "relevance_score"
        case completenessScore = "completeness_score"
        case breakdown
    }
}

struct PipelineLog: Codable {
    let running: Bool
    let log: [PipelineLogEntry]
}

struct PipelineLogEntry: Codable, Identifiable {
    var id: String { timestamp + stage }
    let timestamp: String
    let stage: String
    let message: String
}

struct UserProfile: Codable {
    let id: Int
    var name: String?
    var email: String?
    var phone: String?
    var linkedin: String?
    var github: String?
    var skills: [String]?
}

// MARK: - Enums

enum JobStatus: String, CaseIterable {
    case new, analyzed, cv_tailored, ats_optimized, ready, applied, rejected, interviewing, offer, skipped

    var displayName: String {
        switch self {
        case .new: return "New"
        case .analyzed: return "Analyzed"
        case .cv_tailored: return "CV Ready"
        case .ats_optimized: return "ATS Done"
        case .ready: return "Ready"
        case .applied: return "Applied"
        case .rejected: return "Rejected"
        case .interviewing: return "Interview"
        case .offer: return "Offer 🎉"
        case .skipped: return "Skipped"
        }
    }

    var color: String {
        switch self {
        case .new: return "gray"
        case .analyzed: return "blue"
        case .cv_tailored, .ats_optimized: return "yellow"
        case .ready: return "green"
        case .applied: return "teal"
        case .interviewing: return "purple"
        case .offer: return "mint"
        case .rejected: return "red"
        case .skipped: return "gray"
        }
    }
}

// MARK: - Study Hub Models

struct StudyNote: Identifiable, Codable, Equatable {
    var id: String { noteId }
    let noteId: String
    let title: String
    let preview: String
    let tags: [String]
    let topic: String
    let date: String
    let path: String

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case title, preview, tags, topic, date, path
    }
}

struct StudyNoteContent: Codable {
    let noteId: String
    let title: String
    let content: String
    let tags: [String]
    let topic: String
    let date: String
    let path: String

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case title, content, tags, topic, date, path
    }
}

struct StudySearchResult: Identifiable, Codable {
    var id: String { noteId }
    let noteId: String
    let title: String
    let snippet: String
    let score: Float
    let tags: [String]
    let topic: String
    let date: String

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case title, snippet, score, tags, topic, date
    }
}

struct StudySearchResponse: Codable {
    let results: [StudySearchResult]
    let query: String
}

struct StudyChatMessage: Identifiable, Codable {
    let id: UUID
    let role: String   // "user" | "assistant"
    let content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct StudyChatRequest: Codable {
    let query: String
    let history: [StudyChatHistoryItem]

    struct StudyChatHistoryItem: Codable {
        let role: String
        let content: String
    }
}

struct StudyChatResponse: Codable {
    let answer: String
    let sources: [String]
}

struct StudyUploadResponse: Codable {
    let ok: Bool
    let savedPath: String
    let noteId: String
    let title: String
    let charsExtracted: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case savedPath = "saved_path"
        case noteId = "note_id"
        case title
        case charsExtracted = "chars_extracted"
    }
}

// MARK: - Navigation

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case jobs = "Jobs"
    case tracker = "Tracker"
    case profile = "Profile"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .jobs: return "briefcase.fill"
        case .tracker: return "checklist"
        case .profile: return "person.fill"
        }
    }
}
