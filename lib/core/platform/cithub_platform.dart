import '../logging/runtime_log.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/cithub_api.g.dart';
import '../utils/request_queue.dart';
import '../native/cithub_api.g.dart' as native;

abstract interface class CithubPlatform {
  Future<String?> readAiApiKey();
  Future<bool> writeAiApiKey(String value);
  Future<bool> deleteAiApiKey();
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
  Future<List<AcademicTermDto>> loadSelectionTerms();
  Future<WebVpnSessionDto> selectSavedAcademicAccount(String username);
  Future<WebVpnSessionDto> forgetSavedAcademicAccount(String username);
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

/// One WebVPN session future shared by the Academic and Mine tabs.
final webVpnSessionProvider = StateProvider<Future<WebVpnSessionDto>>(
  (ref) => ref.read(cithubPlatformProvider).initializeWebVpn(),
);

class PigeonCithubPlatform implements CithubPlatform {
  final _aiSecrets = AiSecretHostApi();
  @override
  Future<String?> readAiApiKey() => RuntimeLog.trace(
    'native',
    'readApiKey',
    [],
    () => _aiSecrets.readApiKey(),
  );
  @override
  Future<bool> writeAiApiKey(String value) => RuntimeLog.trace(
    'native',
    'writeApiKey',
    [value],
    () => _aiSecrets.writeApiKey(value),
  );
  @override
  Future<bool> deleteAiApiKey() => RuntimeLog.trace(
    'native',
    'deleteApiKey',
    [],
    () => _aiSecrets.deleteApiKey(),
  );
  final _webVpn = WebVpnHostApi();
  final _academic = AcademicHostApi();
  final _tieba = TiebaHostApi();
  final _update = UpdateHostApi();
  final _settings = SettingsHostApi();
  final _logs = RuntimeLogHostApi();
  late final Stream<NativeEventDto> _events = native.events().map((event) {
    RuntimeLog.event('native-event', 'received', event);
    return event;
  }).asBroadcastStream();

