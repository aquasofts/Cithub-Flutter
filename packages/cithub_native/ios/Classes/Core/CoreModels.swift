import Foundation

public enum CoreRequiredAction: Sendable, Equatable {
    case none, tfa, passwordReset, bindAccount
}

public struct WebVpnLoginConfiguration: Sendable, Equatable {
    public var externalID: String
    public var requiresPassword: Bool
    public var requiresCaptcha: Bool
    public var dynamicVerificationTypes: [Int64]
}

public struct WebVpnCaptcha: Sendable, Equatable {
    public var id: String
    public var image: String
}

public struct WebVpnUser: Sendable, Equatable {
    public var username: String
    public var nickname: String
    public var fullName: String
    public var groups: [String]
    public var authType: Int64
    public var bindWechat: Bool
    public var bindOtp: Bool
    public var requiredAction: CoreRequiredAction
}

public struct CoreAcademicTerm: Sendable, Equatable {
    public var value: String
    public var label: String
    public var selected: Bool
}

public struct CoreCourseGrade: Sendable, Equatable {
    public var values: [String]
    public var sequence: String { values[safe: 0] ?? "" }
    public var semester: String { values[safe: 1] ?? "" }
    public var courseCode: String { values[safe: 2] ?? "" }
    public var courseName: String { values[safe: 3] ?? "" }
}

public struct CoreSelectedCourse: Sendable, Equatable {
    public var values: [String]
    public var sequence: String { values[safe: 0] ?? "" }
    public var courseName: String { values[safe: 1] ?? "" }
}

public struct CoreEvaluationBatch: Sendable, Equatable {
    public var sequence: String
    public var semester: String
    public var category: String
    public var name: String
    public var startDate: String
    public var endDate: String
    public var courseListPath: String
}

public struct CoreEvaluationCourse: Sendable, Equatable {
    public var sequence: String
    public var courseCode: String
    public var courseName: String
    public var teacher: String
    public var category: String
    public var totalScore: String
    public var evaluated: Bool
    public var submitted: Bool
    public var teachingHours: String
    public var formPath: String
}

public struct CoreEvaluationOption: Sendable, Equatable {
    public var id: String
    public var label: String
    public var score: String
    public var selected: Bool
}

public struct CoreEvaluationQuestion: Sendable, Equatable {
    public var id: String
    public var title: String
    public var options: [CoreEvaluationOption]
}

public struct CoreEvaluationAnswer: Sendable, Equatable {
    public var questionID: String
    public var optionID: String
}

public struct CoreEvaluationHiddenField: Sendable, Equatable {
    public var name: String
    public var value: String
}

public struct CoreEvaluationForm: Sendable, Equatable {
    public var courseName: String
    public var category: String
    public var actionPath: String
    public var hiddenFields: [CoreEvaluationHiddenField]
    public var questions: [CoreEvaluationQuestion]
    public var suggestionField: String?
    public var suggestion: String
    public var readOnly: Bool
}

public struct CoreTimetablePeriod: Sendable, Equatable {
    public var index: Int64
    public var label: String
    public var startTime: String
    public var endTime: String
}

public struct CoreTimetableCourse: Sendable, Equatable {
    public var id: String
    public var dayOfWeek: Int64
    public var periodIndex: Int64
    public var startSection: Int64
    public var endSection: Int64
    public var name: String
    public var teacher: String
    public var weeks: String
    public var weekNumbers: [Int64]
    public var location: String
}

public struct CoreTimetable: Sendable, Equatable {
    public var terms: [CoreAcademicTerm]
    public var selectedTerm: String
    public var periods: [CoreTimetablePeriod]
    public var courses: [CoreTimetableCourse]
    public var note: String
    public var referenceDateISO: String?
    public var referenceWeek: Int64?
    public var totalWeeks: Int64?
}

public enum CoreTiebaModeratorRole: Sendable, Equatable {
    case none, owner, assistant
}

