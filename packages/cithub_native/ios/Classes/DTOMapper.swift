import Foundation

func requiredActionDto(_ value: CoreRequiredAction) -> RequiredAccountAction {
    switch value {
    case .none: return .none
    case .tfa: return .tfa
    case .passwordReset: return .passwordReset
    case .bindAccount: return .bindAccount
    }
}

func userDto(_ value: WebVpnUser) -> UserInfoDto {
    UserInfoDto(
        username: value.username,
        nickname: value.nickname,
        fullName: value.fullName,
        groups: value.groups,
        authType: value.authType,
        bindWechat: value.bindWechat,
        bindOtp: value.bindOtp
    )
}

func academicTermDto(_ value: CoreAcademicTerm) -> AcademicTermDto {
    AcademicTermDto(value: value.value, label: value.label, selected: value.selected)
}

func gradeDto(_ value: CoreCourseGrade) -> CourseGradeDto {
    let v = value.values + Array(repeating: "", count: max(0, 20 - value.values.count))
    return CourseGradeDto(
        sequence: v[0], semester: v[1], courseCode: v[2], courseName: v[3],
        groupName: v[4], score: v[5], scoreMark: v[6], credit: v[7],
        totalHours: v[8], gradePoint: v[9], generalElective: v[10], originalScore: v[11],
        scoreDescription: v[12], note: v[13], retakeSemester: v[14], assessmentMethod: v[15],
        examType: v[16], courseAttribute: v[17], courseNature: v[18], courseCategory: v[19]
    )
}

func selectedCourseDto(_ value: CoreSelectedCourse) -> SelectedCourseDto {
    let v = value.values + Array(repeating: "", count: max(0, 8 - value.values.count))
    return SelectedCourseDto(
        sequence: v[0], courseName: v[1], courseCode: v[2], teacher: v[3],
        totalHours: v[4], credit: v[5], courseAttribute: v[6], courseNature: v[7]
    )
}

func evaluationBatchDto(_ value: CoreEvaluationBatch) -> EvaluationBatchDto {
    EvaluationBatchDto(
        sequence: value.sequence, semester: value.semester, category: value.category,
        name: value.name, startDate: value.startDate, endDate: value.endDate,
        courseListPath: value.courseListPath
    )
}

func evaluationCourseDto(_ value: CoreEvaluationCourse) -> EvaluationCourseDto {
    EvaluationCourseDto(
        sequence: value.sequence, courseCode: value.courseCode, courseName: value.courseName,
        teacher: value.teacher, category: value.category, totalScore: value.totalScore,
        evaluated: value.evaluated, submitted: value.submitted,
        teachingHours: value.teachingHours, formPath: value.formPath
    )
}

func evaluationFormDto(_ value: CoreEvaluationForm) -> EvaluationFormDto {
    EvaluationFormDto(
        courseName: value.courseName,
        category: value.category,
        actionPath: value.actionPath,
        hiddenFields: value.hiddenFields.map {
            EvaluationHiddenFieldDto(name: $0.name, value: $0.value)
        },
        questions: value.questions.map { question in
            EvaluationQuestionDto(
                id: question.id,
                title: question.title,
                options: question.options.map {
                    EvaluationOptionDto(
                        id: $0.id, label: $0.label, score: $0.score, selected: $0.selected
                    )
                }
            )
        },
        suggestionField: value.suggestionField,
        suggestion: value.suggestion,
        readOnly: value.readOnly
    )
}

func coreEvaluationForm(_ value: EvaluationFormDto) -> CoreEvaluationForm {
    CoreEvaluationForm(
        courseName: value.courseName,
        category: value.category,
        actionPath: value.actionPath,
        hiddenFields: value.hiddenFields.map { CoreEvaluationHiddenField(name: $0.name, value: $0.value) },
        questions: value.questions.map { question in
            CoreEvaluationQuestion(
                id: question.id,
                title: question.title,
                options: question.options.map {
                    CoreEvaluationOption(id: $0.id, label: $0.label, score: $0.score, selected: $0.selected)
                }
            )
        },
        suggestionField: value.suggestionField,
        suggestion: value.suggestion,
        readOnly: value.readOnly
    )
}

func timetableDto(_ value: CoreTimetable) -> TimetableDto {
    TimetableDto(
        terms: value.terms.map(academicTermDto),
        selectedTerm: value.selectedTerm,
        periods: value.periods.map {
            TimetablePeriodDto(
                index: $0.index, label: $0.label,
                startTime: $0.startTime, endTime: $0.endTime
            )
        },
        courses: value.courses.map {
            TimetableCourseDto(
                id: $0.id, dayOfWeek: $0.dayOfWeek, periodIndex: $0.periodIndex,
                startSection: $0.startSection, endSection: $0.endSection,
                name: $0.name, teacher: $0.teacher, weeks: $0.weeks,
                weekNumbers: $0.weekNumbers, location: $0.location
            )
        },
        note: value.note,
        referenceDateIso: value.referenceDateISO,
        referenceWeek: value.referenceWeek,
        totalWeeks: value.totalWeeks
    )
}