  @override
  Future<NativeCapabilities> capabilities() => RuntimeLog.trace(
    'native',
    'getCapabilities',
    [],
    () => _webVpn.getCapabilities(),
  );
  @override
  Future<WebVpnSessionDto> initializeWebVpn() =>
      RuntimeLog.trace('native', 'initialize', [], () => _webVpn.initialize());
  @override
  Future<WebVpnSessionDto> loginWebVpn(LoginRequestDto request) =>
      RuntimeLog.trace('native', 'login', [
        request,
      ], () => _webVpn.login(request));
  @override
  Future<WebVpnSessionDto> refreshWebVpnCaptcha() => RuntimeLog.trace(
    'native',
    'refreshCaptcha',
    [],
    () => _webVpn.refreshCaptcha(),
  );
  @override
  Future<WebVpnSessionDto> selectSavedWebVpnAccount(String username) =>
      RuntimeLog.trace('native', 'selectSavedAccount', [
        username,
      ], () => _webVpn.selectSavedAccount(username));
  @override
  Future<WebVpnSessionDto> forgetSavedWebVpnAccount(String username) =>
      RuntimeLog.trace('native', 'forgetSavedAccount', [
        username,
      ], () => _webVpn.forgetSavedAccount(username));
  @override
  Future<WebVpnSessionDto> logoutWebVpn() =>
      RuntimeLog.trace('native', 'logout', [], () => _webVpn.logout());
  @override
  Future<WebVpnSessionDto> initializeAcademic(String username) =>
      RuntimeLog.trace('native', 'initialize', [
        username,
      ], () => _academic.initialize(username));
  @override
  Future<WebVpnSessionDto> refreshAcademicCaptcha() => RuntimeLog.trace(
    'native',
    'refreshCaptcha',
    [],
    () => _academic.refreshCaptcha(),
  );
  @override
  Future<WebVpnSessionDto> loginAcademic(LoginRequestDto request) =>
      RuntimeLog.trace('native', 'login', [
        request,
      ], () => _academic.login(request));
  @override
  Future<bool> logoutAcademic() =>
      RuntimeLog.trace('native', 'logout', [], () => _academic.logout());
  @override
  Future<List<AcademicTermDto>> loadAcademicTerms() =>
      RuntimeLog.trace('native', 'loadTerms', [], () => _academic.loadTerms());
  @override
  Future<List<AcademicTermDto>> loadSelectionTerms() => RuntimeLog.trace(
    'native',
    'loadSelectionTerms',
    [],
    () => _academic.loadSelectionTerms(),
  );
  @override
  Future<WebVpnSessionDto> selectSavedAcademicAccount(String username) =>
      RuntimeLog.trace('native', 'selectSavedAccount', [
        username,
      ], () => _academic.selectSavedAccount(username));
  @override
  Future<WebVpnSessionDto> forgetSavedAcademicAccount(String username) =>
      RuntimeLog.trace('native', 'forgetSavedAccount', [
        username,
      ], () => _academic.forgetSavedAccount(username));
  @override
  Future<List<CourseGradeDto>> loadGrades(
    String term, {
    bool bestOnly = false,
  }) => RuntimeLog.trace('native', 'loadGrades', [
    term,
    bestOnly,
  ], () => _academic.loadGrades(term, bestOnly));
  @override
  Future<TimetableDto> loadTimetable([String? term]) => RuntimeLog.trace(
    'native',
    'loadTimetable',
    [term],
    () => _academic.loadTimetable(term),
  );
  @override
  Future<List<SelectedCourseDto>> loadSelectionResults(String term) =>
      RuntimeLog.trace('native', 'loadSelectionResults', [
        term,
      ], () => _academic.loadSelectionResults(term));
  @override
  Future<List<EvaluationBatchDto>> loadEvaluationBatches() => RuntimeLog.trace(
    'native',
    'loadEvaluationBatches',
    [],
    () => _academic.loadEvaluationBatches(),
  );
  @override
  Future<List<EvaluationCourseDto>> loadEvaluationCourses(String path) =>
      RuntimeLog.trace('native', 'loadEvaluationCourses', [
        path,
      ], () => _academic.loadEvaluationCourses(path));
  @override
  Future<EvaluationFormDto> loadEvaluationForm(String path) => RuntimeLog.trace(
    'native',
    'loadEvaluationForm',
    [path],
    () => _academic.loadEvaluationForm(path),
  );
  @override
  Future<bool> saveEvaluation(
    EvaluationFormDto form,
    List<EvaluationAnswerDto> answers,
    String suggestion, {
    required bool submit,
  }) => RuntimeLog.trace('native', 'saveEvaluation', [
    form,
    answers,
    suggestion,
    submit,
  ], () => _academic.saveEvaluation(form, answers, suggestion, submit));
  @override
  Future<String> prepareAcademicWebPage(String path) => RuntimeLog.trace(
    'native',
    'prepareWebPage',
    [path],
    () => _academic.prepareWebPage(path),
  );
  @override
  Future<ForumPageDto> loadForum(
    String name, {
    int page = 1,
    String sort = 'reply',
    bool goodOnly = false,
  }) => RequestQueue.tieba.run(
    'forum:$name:$page:$sort:$goodOnly',
    () => RuntimeLog.trace('native', 'loadForum', [
      name,
      page,
      sort,
      goodOnly,
    ], () => _tieba.loadForum(name, page, sort, goodOnly)),
  );
  @override
  Future<ForumPageDto> searchForum(
    String name,
    String keyword, {
    int page = 1,
  }) => RequestQueue.tieba.run(
    'search:$name:$keyword:$page',
    () => RuntimeLog.trace('native', 'search', [
      name,
      keyword,
      page,
    ], () => _tieba.search(name, keyword, page)),
  );
  @override
  Future<ThreadPageDto> loadThread(
    String threadId,
    int forumId,
    String forumName, {
    int page = 1,
    String sort = 'asc',
    bool onlyOriginalPoster = false,
  }) => RequestQueue.tieba.run(
    'thread:$threadId:$page:$sort:$onlyOriginalPoster',
    () => RuntimeLog.trace(
      'native',
      'loadThread',
      [threadId, forumId, forumName, page, sort, onlyOriginalPoster],
      () => _tieba.loadThread(
        threadId,
        forumId,
        forumName,
        page,
        sort,
        onlyOriginalPoster,
      ),
    ),
  );
  @override
  Future<FloorReplyPageDto> loadFloorReplies(
    String threadId,
    String postId, {
    int page = 1,
  }) => RequestQueue.tieba.run(
    'replies:$threadId:$postId:$page',
    () => RuntimeLog.trace('native', 'loadFloorReplies', [
      threadId,
      postId,
      page,
    ], () => _tieba.loadFloorReplies(threadId, postId, page)),
  );
  @override
  Future<TiebaUserProfileDto> loadTiebaUserProfile(int uid) => RuntimeLog.trace(
    'native',
    'loadUserProfile',
    [uid],
    () => _tieba.loadUserProfile(uid),
  );
  @override
  Future<String> resolveOriginalImage(TiebaImageRequestDto request) =>
      RuntimeLog.trace('native', 'resolveOriginalImage', [
        request,
      ], () => _tieba.resolveOriginalImage(request));
  @override
  Future<TiebaAccountDto?> currentTiebaAccount() => RuntimeLog.trace(
    'native',
    'currentAccount',
    [],
    () => _tieba.currentAccount(),
  );
  @override
  Future<TiebaAccountDto> completeTiebaWebLogin() => RuntimeLog.trace(
    'native',
    'completeWebLogin',
    [''],
    () => _tieba.completeWebLogin(''),
  );
  @override
  Future<TiebaAccountDto> refreshTiebaAccount() => RuntimeLog.trace(
    'native',
    'refreshAccount',
    [],
    () => _tieba.refreshAccount(),
  );
  @override
  Future<bool> logoutTieba() =>
      RuntimeLog.trace('native', 'logout', [], () => _tieba.logout());
  @override
  Future<String> loadForumRule(int forumId) => RuntimeLog.trace(
    'native',
    'loadForumRule',
    [forumId],
    () => _tieba.loadForumRule(forumId),
  );
  @override
  Future<String> signForum(String forumId, String forumName) =>
      RuntimeLog.trace('native', 'sign', [
        forumId,
        forumName,
      ], () => _tieba.sign(forumId, forumName));
  @override
  Future<String> followForum(String forumId, String forumName) =>
      RuntimeLog.trace('native', 'followForum', [
        forumId,
        forumName,
      ], () => _tieba.followForum(forumId, forumName));
  @override
  Future<bool> launchOfficialReply(int threadId, [int? postId]) =>
      RuntimeLog.trace('native', 'launchOfficialReply', [
        threadId,
        postId,
      ], () => _tieba.launchOfficialReply(threadId, postId));
  @override
  Future<UpdateReleaseDto?> checkUpdate({bool includePrereleases = false}) =>
      RuntimeLog.trace('native', 'check', [
        includePrereleases,
      ], () => _update.check(includePrereleases));
  @override
  Future<bool> startUpdate(UpdateReleaseDto release) => RuntimeLog.trace(
    'native',
    'startDownload',
    [release],
    () => _update.startDownload(release),
  );
  @override
  Future<bool> cancelUpdate() => RuntimeLog.trace(
    'native',
    'cancelDownload',
    [],
    () => _update.cancelDownload(),
  );
  @override
  Future<bool> installUpdate() => RuntimeLog.trace(
    'native',
    'installDownloaded',
    [],
    () => _update.installDownloaded(),
  );
  @override
  Future<String> exportRuntimeLog() => _logs.exportLog();
  @override
  Future<bool> clearRuntimeLog() => _logs.clearLog();
  @override
  Future<bool> setThemedIcon(bool enabled) => RuntimeLog.trace(
    'native',
    'setThemedIcon',
    [enabled],
    () => _settings.setThemedIcon(enabled),
  );
  @override
  Stream<NativeEventDto> get events => _events;
}

final cithubPlatformProvider = Provider<CithubPlatform>(
  (ref) => PigeonCithubPlatform(),
);