public struct CoreTiebaAccount: Sendable, Equatable {
    public var uid: Int64
    public var username: String
    public var nickname: String
    public var avatarURL: String
    public var intro: String
    public var fans: String
    public var posts: String
    public var concerned: String
}

public struct CoreForumSummary: Sendable, Equatable {
    public var id: String
    public var name: String
    public var avatarURL: String
    public var memberCount: String
    public var threadCount: String
    public var forumRuleTitle: String
    public var isFollowed: Bool
    public var signed: Bool
    public var signedDays: Int64
}

public struct CoreTiebaContent: Sendable, Equatable {
    public var kind: String
    public var text: String
    public var emoticonID: String
    public var url: String
    public var originalURL: String
    public var width: Int64
    public var height: Int64

    public static func text(_ text: String) -> Self {
        CoreTiebaContent(kind: "text", text: text, emoticonID: "", url: "", originalURL: "", width: 0, height: 0)
    }
}

public struct CoreForumThread: Sendable, Equatable {
    public var id: String
    public var title: String
    public var excerpt: String
    public var excerptContent: [CoreTiebaContent]
    public var authorName: String
    public var authorNickname: String
    public var authorID: Int64
    public var authorPortrait: String
    public var replyCount: String
    public var viewCount: String
    public var lastReplyTime: String
    public var isTop: Bool
    public var isGood: Bool
    public var imageURLs: [String]
    public var forumID: Int64
    public var forumName: String
    public var authorModeratorRole: CoreTiebaModeratorRole
}

public struct CoreForumPage: Sendable, Equatable {
    public var forum: CoreForumSummary
    public var threads: [CoreForumThread]
    public var page: Int64
    public var hasMore: Bool
}

public struct CoreFloorReply: Sendable, Equatable {
    public var id: String
    public var authorID: Int64
    public var authorName: String
    public var authorNickname: String
    public var authorPortrait: String
    public var content: [CoreTiebaContent]
    public var time: String
    public var authorLevel: Int64
    public var authorTitle: String
    public var authorIP: String
    public var authorModeratorRole: CoreTiebaModeratorRole
}

public struct CoreFloorReplyPage: Sendable, Equatable {
    public var replies: [CoreFloorReply]
    public var page: Int64
    public var totalPages: Int64
    public var totalReplies: Int64
}

public struct CoreThreadFloor: Sendable, Equatable {
    public var postID: String
    public var floor: Int64
    public var authorID: Int64
    public var authorName: String
    public var authorNickname: String
    public var authorPortrait: String
    public var authorLevel: Int64
    public var authorTitle: String
    public var authorIP: String
    public var authorModeratorRole: CoreTiebaModeratorRole
    public var time: String
    public var content: [CoreTiebaContent]
    public var replies: [CoreFloorReply]
    public var replyCount: Int64
    public var isOriginalPoster: Bool
}

public struct CoreThreadPage: Sendable, Equatable {
    public var title: String
    public var body: CoreThreadFloor?
    public var floors: [CoreThreadFloor]
    public var page: Int64
    public var totalPages: Int64
    public var replyCount: Int64
}

public struct CoreTiebaUserPost: Sendable, Equatable {
    public var threadID: Int64
    public var postID: Int64
    public var title: String
    public var excerpt: String
    public var time: String
    public var forumID: Int64
    public var forumName: String
    public var replyCount: Int64
    public var isReply: Bool
    public var imageURLs: [String]
}

public struct CoreTiebaUserProfile: Sendable, Equatable {
    public var uid: Int64
    public var username: String
    public var nickname: String
    public var avatarURL: String
    public var intro: String
    public var fans: Int64
    public var concerned: Int64
    public var posts: Int64
    public var threads: [CoreTiebaUserPost]
    public var replies: [CoreTiebaUserPost]
}

public struct CoreTiebaImageRequest: Sendable, Equatable {
    public var url: String
    public var threadID: Int64
    public var postID: Int64
    public var forumID: Int64
    public var forumName: String
    public var imageIndex: Int64
    public var seeOriginalPosterOnly: Bool
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
