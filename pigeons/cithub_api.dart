import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/native/cithub_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'packages/cithub_native/android/src/main/kotlin/com/aquasofts/cithub_flutter/native/CithubApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.aquasofts.cithub_flutter.native',
      includeErrorClass: true,
    ),
    dartPackageName: 'cithub_flutter',
  ),
)
enum CaptchaFlavor { autoCaptcha, manualCaptcha }

enum AuthStatus {
  initializing,
  signedOut,
  submitting,
  signedIn,
  actionRequired,
}

enum RequiredAccountAction { none, tfa, passwordReset, bindAccount }

enum TiebaSignOutcome { idle, running, success, alreadySigned, failed }

enum TiebaModeratorRole { none, owner, assistant }

enum UpdateStage { idle, checking, available, downloading, ready, failed }

class NativeCapabilities {
  NativeCapabilities({
    required this.flavor,
    required this.captchaAutofillEnabled,
    required this.versionName,
    required this.versionCode,
  });

  CaptchaFlavor flavor;
  bool captchaAutofillEnabled;
  String versionName;
  int versionCode;
}

class SavedAccountDto {
  SavedAccountDto({required this.username, required this.lastUsedAtMillis});
  String username;
  int lastUsedAtMillis;
}

class CaptchaDto {
  CaptchaDto({
    required this.id,
    required this.base64Image,
    required this.recognizedCode,
  });
  String id;
  String base64Image;
  String recognizedCode;
}

class LoginRequestDto {
  LoginRequestDto({
    required this.username,
    required this.password,
    required this.captchaId,
    required this.captchaCode,
    required this.rememberPassword,
    required this.useSavedPassword,
  });
  String username;
  String password;
  String captchaId;
  String captchaCode;
  bool rememberPassword;
  bool useSavedPassword;
}

class UserInfoDto {
  UserInfoDto({
    required this.username,
    required this.nickname,
    required this.fullName,
    required this.groups,
    required this.authType,
    required this.bindWechat,
    required this.bindOtp,
  });
  String username;
  String nickname;
  String fullName;
  List<String> groups;
  int authType;
  bool bindWechat;
  bool bindOtp;
}

class WebVpnSessionDto {
  WebVpnSessionDto({
    required this.status,
    required this.requiredAction,
    required this.user,
    required this.savedAccounts,
    required this.captcha,
    required this.requiresCaptcha,
    required this.message,
  });
  AuthStatus status;
  RequiredAccountAction requiredAction;
  UserInfoDto? user;
  List<SavedAccountDto> savedAccounts;
  CaptchaDto? captcha;
  bool requiresCaptcha;
  String? message;
}

class AcademicTermDto {
  AcademicTermDto({
    required this.value,
    required this.label,
    required this.selected,
  });
  String value;
  String label;
  bool selected;
}

class CourseGradeDto {
  CourseGradeDto({
    required this.sequence,
    required this.semester,
    required this.courseCode,
    required this.courseName,
    required this.groupName,
    required this.score,
    required this.scoreMark,
    required this.credit,
    required this.totalHours,
    required this.gradePoint,
    required this.generalElective,
    required this.originalScore,
    required this.description,
    required this.note,
    required this.retakeSemester,
    required this.assessmentMethod,
    required this.examType,
    required this.courseAttribute,
    required this.courseNature,
    required this.courseCategory,
  });
  String sequence;
  String semester;
  String courseCode;
  String courseName;
  String groupName;
  String score;
  String scoreMark;
  String credit;
  String totalHours;
  String gradePoint;
  String generalElective;
  String originalScore;
  String description;
  String note;
  String retakeSemester;
  String assessmentMethod;
  String examType;
  String courseAttribute;
  String courseNature;
  String courseCategory;
}

class TimetablePeriodDto {
  TimetablePeriodDto({
    required this.index,
    required this.label,
    required this.startTime,
    required this.endTime,
  });
  int index;
  String label;
  String startTime;
  String endTime;
}

