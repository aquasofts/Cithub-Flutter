import 'dart:async';

import '../native/cithub_api.g.dart';
import 'cithub_platform.dart';

class DemoCithubPlatform implements CithubPlatform {
  DemoCithubPlatform({this.autoCaptcha = true});

  final bool autoCaptcha;
  final _events = StreamController<NativeEventDto>.broadcast();
  bool _webVpnSignedIn = false;

  WebVpnSessionDto _session({String? message}) => WebVpnSessionDto(
    status: _webVpnSignedIn ? AuthStatus.signedIn : AuthStatus.signedOut,
    requiredAction: RequiredAccountAction.none,
    user: _webVpnSignedIn
        ? UserInfoDto(
            username: '20260001',
            nickname: 'Cithub 用户',
            fullName: '测试同学',
            groups: const ['学生'],
            authType: 1,
            bindWechat: true,
            bindOtp: false,
          )
        : null,
    savedAccounts: const [],
    captcha: CaptchaDto(
      id: 'demo-captcha',
      base64Image: '',
      recognizedCode: autoCaptcha ? '1234' : '',
    ),
    requiresCaptcha: true,
    message: message,
  );

  @override
  Future<NativeCapabilities> capabilities() async => NativeCapabilities(
    flavor: autoCaptcha
        ? CaptchaFlavor.autoCaptcha
        : CaptchaFlavor.manualCaptcha,
    captchaAutofillEnabled: autoCaptcha,
    versionName: '1.0.0',
    versionCode: 1,
  );

  @override
  Future<WebVpnSessionDto> initializeWebVpn() async => _session();
  @override
  Future<WebVpnSessionDto> loginWebVpn(LoginRequestDto request) async {
    _webVpnSignedIn = true;
    return _session(message: '登录成功');
  }

  @override
  Future<WebVpnSessionDto> refreshWebVpnCaptcha() async => _session();
  @override
  Future<WebVpnSessionDto> selectSavedWebVpnAccount(String username) async =>
      _session(message: '已选择 $username');
  @override
  Future<WebVpnSessionDto> forgetSavedWebVpnAccount(String username) async =>
      _session(message: '已删除 $username');
  @override
  Future<WebVpnSessionDto> logoutWebVpn() async {
    _webVpnSignedIn = false;
    return _session(message: '已退出');
  }

  @override
  Future<WebVpnSessionDto> initializeAcademic(String webVpnUsername) async =>
      _session();
  @override
  Future<WebVpnSessionDto> loginAcademic(LoginRequestDto request) async =>
      _session();
  @override
  Future<bool> logoutAcademic() async => true;

  @override
  Future<List<AcademicTermDto>> loadAcademicTerms() async => [
    AcademicTermDto(
      value: '2025-2026-2',
      label: '2025-2026 学年第二学期',
      selected: true,
    ),
    AcademicTermDto(
      value: '2025-2026-1',
      label: '2025-2026 学年第一学期',
      selected: false,
    ),
  ];

  @override
  Future<List<CourseGradeDto>> loadGrades(
    String term, {
    bool bestOnly = false,
  }) async => [
    CourseGradeDto(
      sequence: '1',
      semester: term,
      courseCode: 'CS101',
      courseName: '程序设计基础',
      groupName: '01',
      score: '92',
      scoreMark: '',
      credit: '4.0',
      totalHours: '64',
      gradePoint: '4.2',
      generalElective: '否',
      originalScore: '92',
      description: '',
      note: '',
      retakeSemester: '',
      assessmentMethod: '考试',
      examType: '正常考试',
      courseAttribute: '必修',
      courseNature: '专业基础课',
      courseCategory: '专业课',
    ),
    CourseGradeDto(
      sequence: '2',
      semester: term,
      courseCode: 'MA102',
      courseName: '高等数学',
      groupName: '02',
      score: '86',
      scoreMark: '',
      credit: '5.0',
      totalHours: '80',
      gradePoint: '3.6',
      generalElective: '否',
      originalScore: '86',
      description: '',
      note: '',
      retakeSemester: '',
      assessmentMethod: '考试',
      examType: '正常考试',
      courseAttribute: '必修',
      courseNature: '公共基础课',
      courseCategory: '基础课',
    ),
  ];

  @override
  Future<TimetableDto> loadTimetable([String? term]) async => TimetableDto(
    terms: await loadAcademicTerms(),
    selectedTerm: term ?? '2025-2026-2',
    periods: [
      TimetablePeriodDto(
        index: 0,
        label: '1-2',
        startTime: '08:00',
        endTime: '09:35',
      ),
      TimetablePeriodDto(
        index: 1,
        label: '3-4',
        startTime: '10:00',
        endTime: '11:35',
      ),
    ],
    courses: [
      TimetableCourseDto(
        id: 'course-1',
        dayOfWeek: 1,
        periodIndex: 0,
        startSection: 1,
        endSection: 2,
        name: '程序设计基础',
        teacher: '王老师',
        weeks: '1-16周',
        weekNumbers: List.generate(16, (index) => index + 1),
        location: '笃行楼 302',
      ),
      TimetableCourseDto(
        id: 'course-2',
        dayOfWeek: 3,
        periodIndex: 1,
        startSection: 3,
        endSection: 4,
        name: '高等数学',
        teacher: '李老师',
        weeks: '1-16周',
        weekNumbers: List.generate(16, (index) => index + 1),
        location: '博学楼 201',
      ),
    ],
    note: '',
    referenceDateIso: '2026-02-23',
    referenceWeek: 1,
    totalWeeks: 20,
  );