func moderatorDto(_ value: CoreTiebaModeratorRole) -> TiebaModeratorRole {
    switch value {
    case .none: return .none
    case .owner: return .owner
    case .assistant: return .assistant
    }
}

func tiebaAccountDto(_ value: CoreTiebaAccount) -> TiebaAccountDto {
    TiebaAccountDto(
        uid: value.uid, username: value.username, nickname: value.nickname,
        avatarUrl: value.avatarURL, intro: value.intro, fans: value.fans,
        posts: value.posts, concerned: value.concerned
    )
}

func tiebaContentDto(_ value: CoreTiebaContent) -> TiebaContentDto {
    TiebaContentDto(
        kind: value.kind, text: value.text, emoticonId: value.emoticonID,
        url: value.url, originalUrl: value.originalURL,
        width: value.width, height: value.height
    )
}

func forumPageDto(_ value: CoreForumPage) -> ForumPageDto {
    ForumPageDto(
        forum: ForumSummaryDto(
            id: value.forum.id, name: value.forum.name, avatarUrl: value.forum.avatarURL,
            memberCount: value.forum.memberCount, threadCount: value.forum.threadCount,
            forumRuleTitle: value.forum.forumRuleTitle, isFollowed: value.forum.isFollowed,
            signed: value.forum.signed, signedDays: value.forum.signedDays
        ),
        threads: value.threads.map { thread in
            ForumThreadDto(
                id: thread.id, title: thread.title, excerpt: thread.excerpt,
                excerptContent: thread.excerptContent.map(tiebaContentDto),
                authorName: thread.authorName, authorNickname: thread.authorNickname,
                authorId: thread.authorID, authorPortrait: thread.authorPortrait,
                replyCount: thread.replyCount, viewCount: thread.viewCount,
                lastReplyTime: thread.lastReplyTime, isTop: thread.isTop, isGood: thread.isGood,
                imageUrls: thread.imageURLs, forumId: thread.forumID, forumName: thread.forumName,
                authorModeratorRole: moderatorDto(thread.authorModeratorRole)
            )
        },
        page: value.page,
        hasMore: value.hasMore
    )
}

func floorReplyDto(_ value: CoreFloorReply) -> FloorReplyDto {
    FloorReplyDto(
        id: value.id, authorId: value.authorID, authorName: value.authorName,
        authorNickname: value.authorNickname, authorPortrait: value.authorPortrait,
        content: value.content.map(tiebaContentDto), time: value.time,
        authorLevel: value.authorLevel, authorTitle: value.authorTitle,
        authorIp: value.authorIP, authorModeratorRole: moderatorDto(value.authorModeratorRole)
    )
}

func floorReplyPageDto(_ value: CoreFloorReplyPage) -> FloorReplyPageDto {
    FloorReplyPageDto(
        replies: value.replies.map(floorReplyDto), page: value.page,
        totalPages: value.totalPages, totalReplies: value.totalReplies
    )
}

func threadFloorDto(_ value: CoreThreadFloor) -> ThreadFloorDto {
    ThreadFloorDto(
        postId: value.postID, floor: value.floor, authorId: value.authorID,
        authorName: value.authorName, authorNickname: value.authorNickname,
        authorPortrait: value.authorPortrait, authorLevel: value.authorLevel,
        authorTitle: value.authorTitle, authorIp: value.authorIP,
        authorModeratorRole: moderatorDto(value.authorModeratorRole), time: value.time,
        content: value.content.map(tiebaContentDto), replies: value.replies.map(floorReplyDto),
        replyCount: value.replyCount, isOriginalPoster: value.isOriginalPoster
    )
}

func threadPageDto(_ value: CoreThreadPage) -> ThreadPageDto {
    ThreadPageDto(
        title: value.title,
        body: value.body.map(threadFloorDto),
        floors: value.floors.map(threadFloorDto),
        page: value.page,
        totalPages: value.totalPages,
        replyCount: value.replyCount
    )
}

func tiebaUserProfileDto(_ value: CoreTiebaUserProfile) -> TiebaUserProfileDto {
    TiebaUserProfileDto(
        uid: value.uid, username: value.username, nickname: value.nickname,
        avatarUrl: value.avatarURL, intro: value.intro, fans: value.fans,
        concerned: value.concerned, posts: value.posts,
        threads: value.threads.map { post in
            TiebaUserPostDto(
                threadId: post.threadID, postId: post.postID, title: post.title,
                excerpt: post.excerpt, time: post.time, forumId: post.forumID,
                forumName: post.forumName, replyCount: post.replyCount,
                isReply: post.isReply, imageUrls: post.imageURLs
            )
        },
        replies: value.replies.map { post in
            TiebaUserPostDto(
                threadId: post.threadID, postId: post.postID, title: post.title,
                excerpt: post.excerpt, time: post.time, forumId: post.forumID,
                forumName: post.forumName, replyCount: post.replyCount,
                isReply: post.isReply, imageUrls: post.imageURLs
            )
        }
    )
}