class TimetableCourseDto {
  TimetableCourseDto({
    required this.id,
    required this.dayOfWeek,
    required this.periodIndex,
    required this.startSection,
    required this.endSection,
    required this.name,
    required this.teacher,
    required this.weeks,
    required this.weekNumbers,
    required this.location,
  });
  String id;
  int dayOfWeek;
  int periodIndex;
  int startSection;
  int endSection;
  String name;
  String teacher;
  String weeks;
  List<int> weekNumbers;
  String location;
}

class TimetableDto {
  TimetableDto({
    required this.terms,
    required this.selectedTerm,
    required this.periods,
    required this.courses,
    required this.note,
    required this.referenceDateIso,
    required this.referenceWeek,
    required this.totalWeeks,
  });
  List<AcademicTermDto> terms;
  String selectedTerm;
  List<TimetablePeriodDto> periods;
  List<TimetableCourseDto> courses;
  String note;
  String? referenceDateIso;
  int? referenceWeek;
  int? totalWeeks;
}

class SelectedCourseDto {
  SelectedCourseDto({
    required this.sequence,
    required this.courseName,
    required this.courseCode,
    required this.teacher,
    required this.totalHours,
    required this.credit,
    required this.courseAttribute,
    required this.courseNature,
  });
  String sequence;
  String courseName;
  String courseCode;
  String teacher;
  String totalHours;
  String credit;
  String courseAttribute;
  String courseNature;
}

class EvaluationBatchDto {
  EvaluationBatchDto({
    required this.sequence,
    required this.semester,
    required this.category,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.courseListPath,
  });
  String sequence;
  String semester;
  String category;
  String name;
  String startDate;
  String endDate;
  String courseListPath;
}

class EvaluationCourseDto {
  EvaluationCourseDto({
    required this.sequence,
    required this.courseCode,
    required this.courseName,
    required this.teacher,
    required this.category,
    required this.totalScore,
    required this.evaluated,
    required this.submitted,
    required this.teachingHours,
    required this.formPath,
  });
  String sequence;
  String courseCode;
  String courseName;
  String teacher;
  String category;
  String totalScore;
  bool evaluated;
  bool submitted;
  String teachingHours;
  String formPath;
}

class EvaluationOptionDto {
  EvaluationOptionDto({
    required this.id,
    required this.label,
    required this.score,
    required this.selected,
  });
  String id;
  String label;
  String score;
  bool selected;
}

class EvaluationQuestionDto {
  EvaluationQuestionDto({
    required this.id,
    required this.title,
    required this.options,
  });
  String id;
  String title;
  List<EvaluationOptionDto> options;
}

class EvaluationAnswerDto {
  EvaluationAnswerDto({required this.questionId, required this.optionId});
  String questionId;
  String optionId;
}

class EvaluationHiddenFieldDto {
  EvaluationHiddenFieldDto({required this.name, required this.value});
  String name;
  String value;
}

class EvaluationFormDto {
  EvaluationFormDto({
    required this.courseName,
    required this.category,
    required this.actionPath,
    required this.hiddenFields,
    required this.questions,
    required this.suggestionField,
    required this.suggestion,
    required this.readOnly,
  });
  String courseName;
  String category;
  String actionPath;
  List<EvaluationHiddenFieldDto> hiddenFields;
  List<EvaluationQuestionDto> questions;
  String? suggestionField;
  String suggestion;
  bool readOnly;
}

class TiebaAccountDto {
  TiebaAccountDto({
    required this.uid,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    required this.intro,
    required this.fans,
    required this.posts,
    required this.concerned,
  });
  int uid;
  String username;
  String nickname;
  String avatarUrl;
  String intro;
  String fans;
  String posts;
  String concerned;
}

class ForumSummaryDto {
  ForumSummaryDto({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.memberCount,
    required this.threadCount,
    required this.forumRuleTitle,
    required this.isFollowed,
    required this.signed,
    required this.signedDays,
  });
  String id;
  String name;
  String avatarUrl;
  String memberCount;
  String threadCount;
  String forumRuleTitle;
  bool isFollowed;
  bool signed;
  int signedDays;
}