  @override
  Future<List<SelectedCourseDto>> loadSelectionResults(String term) async => [
    SelectedCourseDto(
      sequence: '1',
      courseName: '移动应用开发',
      courseCode: 'CS305',
      teacher: '陈老师',
      totalHours: '48',
      credit: '3.0',
      courseAttribute: '选修',
      courseNature: '专业选修课',
    ),
  ];

  @override
  Future<List<EvaluationBatchDto>> loadEvaluationBatches() async => [
    EvaluationBatchDto(
      sequence: '1',
      semester: '2025-2026-2',
      category: '理论课',
      name: '期末学生评价',
      startDate: '2026-06-01',
      endDate: '2026-06-30',
      courseListPath: '/evaluation/courses',
    ),
  ];

  @override
  Future<List<EvaluationCourseDto>> loadEvaluationCourses(String path) async =>
      [
        EvaluationCourseDto(
          sequence: '1',
          courseCode: 'CS101',
          courseName: '程序设计基础',
          teacher: '王老师',
          category: '理论课',
          totalScore: '100',
          evaluated: false,
          submitted: false,
          teachingHours: '64',
          formPath: '/evaluation/form/1',
        ),
      ];

  @override
  Future<EvaluationFormDto> loadEvaluationForm(String path) async =>
      EvaluationFormDto(
        courseName: '程序设计基础',
        category: '理论课',
        actionPath: '/evaluation/save',
        hiddenFields: [],
        questions: [
          EvaluationQuestionDto(
            id: 'q1',
            title: '教学态度认真，课程准备充分',
            options: [
              EvaluationOptionDto(
                id: 'excellent',
                label: '优秀',
                score: '10',
                selected: true,
              ),
              EvaluationOptionDto(
                id: 'good',
                label: '良好',
                score: '8',
                selected: false,
              ),
            ],
          ),
        ],
        suggestionField: 'suggestion',
        suggestion: '',
        readOnly: false,
      );

  @override
  Future<bool> saveEvaluation(
    EvaluationFormDto form,
    List<EvaluationAnswerDto> answers,
    String suggestion, {
    required bool submit,
  }) async => true;

  @override
  Future<String> prepareAcademicWebPage(String path) async =>
      'https://webvpn.example.edu/academic/$path';

