import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/cithub_api.g.dart';
import '../native/cithub_api.g.dart' as native;

abstract interface class CithubPlatform {
  Future<NativeCapabilities> capabilities();
  Future<WebVpnSessionDto> initializeWebVpn();
  Future<WebVpnSessionDto> loginWebVpn(LoginRequestDto request);
  Future<WebVpnSessionDto> refreshWebVpnCaptcha();
  Future<WebVpnSessionDto> selectSavedWebVpnAccount(String username);
  Future<WebVpnSessionDto> forgetSavedWebVpnAccount(String username);
  Future<WebVpnSessionDto> logoutWebVpn();
  Future<WebVpnSessionDto> initializeAcademic(String webVpnUsername);
  Future<WebVpnSessionDto> refreshAcademicCaptcha();
  Future<WebVpnSessionDto> loginAcademic(LoginRequestDto request);
  Future<bool> logoutAcademic();
  Future<List<AcademicTermDto>> loadAcademicTerms();
  Future<List<CourseGradeDto>> loadGrades(String term, {bool bestOnly = false});
  Future<TimetableDto> loadTimetable([String? term]);
  Future<List<SelectedCourseDto>> loadSelectionResults(String term);
  Future<List<EvaluationBatchDto>> loadEvaluationBatches();
  Future<List<EvaluationCourseDto>> loadEvaluationCourses(String path);
  Future<EvaluationFormDto> loadEvaluationForm(String path);
  Future<bool> saveEvaluation(
    EvaluationFormDto form,
    List<EvaluationAnswerDto> answers,
    String suggestion, {
    required bool submit,
  });
  Future<String> prepareAcademicWebPage(String path);
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  });
  Future<ForumPageDto> searchForum(String name, String keyword, {int page = 1});
  Future<ThreadPageDto> loadThread(
    String threadId,
    int forumId,
    String forumName, {
    int page = 1,
    String sort = 'asc',
    bool onlyOriginalPoster = false,
  });
  Future<FloorReplyPageDto> loadFloorReplies(
    String threadId,
    String postId, {
    int page = 1,
  });
  Future<TiebaUserProfileDto> loadTiebaUserProfile(int uid);
  Future<String> resolveOriginalImage(TiebaImageRequestDto request);
  Future<TiebaAccountDto?> currentTiebaAccount();
  Future<TiebaAccountDto> completeTiebaWebLogin();
  Future<TiebaAccountDto> refreshTiebaAccount();
  Future<bool> logoutTieba();
  Future<String> loadForumRule(int forumId);
  Future<String> signForum(String forumId, String forumName);
  Future<String> followForum(String forumId, String forumName);
  Future<bool> launchOfficialReply(int threadId, [int? postId]);
  Future<UpdateReleaseDto?> checkUpdate({bool includePrereleases = false});
  Future<bool> startUpdate(UpdateReleaseDto release);
  Future<bool> cancelUpdate();
  Future<bool> installUpdate();
  Future<String> exportRuntimeLog();
  Future<bool> clearRuntimeLog();
  Future<bool> setThemedIcon(bool enabled);
  Stream<NativeEventDto> get events;
}

class PigeonCithubPlatform implements CithubPlatform {
  final _webVpn = WebVpnHostApi();
  final _academic = AcademicHostApi();
  final _tieba = TiebaHostApi();
  final _update = UpdateHostApi();
  final _settings = SettingsHostApi();
  final _logs = RuntimeLogHostApi();