class ForumThreadDto {
  ForumThreadDto({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.authorName,
    required this.authorNickname,
    required this.authorId,
    required this.authorPortrait,
    required this.replyCount,
    required this.viewCount,
    required this.lastReplyTime,
    required this.isTop,
    required this.isGood,
    required this.imageUrls,
    required this.forumId,
    required this.forumName,
    required this.authorModeratorRole,
  });
  String id;
  String title;
  String excerpt;
  String authorName;
  String authorNickname;
  int authorId;
  String authorPortrait;
  String replyCount;
  String viewCount;
  String lastReplyTime;
  bool isTop;
  bool isGood;
  List<String> imageUrls;
  int forumId;
  String forumName;
  TiebaModeratorRole authorModeratorRole;
}

class ForumPageDto {
  ForumPageDto({
    required this.forum,
    required this.threads,
    required this.page,
    required this.hasMore,
  });
  ForumSummaryDto forum;
  List<ForumThreadDto> threads;
  int page;
  bool hasMore;
}

class TiebaContentDto {
  TiebaContentDto({
    required this.kind,
    required this.text,
    required this.url,
    required this.originalUrl,
    required this.width,
    required this.height,
  });
  String kind;
  String text;
  String url;
  String originalUrl;
  int width;
  int height;
}

class FloorReplyDto {
  FloorReplyDto({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorNickname,
    required this.authorPortrait,
    required this.content,
    required this.time,
    required this.authorLevel,
    required this.authorTitle,
    required this.authorIp,
    required this.authorModeratorRole,
  });
  String id;
  int authorId;
  String authorName;
  String authorNickname;
  String authorPortrait;
  List<TiebaContentDto> content;
  String time;
  int authorLevel;
  String authorTitle;
  String authorIp;
  TiebaModeratorRole authorModeratorRole;
}

class FloorReplyPageDto {
  FloorReplyPageDto({
    required this.replies,
    required this.page,
    required this.totalPages,
    required this.totalReplies,
  });
  List<FloorReplyDto> replies;
  int page;
  int totalPages;
  int totalReplies;
}

class ThreadFloorDto {
  ThreadFloorDto({
    required this.postId,
    required this.floor,
    required this.authorId,
    required this.authorName,
    required this.authorNickname,
    required this.authorPortrait,
    required this.authorLevel,
    required this.authorTitle,
    required this.authorIp,
    required this.authorModeratorRole,
    required this.time,
    required this.content,
    required this.replies,
    required this.replyCount,
    required this.isOriginalPoster,
  });
  String postId;
  int floor;
  int authorId;
  String authorName;
  String authorNickname;
  String authorPortrait;
  int authorLevel;
  String authorTitle;
  String authorIp;
  TiebaModeratorRole authorModeratorRole;
  String time;
  List<TiebaContentDto> content;
  List<FloorReplyDto> replies;
  int replyCount;
  bool isOriginalPoster;
}

class ThreadPageDto {
  ThreadPageDto({
    required this.title,
    required this.body,
    required this.floors,
    required this.page,
    required this.totalPages,
    required this.replyCount,
  });
  String title;
  ThreadFloorDto? body;
  List<ThreadFloorDto> floors;
  int page;
  int totalPages;
  int replyCount;
}

class TiebaUserPostDto {
  TiebaUserPostDto({
    required this.threadId,
    required this.postId,
    required this.title,
    required this.excerpt,
    required this.time,
    required this.forumId,
    required this.forumName,
    required this.replyCount,
    required this.isReply,
    required this.imageUrls,
  });
  int threadId;
  int postId;
  String title;
  String excerpt;
  String time;
  int forumId;
  String forumName;
  int replyCount;
  bool isReply;
  List<String> imageUrls;
}

class TiebaUserProfileDto {
  TiebaUserProfileDto({
    required this.uid,
    required this.username,
    required this.nickname,
    required this.avatarUrl,
    required this.intro,
    required this.fans,
    required this.concerned,
    required this.posts,
    required this.threads,
    required this.replies,
  });
  int uid;
  String username;
  String nickname;
  String avatarUrl;
  String intro;
  int fans;
  int concerned;
  int posts;
  List<TiebaUserPostDto> threads;
  List<TiebaUserPostDto> replies;
}

class TiebaImageRequestDto {
  TiebaImageRequestDto({
    required this.url,
    required this.threadId,
    required this.postId,
    required this.forumId,
    required this.forumName,
    required this.imageIndex,
    required this.seeOriginalPosterOnly,
  });
  String url;
  int threadId;
  int postId;
  int forumId;
  String forumName;
  int imageIndex;
  bool seeOriginalPosterOnly;
}

