import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/native/cithub_api.g.dart';
import '../../core/platform/cithub_platform.dart';
import '../../core/settings/app_settings.dart';
import '../../core/utils/pagination.dart';

class TiebaScreen extends ConsumerStatefulWidget {
  const TiebaScreen({super.key});

  @override
  ConsumerState<TiebaScreen> createState() => _TiebaScreenState();
}

class _TiebaScreenState extends ConsumerState<TiebaScreen>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
  final _threads = <ForumThreadDto>[];
  ForumSummaryDto? _forum;
  String _forumName = defaultTiebaHomeForum;
  String _sort = 'reply';
  bool _goodOnly = false;
  bool _loading = false;
  bool _hasMore = true;
  int _page = 0;
  int _generation = 0;
  Object? _error;
  StreamSubscription<NativeEventDto>? _nativeEventSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _forumName = ref.read(appSettingsProvider).tiebaHomeForumName;
    _scrollController.addListener(_onScroll);
    _nativeEventSubscription = ref
        .read(cithubPlatformProvider)
        .events
        .where((event) => event.source == 'tieba')
        .listen((event) {
          if (!mounted ||
              (event.stage != 'signedIn' && event.stage != 'signedOut')) {
            return;
          }
          unawaited(_resetAndLoad());
        });
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetAndLoad());
  }

  @override
  void dispose() {
    _nativeEventSubscription?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 520) _loadNext();
  }

  Future<void> _resetAndLoad({String? forumName}) async {
    if (forumName != null) _forumName = forumName;
    _generation++;
    setState(() {
      _forum = null;
      _threads.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final requestedPage = _page + 1;
    try {
      final result = await ref
          .read(cithubPlatformProvider)
          .loadForum(
            _forumName,
            page: requestedPage,
            sort: _sort,
            goodOnly: _goodOnly,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _forum = result.forum;
        _page = result.page > 0 ? result.page : requestedPage;
        _hasMore = result.hasMore;
        appendUniqueBy(_threads, result.threads, (item) => item.id);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _followOrSign() async {
    final forum = _forum;
    if (forum == null || forum.signed) return;
    try {
      final platform = ref.read(cithubPlatformProvider);
      final message = !forum.isFollowed
          ? await platform.followForum(forum.id, forum.name)
          : await platform.signForum(forum.id, forum.name);
      if (!mounted) return;
      setState(() {
        if (!forum.isFollowed) {
          forum.isFollowed = true;
        } else {
          forum.signed = true;
          forum.signedDays = forum.signedDays + 1;
        }
      });
      _message(context, message);
    } catch (error) {
      if (mounted) _message(context, '操作失败：$error');
    }
  }

  String get _forumActionLabel {
    final forum = _forum;
    if (forum == null) return '';
    if (!forum.isFollowed) return '关注';
    if (!forum.signed) return '签到';
    return forum.signedDays > 0 ? '已签${forum.signedDays}天' : '已签到';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<String>(
      appSettingsProvider.select((value) => value.tiebaHomeForumName),
      (previous, next) {
        if (next != _forumName) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _resetAndLoad(forumName: next),
          );
        }
      },
    );

    final pinned = _threads.where((item) => item.isTop).toList();
    final regular = _threads.where((item) => !item.isTop).toList();
    return RefreshIndicator(
      onRefresh: _resetAndLoad,
      child: CustomScrollView(
        key: const PageStorageKey('tieba-scroll'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: 72,
            titleSpacing: 20,
            title: Text(
              displayTiebaForumName(_forumName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                key: const Key('tieba-search'),
                tooltip: '吧内搜索',
                onPressed: () => showSearch<void>(
                  context: context,
                  delegate: _ForumSearchDelegate(
                    ref.read(cithubPlatformProvider),
                    _forumName,
                  ),
                ),
                icon: const Icon(Icons.search),
              ),
              if (_forum != null)
                TextButton(
                  key: const Key('tieba-follow-sign'),
                  onPressed: _forum!.signed ? null : _followOrSign,
                  child: Text(_forumActionLabel),
                ),
              PopupMenuButton<String>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (value) {
                  if (value == _sort) return;
                  _sort = value;
                  _resetAndLoad();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reply', child: Text('按回复时间')),
                  PopupMenuItem(value: 'post', child: Text('按发帖时间')),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('最新'),
                    selected: !_goodOnly,
                    onSelected: (_) {
                      if (_goodOnly) {
                        _goodOnly = false;
                        _resetAndLoad();
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('精品'),
                    selected: _goodOnly,
                    onSelected: (_) {
                      if (!_goodOnly) {
                        _goodOnly = true;
                        _resetAndLoad();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_forum case final forum?)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              sliver: SliverToBoxAdapter(
                child: _ForumNoticeRows(forum: forum, pinned: pinned),
              ),
            ),
          if (_error != null && _threads.isEmpty)
            _ErrorSliver(error: _error, onRetry: _loadNext)
          else if (_loading && _threads.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (regular.isEmpty && !_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('暂无帖子')),
            )
          else
            SliverList.separated(
              itemCount: regular.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) => _ThreadTile(
                thread: regular[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ThreadScreen(thread: regular[index]),
                  ),
                ),
              ),
            ),
          if (_threads.isNotEmpty)
            SliverToBoxAdapter(
              child: _LoadingFooter(
                loading: _loading,
                error: _error,
                hasMore: _hasMore,
                onRetry: _loadNext,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class _ForumNoticeRows extends ConsumerWidget {
  const _ForumNoticeRows({required this.forum, required this.pinned});

  final ForumSummaryDto forum;
  final List<ForumThreadDto> pinned;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      if (forum.forumRuleTitle.isNotEmpty)
        _NoticeRow(
          label: '吧规',
          text: forum.forumRuleTitle,
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(forum.forumRuleTitle),
              content: FutureBuilder<String>(
                future: ref
                    .read(cithubPlatformProvider)
                    .loadForumRule(int.tryParse(forum.id) ?? 0),
                builder: (_, snapshot) => SingleChildScrollView(
                  child: Text(snapshot.data ?? '正在加载…'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
      for (final thread in pinned)
        _NoticeRow(
          label: '置顶',
          text: thread.title,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ThreadScreen(thread: thread)),
          ),
        ),
      if (forum.forumRuleTitle.isNotEmpty || pinned.isNotEmpty)
        const Divider(height: 18),
    ],
  );
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.label, required this.text, this.onTap});

  final String label;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    ),
  );
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onTap});

  final ForumThreadDto thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                url: thread.authorPortrait,
                label: thread.authorNickname,
                radius: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      thread.authorNickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ModeratorBadge(role: thread.authorModeratorRole),
                        Text(
                          thread.lastReplyTime,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text('${thread.replyCount} 回复'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thread.isGood)
                Padding(
                  padding: const EdgeInsets.only(right: 5, top: 2),
                  child: Icon(
                    Icons.workspace_premium,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              Expanded(
                child: Text(
                  thread.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (thread.excerptContent.isNotEmpty ||
              thread.excerpt.isNotEmpty) ...[
            const SizedBox(height: 6),
            _TiebaInlineText(
              content: thread.excerptContent.isNotEmpty
                  ? thread.excerptContent
                  : [_textTiebaContent(thread.excerpt)],
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (thread.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ThreadImagePreview(urls: thread.imageUrls.take(3).toList()),
          ],
          if (thread.viewCount.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${thread.viewCount} 次浏览',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

class _ThreadImagePreview extends StatelessWidget {
  const _ThreadImagePreview({required this.urls});

  final List<String> urls;

  Widget _image(String url, int index) => ClipRRect(
    key: Key('thread-preview-image-$index'),
    borderRadius: BorderRadius.circular(10),
    child: CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      errorWidget: (_, _, _) => const SizedBox.shrink(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return AspectRatio(
        key: const Key('thread-single-image-preview'),
        aspectRatio: 2,
        child: _image(urls.first, 0),
      );
    }
    return SizedBox(
      key: const Key('thread-multi-image-preview'),
      height: 96,
      child: Row(
        children: [
          for (var index = 0; index < urls.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            Expanded(child: _image(urls[index], index)),
          ],
        ],
      ),
    );
  }
}

class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.thread});

  final ForumThreadDto thread;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _scrollController = ScrollController();
  final _floors = <ThreadFloorDto>[];
  ThreadFloorDto? _body;
  bool _onlyAuthor = false;
  String _sort = 'asc';
  bool _loading = false;
  int _page = 0;
  int _totalPages = 1;
  int _replyCount = 0;
  int _generation = 0;
  bool _showScrollToTop = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetAndLoad());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  bool get _hasMore => _page < _totalPages;

  void _onScroll() {
    final showScrollToTop = _scrollController.offset > 240;
    if (showScrollToTop != _showScrollToTop && mounted) {
      setState(() => _showScrollToTop = showScrollToTop);
    }
    if (_scrollController.position.extentAfter < 560) _loadNext();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _resetAndLoad() async {
    _generation++;
    setState(() {
      _body = null;
      _floors.clear();
      _page = 0;
      _totalPages = 1;
      _replyCount = 0;
      _showScrollToTop = false;
      _loading = false;
      _error = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || (_page > 0 && !_hasMore)) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final requestedPage = _page + 1;
    try {
      final result = await ref
          .read(cithubPlatformProvider)
          .loadThread(
            widget.thread.id,
            widget.thread.forumId,
            widget.thread.forumName,
            page: requestedPage,
            sort: _sort,
            onlyOriginalPoster: _onlyAuthor,
          );
      if (!mounted || generation != _generation) return;
      final bodyId = result.body?.postId;
      setState(() {
        _body ??= result.body;
        _page = result.page > 0 ? result.page : requestedPage;
        _totalPages = result.totalPages < _page ? _page : result.totalPages;
        _replyCount = result.replyCount;
        appendUniqueBy(
          _floors,
          result.floors.where((item) => item.postId != bodyId),
          (item) => item.postId,
        );
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 56,
      centerTitle: false,
      titleSpacing: 0,
      title: Text(
        widget.thread.forumName.isEmpty
            ? '贴吧'
            : displayTiebaForumName(widget.thread.forumName),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      ),
      actions: [
        if (_showScrollToTop)
          IconButton(
            tooltip: '回到顶部',
            onPressed: _scrollToTop,
            icon: const Icon(Icons.vertical_align_top),
          ),
        const SizedBox(width: 4),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _resetAndLoad,
      child: CustomScrollView(
        key: Key('thread-${widget.thread.id}'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_error != null && _body == null)
            _ErrorSliver(error: _error, onRetry: _loadNext)
          else if (_body == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SliverToBoxAdapter(
              child: _FloorCard(
                key: const Key('thread-main-floor'),
                threadId: widget.thread.id,
                forumId: widget.thread.forumId,
                forumName: widget.thread.forumName,
                floor: _body!,
                title: widget.thread.title,
                isMain: true,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(
                  key: const Key('thread-body-replies-divider'),
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ThreadControlsDelegate(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        void toggleAuthor() {
                          _onlyAuthor = !_onlyAuthor;
                          _resetAndLoad();
                        }

                        void selectSort(String value) {
                          if (value == _sort) return;
                          _sort = value;
                          _resetAndLoad();
                        }

                        if (constraints.maxWidth < 360) {
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '回复 $_replyCount',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: _onlyAuthor ? '查看全部' : '只看楼主',
                                onPressed: toggleAuthor,
                                icon: Icon(
                                  _onlyAuthor
                                      ? Icons.person
                                      : Icons.person_outline,
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '楼层排序',
                                initialValue: _sort,
                                onSelected: selectSort,
                                icon: const Icon(Icons.sort),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'asc',
                                    child: Text('正序'),
                                  ),
                                  PopupMenuItem(
                                    value: 'desc',
                                    child: Text('倒序'),
                                  ),
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Text(
                              '回复 $_replyCount',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: toggleAuthor,
                              child: Text(_onlyAuthor ? '查看全部' : '只看楼主'),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _sort == 'asc'
                                  ? null
                                  : () => selectSort('asc'),
                              child: const Text('正序'),
                            ),
                            TextButton(
                              onPressed: _sort == 'desc'
                                  ? null
                                  : () => selectSort('desc'),
                              child: const Text('倒序'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: _floors.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) => _FloorCard(
                key: ValueKey('floor-${_floors[index].postId}'),
                threadId: widget.thread.id,
                forumId: widget.thread.forumId,
                forumName: widget.thread.forumName,
                floor: _floors[index],
              ),
            ),
            SliverToBoxAdapter(
              child: _LoadingFooter(
                loading: _loading,
                error: _error,
                hasMore: _hasMore,
                onRetry: _loadNext,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    ),
  );
}

class _ThreadControlsDelegate extends SliverPersistentHeaderDelegate {
  const _ThreadControlsDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 58;
  @override
  double get maxExtent => 58;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(covariant _ThreadControlsDelegate oldDelegate) =>
      oldDelegate.child != child;
}

enum _PostMenuAction { reply, copy }

class _FloorCard extends ConsumerWidget {
  const _FloorCard({
    super.key,
    required this.threadId,
    required this.forumId,
    required this.forumName,
    required this.floor,
    this.title,
    this.isMain = false,
    this.showReplies = true,
  });

  final String threadId;
  final int forumId;
  final String forumName;
  final ThreadFloorDto floor;
  final String? title;
  final bool isMain;
  final bool showReplies;

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_PostMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: _PostMenuAction.reply, child: Text('回复')),
        PopupMenuItem(value: _PostMenuAction.copy, child: Text('复制')),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == _PostMenuAction.copy) {
      await Clipboard.setData(ClipboardData(text: _floorText(floor)));
      if (context.mounted) _message(context, '已复制');
      return;
    }
    final ok = await ref
        .read(cithubPlatformProvider)
        .launchOfficialReply(
          int.tryParse(threadId) ?? 0,
          isMain ? null : int.tryParse(floor.postId),
        );
    if (context.mounted && !ok) _message(context, '未找到百度贴吧客户端');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = floor.replies.take(3).toList();
    return GestureDetector(
      key: Key('floor-menu-${floor.postId}'),
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) =>
          _showMenu(context, ref, details.globalPosition),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, isMain ? 12 : 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: floor.authorId <= 0
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                _TiebaProfileScreen(uid: floor.authorId),
                          ),
                        ),
                  child: _Avatar(
                    url: floor.authorPortrait,
                    label: _displayTiebaName(
                      floor.authorNickname,
                      floor.authorName,
                      floor.authorId,
                    ),
                    radius: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _displayTiebaName(
                                floor.authorNickname,
                                floor.authorName,
                                floor.authorId,
                              ),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (!isMain) Text('${floor.floor} 楼'),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _IdentityBadges(
                              moderatorRole: floor.authorModeratorRole,
                              title: floor.authorTitle,
                              level: floor.authorLevel,
                            ),
                          ),
                          if (floor.isOriginalPoster) ...[
                            const SizedBox(width: 8),
                            const _SmallBadge(text: '楼主'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          floor.time,
                          if (!isMain) '第 ${floor.floor} 楼',
                          if (floor.authorIp.isNotEmpty)
                            'IP属地 ${floor.authorIp}',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(left: isMain ? 0 : 46),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title?.isNotEmpty == true) ...[
                    const SizedBox(height: 18),
                    Text(
                      title!,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _TiebaContent(
                    content: floor.content,
                    threadId: threadId,
                    postId: floor.postId,
                    forumId: forumId,
                    forumName: forumName,
                  ),
                  if (showReplies &&
                      (replies.isNotEmpty || floor.replyCount > 0)) ...[
                    const SizedBox(height: 14),
                    _FloorReplyPreview(
                      threadId: threadId,
                      forumId: forumId,
                      forumName: forumName,
                      floor: floor,
                      replies: replies,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FloorReplyPreview extends StatelessWidget {
  const _FloorReplyPreview({
    required this.threadId,
    required this.forumId,
    required this.forumName,
    required this.floor,
    required this.replies,
  });

  final String threadId;
  final int forumId;
  final String forumName;
  final ThreadFloorDto floor;
  final List<FloorReplyDto> replies;

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FloorRepliesScreen(
        threadId: threadId,
        forumId: forumId,
        forumName: forumName,
        parent: floor,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('floor-reply-preview'),
    width: double.infinity,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reply in replies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _TiebaInlineText(
                    content: reply.content,
                    prefix:
                        '${_displayTiebaName(reply.authorNickname, reply.authorName, reply.authorId)}：',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (floor.replyCount > 1 && floor.replyCount > replies.length)
                Text(
                  '查看全部 ${floor.replyCount} 条回复',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class FloorRepliesScreen extends ConsumerStatefulWidget {
  const FloorRepliesScreen({
    super.key,
    required this.threadId,
    required this.forumId,
    required this.forumName,
    required this.parent,
  });

  final String threadId;
  final int forumId;
  final String forumName;
  final ThreadFloorDto parent;

  @override
  ConsumerState<FloorRepliesScreen> createState() => _FloorRepliesScreenState();
}

class _FloorRepliesScreenState extends ConsumerState<FloorRepliesScreen> {
  final _scrollController = ScrollController();
  final _replies = <FloorReplyDto>[];
  int _page = 0;
  int _totalPages = 1;
  int _totalReplies = 0;
  int _generation = 0;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _totalReplies = widget.parent.replyCount;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNext());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  bool get _hasMore => _page < _totalPages;

  void _onScroll() {
    if (_scrollController.position.extentAfter < 420) _loadNext();
  }

  Future<void> _refresh() async {
    _generation++;
    setState(() {
      _replies.clear();
      _page = 0;
      _totalPages = 1;
      _totalReplies = widget.parent.replyCount;
      _error = null;
      _loading = false;
    });
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || (_page > 0 && !_hasMore)) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final requestedPage = _page + 1;
    try {
      final result = await ref
          .read(cithubPlatformProvider)
          .loadFloorReplies(
            widget.threadId,
            widget.parent.postId,
            page: requestedPage,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = result.page > 0 ? result.page : requestedPage;
        _totalPages = result.totalPages < _page ? _page : result.totalPages;
        _totalReplies = result.totalReplies;
        appendUniqueBy(_replies, result.replies, (item) => item.id);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _replyAt(
    BuildContext context,
    WidgetRef ref,
    FloorReplyDto reply,
    Offset position,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_PostMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: _PostMenuAction.reply, child: Text('回复')),
        PopupMenuItem(value: _PostMenuAction.copy, child: Text('复制')),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == _PostMenuAction.copy) {
      await Clipboard.setData(ClipboardData(text: _replyText(reply)));
      if (context.mounted) _message(context, '已复制');
      return;
    }
    final ok = await ref
        .read(cithubPlatformProvider)
        .launchOfficialReply(
          int.tryParse(widget.threadId) ?? 0,
          int.tryParse(widget.parent.postId),
        );
    if (context.mounted && !ok) _message(context, '未找到百度贴吧客户端');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.parent.floor} 楼的回复'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _FloorCard(
              threadId: widget.threadId,
              forumId: widget.forumId,
              forumName: widget.forumName,
              floor: widget.parent,
              isMain: false,
              showReplies: false,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                '$_totalReplies 条回复',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          if (_error != null && _replies.isEmpty)
            _ErrorSliver(error: _error, onRetry: _loadNext)
          else
            SliverList.separated(
              itemCount: _replies.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final reply = _replies[index];
                return GestureDetector(
                  key: Key('floor-reply-menu-${reply.id}'),
                  behavior: HitTestBehavior.opaque,
                  onLongPressStart: (details) =>
                      _replyAt(context, ref, reply, details.globalPosition),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Avatar(
                          url: reply.authorPortrait,
                          label: _displayTiebaName(
                            reply.authorNickname,
                            reply.authorName,
                            reply.authorId,
                          ),
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayTiebaName(
                                  reply.authorNickname,
                                  reply.authorName,
                                  reply.authorId,
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              _IdentityBadges(
                                moderatorRole: reply.authorModeratorRole,
                                title: reply.authorTitle,
                                level: reply.authorLevel,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  reply.time,
                                  if (reply.authorIp.isNotEmpty)
                                    'IP属地 ${reply.authorIp}',
                                ].join(' · '),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 10),
                              _TiebaInlineText(content: reply.content),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          SliverToBoxAdapter(
            child: _LoadingFooter(
              loading: _loading,
              error: _error,
              hasMore: _hasMore,
              onRetry: _loadNext,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TiebaContent extends ConsumerWidget {
  const _TiebaContent({
    required this.content,
    required this.threadId,
    required this.postId,
    required this.forumId,
    required this.forumName,
  });

  final List<TiebaContentDto> content;
  final String threadId;
  final String postId;
  final int forumId;
  final String forumName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = content
        .where((item) => item.kind == 'image' && item.url.isNotEmpty)
        .toList();
    final imageRequests = List.generate(images.length, (index) {
      final image = images[index];
      return TiebaImageRequestDto(
        url: image.originalUrl.isEmpty ? image.url : image.originalUrl,
        threadId: int.tryParse(threadId) ?? 0,
        postId: int.tryParse(postId) ?? 0,
        forumId: forumId,
        forumName: forumName,
        imageIndex: index + 1,
        seeOriginalPosterOnly: false,
      );
    });
    var imageIndex = 0;
    final blocks = <Widget>[];
    final inlineContent = <TiebaContentDto>[];

    void flushInlineContent() {
      if (inlineContent.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _TiebaInlineText(
            content: List.of(inlineContent),
            selectable: true,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.55,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
      inlineContent.clear();
    }

    for (final item in content) {
      if (item.kind != 'image' || item.url.isEmpty) {
        if (item.text.isNotEmpty || item.kind == 'emoticon') {
          inlineContent.add(item);
        }
        continue;
      }
      flushInlineContent();
      final currentIndex = imageIndex;
      imageIndex++;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: InkWell(
            key: Key('tieba-floor-image-$currentIndex'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _TiebaImageScreen(
                    previewUrls: images.map((image) => image.url).toList(),
                    requests: imageRequests,
                    initialIndex: currentIndex,
                    platform: ref.read(cithubPlatformProvider),
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: item.url,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                placeholder: (_, _) => const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) => const SizedBox(
                  height: 80,
                  child: Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
          ),
        ),
      );
    }
    flushInlineContent();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }
}

class _TiebaInlineText extends StatelessWidget {
  const _TiebaInlineText({
    required this.content,
    this.prefix = '',
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.selectable = false,
    this.style,
  });

  final List<TiebaContentDto> content;
  final String prefix;
  final int? maxLines;
  final TextOverflow overflow;
  final bool selectable;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        style ??
        Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurface);
    final span = TextSpan(
      style: effectiveStyle,
      children: _tiebaInlineSpans(content, prefix: prefix),
    );
    if (selectable) return SelectableText.rich(span);
    return RichText(
      text: span,
      maxLines: maxLines,
      overflow: overflow,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}

List<InlineSpan> _tiebaInlineSpans(
  List<TiebaContentDto> content, {
  String prefix = '',
}) {
  final spans = <InlineSpan>[if (prefix.isNotEmpty) TextSpan(text: prefix)];
  final emoticonCounts = <String, int>{};
  var shouldTrimReplyColon = prefix.isNotEmpty;

  void addEmoticon(
    String rawName, {
    String emoticonId = '',
    String? fallbackText,
  }) {
    final name = rawName
        .replaceFirst(RegExp(r'^#[（(]'), '')
        .replaceFirst(RegExp(r'[)）]$'), '');
    final parsedId = int.tryParse(
      RegExp(r'(\d+)$').firstMatch(emoticonId)?.group(1) ?? '',
    );
    final asset =
        parsedId != null && _tiebaBundledEmoticonIds.contains(parsedId)
        ? _tiebaEmoticonAsset(parsedId)
        : _tiebaEmoticonAssets[name];
    if (asset == null) {
      spans.add(TextSpan(text: fallbackText ?? '#($name)'));
      return;
    }
    final count = (emoticonCounts[name] ?? 0) + 1;
    emoticonCounts[name] = count;
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Image.asset(
          asset,
          key: Key(
            count == 1 ? 'tieba-emoticon-$name' : 'tieba-emoticon-$name-$count',
          ),
          width: 24,
          height: 24,
          semanticLabel: '贴吧表情：$name',
          errorBuilder: (_, _, _) => Text('#($name)'),
        ),
      ),
    );
  }

  void addText(String text) {
    final normalized = shouldTrimReplyColon
        ? text.replaceFirst(RegExp(r'^\s*[：:]\s*'), '')
        : text;
    shouldTrimReplyColon = false;
    var offset = 0;
    for (final match in RegExp(
      r'#[（(]([^()（）\n]{1,16})[)）]',
    ).allMatches(normalized)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: normalized.substring(offset, match.start)));
      }
      addEmoticon(match.group(1)!, fallbackText: match.group(0));
      offset = match.end;
    }
    if (offset < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(offset)));
    }
  }

  for (final item in content) {
    if (item.kind == 'emoticon') {
      addEmoticon(item.text, emoticonId: item.emoticonId);
    } else if (item.text.isNotEmpty) {
      addText(item.text);
    }
  }
  return spans;
}

class _IdentityBadges extends StatelessWidget {
  const _IdentityBadges({
    required this.moderatorRole,
    required this.title,
    required this.level,
  });

  final TiebaModeratorRole moderatorRole;
  final String title;
  final int level;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      if (moderatorRole != TiebaModeratorRole.none)
        _ModeratorBadge(role: moderatorRole),
      if (title.isNotEmpty) _SmallBadge(text: title),
      if (level > 0) _SmallBadge(text: 'Lv.$level'),
    ],
  );
}

class _ModeratorBadge extends StatelessWidget {
  const _ModeratorBadge({required this.role});

  final TiebaModeratorRole role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      TiebaModeratorRole.owner => '吧主',
      TiebaModeratorRole.assistant => '小吧主',
      TiebaModeratorRole.none => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();
    if (role == TiebaModeratorRole.owner ||
        role == TiebaModeratorRole.assistant) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return _SmallBadge(
        text: label,
        backgroundColor: dark
            ? const Color(0xff73304f)
            : const Color(0xffffd8e7),
        foregroundColor: dark
            ? const Color(0xffffd8e7)
            : const Color(0xff6f123d),
      );
    }
    return _SmallBadge(text: label);
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({
    required this.text,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String text;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color:
          backgroundColor ?? Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: foregroundColor),
    ),
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.label, required this.radius});

  final String url;
  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundImage: url.isEmpty ? null : CachedNetworkImageProvider(url),
    child: url.isEmpty ? Text(_initial(label)) : null,
  );
}

class _TiebaProfileScreen extends ConsumerWidget {
  const _TiebaProfileScreen({required this.uid});

  final int uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('用户资料')),
    body: FutureBuilder<TiebaUserProfileDto>(
      future: ref.read(cithubPlatformProvider).loadTiebaUserProfile(uid),
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('资料加载失败：${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snapshot.requireData;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: _Avatar(
                url: profile.avatarUrl,
                label: profile.nickname,
                radius: 42,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              profile.nickname,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              profile.username,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Text(profile.intro, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            Card(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ProfileMetric(label: '关注', value: profile.concerned),
                  _ProfileMetric(label: '粉丝', value: profile.fans),
                  _ProfileMetric(label: '发帖', value: profile.posts),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _UserPostsSection(
              title: '主题帖',
              emptyLabel: '暂无公开主题帖',
              posts: profile.threads,
              profile: profile,
            ),
            const SizedBox(height: 12),
            _UserPostsSection(
              title: '回复',
              emptyLabel: '暂无公开回复',
              posts: profile.replies,
              profile: profile,
            ),
          ],
        );
      },
    ),
  );
}

class _UserPostsSection extends StatelessWidget {
  const _UserPostsSection({
    required this.title,
    required this.emptyLabel,
    required this.posts,
    required this.profile,
  });

  final String title;
  final String emptyLabel;
  final List<TiebaUserPostDto> posts;
  final TiebaUserProfileDto profile;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(emptyLabel),
          )
        else
          for (var index = 0; index < posts.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              title: Text(
                posts[index].title.isEmpty ? '未命名主题' : posts[index].title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (posts[index].forumName.isNotEmpty)
                    displayTiebaForumName(posts[index].forumName),
                  if (posts[index].excerpt.isNotEmpty) posts[index].excerpt,
                  if (posts[index].time.isNotEmpty) posts[index].time,
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: posts[index].threadId <= 0
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ThreadScreen(
                          thread: ForumThreadDto(
                            id: '${posts[index].threadId}',
                            title: posts[index].title.isEmpty
                                ? '未命名主题'
                                : posts[index].title,
                            excerpt: posts[index].excerpt,
                            excerptContent: posts[index].excerpt.isEmpty
                                ? const []
                                : [_textTiebaContent(posts[index].excerpt)],
                            authorName: profile.username,
                            authorNickname: profile.nickname,
                            authorId: profile.uid,
                            authorPortrait: profile.avatarUrl,
                            replyCount: '${posts[index].replyCount}',
                            viewCount: '',
                            lastReplyTime: posts[index].time,
                            isTop: false,
                            isGood: false,
                            imageUrls: posts[index].imageUrls,
                            forumId: posts[index].forumId,
                            forumName: posts[index].forumName,
                            authorModeratorRole: TiebaModeratorRole.none,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
      ],
    ),
  );
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Column(children: [Text('$value'), Text(label)]),
  );
}

class _TiebaImageScreen extends StatefulWidget {
  const _TiebaImageScreen({
    required this.previewUrls,
    required this.requests,
    required this.initialIndex,
    required this.platform,
  }) : assert(previewUrls.length == requests.length),
       assert(previewUrls.length > 0),
       assert(initialIndex >= 0 && initialIndex < previewUrls.length);

  final List<String> previewUrls;
  final List<TiebaImageRequestDto> requests;
  final int initialIndex;
  final CithubPlatform platform;

  @override
  State<_TiebaImageScreen> createState() => _TiebaImageScreenState();
}

class _TiebaImageScreenState extends State<_TiebaImageScreen> {
  late final PageController _pageController;
  late final List<String> _urls;
  late final List<Future<String>?> _resolutionFutures;
  late int _index;
  bool _currentImageZoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
    _urls = List.of(widget.previewUrls);
    _resolutionFutures = List.filled(widget.previewUrls.length, null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveAround(_index));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String> _resolve(int index) {
    return _resolutionFutures[index] ??= () async {
      try {
        final resolved = await widget.platform.resolveOriginalImage(
          widget.requests[index],
        );
        if (resolved.isNotEmpty && resolved != _urls[index] && mounted) {
          setState(() => _urls[index] = resolved);
        }
        return resolved.isEmpty ? _urls[index] : resolved;
      } catch (_) {
        return _urls[index];
      }
    }();
  }

  void _resolveAround(int index) {
    for (var candidate = index - 1; candidate <= index + 1; candidate++) {
      if (candidate >= 0 && candidate < _urls.length) _resolve(candidate);
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _currentImageZoomed = false;
    });
    _resolveAround(index);
  }

  Future<void> _save() async {
    try {
      final url = await _resolve(_index);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final path = await FilePicker.saveFile(
        dialogTitle: '保存贴吧图片',
        fileName: 'cithub-${DateTime.now().millisecondsSinceEpoch}.jpg',
        bytes: response.bodyBytes,
      );
      if (mounted && path != null) _message(context, '图片已保存');
    } catch (error) {
      if (mounted) _message(context, '图片保存失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _urls.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(count == 1 ? '原图' : '${_index + 1} / $count'),
        actions: [
          IconButton(
            tooltip: '保存图片',
            onPressed: _save,
            icon: const Icon(Icons.download),
          ),
        ],
      ),
      body: PageView.builder(
        key: const Key('tieba-image-gallery'),
        controller: _pageController,
        physics: _currentImageZoomed
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        itemCount: count,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _FocusedPhotoView(
          url: _urls[index],
          index: index,
          onZoomChanged: index == _index
              ? (zoomed) {
                  if (_currentImageZoomed != zoomed) {
                    setState(() => _currentImageZoomed = zoomed);
                  }
                }
              : null,
        ),
      ),
    );
  }
}

class _FocusedPhotoView extends StatefulWidget {
  const _FocusedPhotoView({
    required this.url,
    required this.index,
    this.onZoomChanged,
  });

  final String url;
  final int index;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<_FocusedPhotoView> createState() => _FocusedPhotoViewState();
}

class _FocusedPhotoViewState extends State<_FocusedPhotoView> {
  static const _doubleTapScale = 2.5;
  static const _zoomThreshold = 1.01;

  final _transformationController = TransformationController();
  final _activePointers = <int>{};
  int? _tapPointer;
  Offset? _tapDownPosition;
  Duration? _tapDownTime;
  Offset? _previousTapPosition;
  Duration? _previousTapTime;
  bool _tapCandidate = false;
  bool _zoomed = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _setZoomed(bool value) {
    if (_zoomed == value) return;
    setState(() => _zoomed = value);
    widget.onZoomChanged?.call(value);
  }

  void _handleDoubleTap(Offset focalPoint) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > _zoomThreshold) {
      _setZoomed(false);
      _transformationController.value = Matrix4.identity();
      return;
    }

    final target = Matrix4.identity()
      ..translateByDouble(
        -focalPoint.dx * (_doubleTapScale - 1),
        -focalPoint.dy * (_doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    _setZoomed(true);
    _transformationController.value = target;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    _setZoomed(
      _transformationController.value.getMaxScaleOnAxis() > _zoomThreshold,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length == 1) {
      _tapPointer = event.pointer;
      _tapDownPosition = event.localPosition;
      _tapDownTime = event.timeStamp;
      _tapCandidate = true;
      return;
    }
    _tapCandidate = false;
    _previousTapPosition = null;
    _previousTapTime = null;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _tapPointer || !_tapCandidate) return;
    final start = _tapDownPosition;
    if (start == null || (event.localPosition - start).distance > kTouchSlop) {
      _tapCandidate = false;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer != _tapPointer) return;
    final downTime = _tapDownTime;
    final isTap =
        _tapCandidate &&
        _activePointers.isEmpty &&
        downTime != null &&
        event.timeStamp - downTime < kLongPressTimeout;
    _tapPointer = null;
    _tapDownPosition = null;
    _tapDownTime = null;
    _tapCandidate = false;
    if (!isTap) return;

    final previousTime = _previousTapTime;
    final previousPosition = _previousTapPosition;
    final interval = previousTime == null
        ? null
        : event.timeStamp - previousTime;
    if (interval != null &&
        interval <= kDoubleTapTimeout &&
        previousPosition != null &&
        (event.localPosition - previousPosition).distance <= kDoubleTapSlop) {
      _previousTapTime = null;
      _previousTapPosition = null;
      final focalPoint = event.localPosition;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleDoubleTap(focalPoint);
      });
      return;
    }
    _previousTapTime = event.timeStamp;
    _previousTapPosition = event.localPosition;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (event.pointer == _tapPointer) {
      _tapPointer = null;
      _tapDownPosition = null;
      _tapDownTime = null;
      _tapCandidate = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _handlePointerDown,
    onPointerMove: _handlePointerMove,
    onPointerUp: _handlePointerUp,
    onPointerCancel: _handlePointerCancel,
    child: InteractiveViewer(
      key: Key('tieba-photo-view-${widget.index}'),
      transformationController: _transformationController,
      minScale: 1,
      maxScale: 4,
      panEnabled: _zoomed,
      scaleEnabled: true,
      onInteractionUpdate: _handleInteractionUpdate,
      child: SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.contain,
          placeholder: (_, _) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (_, _, _) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

class _ForumSearchDelegate extends SearchDelegate<void> {
  _ForumSearchDelegate(this.platform, this.forumName);

  final CithubPlatform platform;
  final String forumName;

  @override
  String? get searchFieldLabel => '搜索${displayTiebaForumName(forumName)}';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: '清空',
        onPressed: () => query = '',
        icon: const Icon(Icons.clear),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: '返回',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) => _resultWidget();

  @override
  Widget buildSuggestions(BuildContext context) => _resultWidget();

  Widget _resultWidget() {
    final keyword = query.trim();
    if (keyword.isEmpty) return const Center(child: Text('输入关键词搜索吧内帖子'));
    return _ForumSearchResults(
      key: ValueKey('$forumName/$keyword'),
      platform: platform,
      forumName: forumName,
      keyword: keyword,
    );
  }
}

class _ForumSearchResults extends StatefulWidget {
  const _ForumSearchResults({
    super.key,
    required this.platform,
    required this.forumName,
    required this.keyword,
  });

  final CithubPlatform platform;
  final String forumName;
  final String keyword;

  @override
  State<_ForumSearchResults> createState() => _ForumSearchResultsState();
}

class _ForumSearchResultsState extends State<_ForumSearchResults> {
  final _scrollController = ScrollController();
  final _threads = <ForumThreadDto>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadNext();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 420) _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final requestedPage = _page + 1;
    try {
      final result = await widget.platform.searchForum(
        widget.forumName,
        widget.keyword,
        page: requestedPage,
      );
      if (!mounted) return;
      setState(() {
        _page = result.page > 0 ? result.page : requestedPage;
        _hasMore = result.hasMore;
        appendUniqueBy(_threads, result.threads, (item) => item.id);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _threads.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _threads.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('搜索失败：$_error'),
            const SizedBox(height: 10),
            FilledButton(onPressed: _loadNext, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_threads.isEmpty) return const Center(child: Text('没有找到相关帖子'));
    return ListView.separated(
      controller: _scrollController,
      itemCount: _threads.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        if (index == _threads.length) {
          return _LoadingFooter(
            loading: _loading,
            error: _error,
            hasMore: _hasMore,
            onRetry: _loadNext,
          );
        }
        return _ThreadTile(
          thread: _threads[index],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadScreen(thread: _threads[index]),
            ),
          ),
        );
      },
    );
  }
}

class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter({
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onRetry,
  });

  final bool loading;
  final Object? error;
  final bool hasMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : error != null
          ? TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('加载失败，点击重试'),
            )
          : Text(
              hasMore ? '继续上滑加载' : '已经到底了',
              style: Theme.of(context).textTheme.bodySmall,
            ),
    ),
  );
}

class _ErrorSliver extends StatelessWidget {
  const _ErrorSliver({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('加载失败：$error'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

String _replyText(FloorReplyDto reply) => _plainTiebaContent(reply.content);

String _floorText(ThreadFloorDto floor) => _plainTiebaContent(floor.content);

String _plainTiebaContent(List<TiebaContentDto> content) => content
    .map(
      (item) => switch (item.kind) {
        'emoticon' => '#(${item.text})',
        'video' when item.text.isEmpty => '[视频]',
        _ => item.text,
      },
    )
    .join();

TiebaContentDto _textTiebaContent(String text) => TiebaContentDto(
  kind: 'text',
  text: text,
  emoticonId: '',
  url: '',
  originalUrl: '',
  width: 0,
  height: 0,
);

String _displayTiebaName(String nickname, String username, int userId) {
  final display = nickname.trim().isEmpty ? username.trim() : nickname.trim();
  if (display.isNotEmpty) return display;
  return userId > 0 ? '贴吧用户 $userId' : '贴吧用户';
}

final Map<String, String> _tiebaEmoticonAssets = {
  for (final entry in _tiebaEmoticonIds.entries)
    entry.key: _tiebaEmoticonAsset(entry.value),
};

String _tiebaEmoticonAsset(int id) =>
    'packages/cithub_native/android/src/main/assets/tiebalite/emoticon/image_emoticon$id.webp';

const _tiebaBundledEmoticonIds = <int>{
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
  24,
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
  41,
  42,
  43,
  44,
  45,
  46,
  47,
  48,
  49,
  50,
  77,
  78,
  79,
  80,
  81,
  82,
  83,
  84,
  89,
};

const _tiebaEmoticonIds = <String, int>{
  '呵呵': 1,
  '哈哈': 2,
  '吐舌': 3,
  '啊': 4,
  '酷': 5,
  '怒': 6,
  '开心': 7,
  '汗': 8,
  '泪': 9,
  '黑线': 10,
  '鄙视': 11,
  '不高兴': 12,
  '真棒': 13,
  '钱': 14,
  '疑问': 15,
  '阴险': 16,
  '吐': 17,
  '咦': 18,
  '委屈': 19,
  '花心': 20,
  '呼~': 21,
  '笑眼': 22,
  '冷': 23,
  '太开心': 24,
  '滑稽': 25,
  '勉强': 26,
  '狂汗': 27,
  '乖': 28,
  '睡觉': 29,
  '惊哭': 30,
  '生气': 31,
  '惊讶': 32,
  '喷': 33,
  '爱心': 34,
  '心碎': 35,
  '玫瑰': 36,
  '礼物': 37,
  '彩虹': 38,
  '星星月亮': 39,
  '太阳': 40,
  '钱币': 41,
  '灯泡': 42,
  '茶杯': 43,
  '蛋糕': 44,
  '音乐': 45,
  'haha': 46,
  '胜利': 47,
  '大拇指': 48,
  '弱': 49,
  'OK': 50,
  '沙发': 77,
  '手纸': 78,
  '香蕉': 79,
  '便便': 80,
  '药丸': 81,
  '红领巾': 82,
  '蜡烛': 83,
  '三道杠': 84,
  '笑尿': 89,
};

String _initial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first;
}

void _message(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