  @override
  Future<NativeCapabilities> capabilities() => _webVpn.getCapabilities();
  @override
  Future<WebVpnSessionDto> initializeWebVpn() => _webVpn.initialize();
  @override
  Future<WebVpnSessionDto> loginWebVpn(LoginRequestDto request) =>
      _webVpn.login(request);
  @override
  Future<WebVpnSessionDto> refreshWebVpnCaptcha() => _webVpn.refreshCaptcha();
  @override
  Future<WebVpnSessionDto> selectSavedWebVpnAccount(String username) =>
      _webVpn.selectSavedAccount(username);
  @override
  Future<WebVpnSessionDto> forgetSavedWebVpnAccount(String username) =>
      _webVpn.forgetSavedAccount(username);
  @override
  Future<WebVpnSessionDto> logoutWebVpn() => _webVpn.logout();
  @override
  Future<WebVpnSessionDto> initializeAcademic(String username) =>
      _academic.initialize(username);
  @override
  Future<WebVpnSessionDto> refreshAcademicCaptcha() =>
      _academic.refreshCaptcha();
  @override
  Future<WebVpnSessionDto> loginAcademic(LoginRequestDto request) =>
      _academic.login(request);
  @override
  Future<bool> logoutAcademic() => _academic.logout();
  @override
  Future<List<AcademicTermDto>> loadAcademicTerms() => _academic.loadTerms();
  @override
  Future<List<CourseGradeDto>> loadGrades(
    String term, {
    bool bestOnly = false,
  }) => _academic.loadGrades(term, bestOnly);
  @override
  Future<TimetableDto> loadTimetable([String? term]) =>
      _academic.loadTimetable(term);
  @override
  Future<List<SelectedCourseDto>> loadSelectionResults(String term) =>
      _academic.loadSelectionResults(term);
  @override
  Future<List<EvaluationBatchDto>> loadEvaluationBatches() =>
      _academic.loadEvaluationBatches();
  @override
  Future<List<EvaluationCourseDto>> loadEvaluationCourses(String path) =>
      _academic.loadEvaluationCourses(path);
  @override
  Future<EvaluationFormDto> loadEvaluationForm(String path) =>
      _academic.loadEvaluationForm(path);
  @override
  Future<bool> saveEvaluation(
    EvaluationFormDto form,
    List<EvaluationAnswerDto> answers,
    String suggestion, {
    required bool submit,
  }) => _academic.saveEvaluation(form, answers, suggestion, submit);
  @override
  Future<String> prepareAcademicWebPage(String path) =>
      _academic.prepareWebPage(path);
  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) => _tieba.loadForum(name, page, sort, goodOnly);
  @override
  Future<ForumPageDto> searchForum(
    String name,
    String keyword, {
    int page = 1,
  }) => _tieba.search(name, keyword, page);
  @override
  Future<ThreadPageDto> loadThread(
    String threadId,
    int forumId,
    String forumName, {
    int page = 1,
    String sort = 'asc',
    bool onlyOriginalPoster = false,
  }) => _tieba.loadThread(
    threadId,
    forumId,
    forumName,
    page,
    sort,
    onlyOriginalPoster,
  );
  @override
  Future<FloorReplyPageDto> loadFloorReplies(
    String threadId,
    String postId, {
    int page = 1,
  }) => _tieba.loadFloorReplies(threadId, postId, page);
  @override
  Future<TiebaUserProfileDto> loadTiebaUserProfile(int uid) =>
      _tieba.loadUserProfile(uid);
  @override
  Future<String> resolveOriginalImage(TiebaImageRequestDto request) =>
      _tieba.resolveOriginalImage(request);
  @override
  Future<TiebaAccountDto?> currentTiebaAccount() => _tieba.currentAccount();
  @override
  Future<TiebaAccountDto> completeTiebaWebLogin() =>
      _tieba.completeWebLogin('');
  @override
  Future<TiebaAccountDto> refreshTiebaAccount() => _tieba.refreshAccount();
  @override
  Future<bool> logoutTieba() => _tieba.logout();
  @override
  Future<String> loadForumRule(int forumId) => _tieba.loadForumRule(forumId);
  @override
  Future<String> signForum(String forumId, String forumName) =>
      _tieba.sign(forumId, forumName);
  @override
  Future<String> followForum(String forumId, String forumName) =>
      _tieba.followForum(forumId, forumName);
  @override
  Future<bool> launchOfficialReply(int threadId, [int? postId]) =>
      _tieba.launchOfficialReply(threadId, postId);
  @override
  Future<UpdateReleaseDto?> checkUpdate({bool includePrereleases = false}) =>
      _update.check(includePrereleases);
  @override
  Future<bool> startUpdate(UpdateReleaseDto release) =>
      _update.startDownload(release);
  @override
  Future<bool> cancelUpdate() => _update.cancelDownload();
  @override
  Future<bool> installUpdate() => _update.installDownloaded();
  @override
  Future<String> exportRuntimeLog() => _logs.exportLog();
  @override
  Future<bool> clearRuntimeLog() => _logs.clearLog();
  @override
  Future<bool> setThemedIcon(bool enabled) => _settings.setThemedIcon(enabled);
  @override
  Stream<NativeEventDto> get events => native.events();
}

final cithubPlatformProvider = Provider<CithubPlatform>(
  (ref) => PigeonCithubPlatform(),
);