  ForumSummaryDto _forum(String name) => ForumSummaryDto(
    id: '1',
    name: name,
    avatarUrl: '',
    memberCount: '12.8万',
    threadCount: '486万',
    forumRuleTitle: '【$name吧吧规】请文明交流',
    isFollowed: true,
    signed: false,
    signedDays: 0,
  );

  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) async => ForumPageDto(
    forum: _forum(name),
    page: page,
    hasMore: page < 3,
    threads: List.generate(
      8,
      (index) => ForumThreadDto(
        id: '${page}00$index',
        title: index == 0 ? '欢迎来到 $name 吧' : '$name 讨论帖 ${index + 1}',
        excerpt: index == 0 ? '首页表情#(滑稽)#（笑尿）' : '这是用于离线验收页面、分页和列表状态恢复的模拟内容。',
        excerptContent: [
          TiebaContentDto(
            kind: 'text',
            text: index == 0 ? '首页表情#(滑稽)#（笑尿）' : '这是用于离线验收页面、分页和列表状态恢复的模拟内容。',
            emoticonId: '',
            url: '',
            originalUrl: '',
            width: 0,
            height: 0,
          ),
        ],
        authorName: 'user$index',
        authorNickname: '吧友 $index',
        authorId: index + 10,
        authorPortrait: '',
        replyCount: '${20 + index}',
        viewCount: '${300 + index * 17}',
        lastReplyTime: '刚刚',
        isTop: page == 1 && index == 0,
        isGood: goodOnly || index == 1,
        imageUrls: const [],
        forumId: 1,
        forumName: name,
        authorModeratorRole: index == 0
            ? TiebaModeratorRole.owner
            : TiebaModeratorRole.none,
      ),
    ),
  );

  @override
  Future<ForumPageDto> searchForum(
    String name,
    String keyword, {
    int page = 1,
  }) => loadForum('$name · $keyword', page: page);

  @override
  Future<ThreadPageDto> loadThread(
    String threadId,
    int forumId,
    String forumName, {
    int page = 1,
    String sort = 'asc',
    bool onlyOriginalPoster = false,
  }) async {
    ThreadFloorDto floor(int number) => ThreadFloorDto(
      postId: '$threadId${number.toString().padLeft(4, '0')}',
      floor: number,
      authorId: 100 + number,
      authorName: 'author$number',
      authorNickname: number == 1 ? '楼主' : '吧友 $number',
      authorPortrait: '',
      authorLevel: 8,
      authorTitle: number == 1 ? '砥砺明德' : '渐入佳境',
      authorIp: '吉林',
      authorModeratorRole: number == 1
          ? TiebaModeratorRole.owner
          : TiebaModeratorRole.none,
      time: '2026-08-18 12:${number.toString().padLeft(2, '0')}',
      content: [
        TiebaContentDto(
          kind: 'text',
          text: number == 1 ? '这是主题内容。' : '这是第 $number 楼的回复。',
          emoticonId: '',
          url: '',
          originalUrl: '',
          width: 0,
          height: 0,
        ),
      ],
      replies: number == 2
          ? List.generate(
              3,
              (index) => FloorReplyDto(
                id: '$threadId${number.toString().padLeft(4, '0')}$index',
                authorId: 300 + index,
                authorName: 'preview$index',
                authorNickname: '楼中楼用户 ${index + 1}',
                authorPortrait: '',
                content: [
                  TiebaContentDto(
                    kind: 'text',
                    text: '这是预览回复 ${index + 1}。',
                    emoticonId: '',
                    url: '',
                    originalUrl: '',
                    width: 0,
                    height: 0,
                  ),
                ],
                time: '刚刚',
                authorLevel: index + 3,
                authorTitle: '渐入佳境',
                authorIp: '吉林',
                authorModeratorRole: TiebaModeratorRole.none,
              ),
            )
          : const [],
      replyCount: number == 2 ? 5 : 0,
      isOriginalPoster: number == 1,
    );
    final floors = List.generate(10, (index) => floor(index + 1));
    return ThreadPageDto(
      title: '$forumName 主题详情',
      body: floors.first,
      floors: floors.skip(1).toList(),
      page: page,
      totalPages: 2,
      replyCount: 18,
    );
  }

  @override
  Future<FloorReplyPageDto> loadFloorReplies(
    String threadId,
    String postId, {
    int page = 1,
  }) async => FloorReplyPageDto(
    replies: [
      FloorReplyDto(
        id: '$postId-$page',
        authorId: 201 + page,
        authorName: 'reply_user',
        authorNickname: '楼中楼用户',
        authorPortrait: '',
        content: [
          TiebaContentDto(
            kind: 'text',
            text: '这是楼中楼回复。',
            emoticonId: '',
            url: '',
            originalUrl: '',
            width: 0,
            height: 0,
          ),
        ],
        time: '刚刚',
        authorLevel: 7,
        authorTitle: '小有名气',
        authorIp: '吉林',
        authorModeratorRole: TiebaModeratorRole.none,
      ),
    ],
    page: page,
    totalPages: 2,
    totalReplies: 2,
  );

  @override
  Future<TiebaUserProfileDto> loadTiebaUserProfile(int uid) async =>
      TiebaUserProfileDto(
        uid: uid,
        username: 'user$uid',
        nickname: '贴吧用户 $uid',
        avatarUrl: '',
        intro: '这个人很懒，什么也没写',
        fans: 12,
        concerned: 8,
        posts: 36,
        threads: const [],
        replies: const [],
      );

  @override
  Future<String> resolveOriginalImage(TiebaImageRequestDto request) async =>
      request.url;

  @override
  Future<TiebaAccountDto?> currentTiebaAccount() async => null;
  @override
  Future<TiebaAccountDto> completeTiebaWebLogin() async => TiebaAccountDto(
    uid: 10001,
    username: 'cithub_user',
    nickname: 'Cithub 用户',
    avatarUrl: '',
    intro: '',
    fans: '0',
    posts: '0',
    concerned: '0',
  );
  @override
  Future<TiebaAccountDto> refreshTiebaAccount() => completeTiebaWebLogin();
  @override
  Future<bool> logoutTieba() async => true;
  @override
  Future<String> loadForumRule(int forumId) async => '文明交流，遵守法律法规与贴吧协议。';
  @override
  Future<String> signForum(String forumId, String forumName) async =>
      '$forumName 签到成功';
  @override
  Future<String> followForum(String forumId, String forumName) async =>
      '已关注 $forumName';
  @override
  Future<bool> launchOfficialReply(int threadId, [int? postId]) async => true;

  @override
  Future<UpdateReleaseDto?> checkUpdate({
    bool includePrereleases = false,
  }) async => null;
  @override
  Future<bool> startUpdate(UpdateReleaseDto release) async => true;
  @override
  Future<bool> cancelUpdate() async => true;
  @override
  Future<bool> installUpdate() async => true;
  @override
  Future<String> exportRuntimeLog() async => '/tmp/cithub-runtime.log';
  @override
  Future<bool> clearRuntimeLog() async => true;
  @override
  Future<bool> setThemedIcon(bool enabled) async => true;
  @override
  Stream<NativeEventDto> get events => _events.stream;
}