class UpdateReleaseDto {
  UpdateReleaseDto({
    required this.version,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.assetName,
    required this.assetSize,
    required this.assetUrl,
    required this.assetSha256,
    required this.prerelease,
  });
  String version;
  String tagName;
  String title;
  String notes;
  String pageUrl;
  String? assetName;
  int? assetSize;
  String? assetUrl;
  String? assetSha256;
  bool prerelease;
}

class NativeEventDto {
  NativeEventDto({
    required this.source,
    required this.stage,
    required this.message,
    required this.progress,
    required this.timestampMillis,
  });
  String source;
  String stage;
  String? message;
  double? progress;
  int timestampMillis;
}

@HostApi()
abstract class WebVpnHostApi {
  NativeCapabilities getCapabilities();
  @async
  WebVpnSessionDto initialize();
  @async
  WebVpnSessionDto refreshCaptcha();
  @async
  WebVpnSessionDto login(LoginRequestDto request);
  @async
  WebVpnSessionDto selectSavedAccount(String username);
  @async
  WebVpnSessionDto forgetSavedAccount(String username);
  @async
  WebVpnSessionDto revalidate();
  @async
  WebVpnSessionDto logout();
}

@HostApi()
abstract class AcademicHostApi {
  @async
  WebVpnSessionDto initialize(String webVpnUsername);
  @async
  WebVpnSessionDto refreshCaptcha();
  @async
  WebVpnSessionDto login(LoginRequestDto request);
  @async
  List<AcademicTermDto> loadTerms();
  @async
  List<CourseGradeDto> loadGrades(String term, bool bestOnly);
  @async
  TimetableDto loadTimetable(String? term);
  @async
  List<SelectedCourseDto> loadSelectionResults(String term);
  @async
  List<EvaluationBatchDto> loadEvaluationBatches();
  @async
  List<EvaluationCourseDto> loadEvaluationCourses(String path);
  @async
  EvaluationFormDto loadEvaluationForm(String path);
  @async
  bool saveEvaluation(
    EvaluationFormDto form,
    List<EvaluationAnswerDto> answers,
    String suggestion,
    bool submit,
  );
  @async
  String prepareWebPage(String path);
  @async
  bool logout();
}

@HostApi()
abstract class TiebaHostApi {
  @async
  TiebaAccountDto? currentAccount();
  @async
  TiebaAccountDto completeWebLogin(String cookieHeader);
  @async
  TiebaAccountDto refreshAccount();
  @async
  bool logout();
  @async
  ForumPageDto loadForum(
    String forumName,
    int page,
    String sort,
    bool goodOnly,
  );
  @async
  ForumPageDto search(String forumName, String keyword, int page);
  @async
  ThreadPageDto loadThread(
    String threadId,
    int forumId,
    String forumName,
    int page,
    String sort,
    bool onlyOriginalPoster,
  );
  @async
  FloorReplyPageDto loadFloorReplies(String threadId, String postId, int page);
  @async
  TiebaUserProfileDto loadUserProfile(int uid);
  @async
  String loadForumRule(int forumId);
  @async
  String sign(String forumId, String forumName);
  @async
  String followForum(String forumId, String forumName);
  @async
  String resolveOriginalImage(TiebaImageRequestDto request);
  @async
  bool launchOfficialReply(int threadId, int? postId);
}

@HostApi()
abstract class UpdateHostApi {
  @async
  UpdateReleaseDto? check(bool includePrereleases);
  @async
  bool startDownload(UpdateReleaseDto release);
  @async
  bool cancelDownload();
  @async
  bool installDownloaded();
  @async
  List<String> checkAccelerators(List<String> urls);
}

@HostApi()
abstract class SettingsHostApi {
  @async
  bool setThemedIcon(bool enabled);
}

@HostApi()
abstract class RuntimeLogHostApi {
  @async
  String exportLog();
  @async
  bool clearLog();
}

@EventChannelApi()
abstract class NativeEventChannelApi {
  NativeEventDto events();
}
