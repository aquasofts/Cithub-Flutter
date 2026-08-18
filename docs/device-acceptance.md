# Android device acceptance checklist

Record device model, Android version, app flavor, app version, certificate SHA-256, and test date.

## Installation and lifecycle

- [ ] Old Cithub and Cithub Flutter coexist; neither reads or changes the other's data.
- [ ] Fresh install has no migrated account, setting, session, or cache.
- [ ] Both flavors install independently after uninstalling the other flavor.
- [ ] A later build signed by the same certificate updates in place.
- [ ] Process death and device restart preserve only intended local state.

## WebVPN and academic

- [ ] Multi-account add/select/forget uses encrypted local password storage.
- [ ] Captcha refresh, wrong captcha, wrong password, required action, and valid login states render correctly.
- [ ] Auto flavor recognizes captcha and performs permitted automatic re-login; manual flavor does neither.
- [ ] Cookie restoration, periodic revalidation, expiration, and logout work.
- [ ] Independent academic login works; grades, timetable, selection results, and evaluation parse real pages.
- [ ] Course selection, classroom request, textbook account, textbook confirmation, and minor registration WebViews retain cookies, navigation, forms, uploads, downloads, and back behavior.

## News

- [ ] WeChat/custom RSS, campus RSS, and official news load, merge, deduplicate, sort, and cache.
- [ ] Offline and stale-cache states are usable; malformed sources do not hide healthy sources.
- [ ] Article, image preview/zoom, image save, permission denial, and safe external links work.
- [ ] Article paragraphs and images retain DOM order; scripts, forms, event attributes, and non-HTTPS resources are removed, and wide images/tables stay within the viewport.

## Tieba

- [ ] The home forum defaults to `长春工程学院`, accepts settings with or without trailing `吧`, and refreshes immediately after a setting change.
- [ ] Forum browse, reply/post sorting, featured filter, search, rules, pinned-post deduplication, and near-end infinite loading work without explicit page controls.
- [ ] The first floor renders once as the article body; later floors, floor replies, user profiles, original images, infinite loading, deduplication, and position restoration work.
- [ ] Floor reply previews show at most three replies and “查看全部 N 条回复”; the full view keeps the parent floor above its infinitely loaded replies.
- [ ] Owner, assistant moderator, title, level, original-poster, and IP-location badges match real accounts.
- [ ] Login Cookie/token is not readable as plaintext in app databases or preferences.
- [ ] Login is available only from Mine, uses the mobile login URL and Android mobile UA, and completes automatically after reaching the `tbwise` Mine page on either supported Tieba host.
- [ ] Sign, follow, account refresh, and logout work.
- [ ] Long-press menus on the main floor, normal floors, and floor replies offer Reply/Copy; Reply opens the official Baidu Tieba client and normal floors carry the correct `postId`.
- [ ] With the official Tieba client uninstalled, Reply shows a clear unavailable-client message.

## UI, settings, update, and logs

- [ ] 320dp width, long Chinese text, large font, rapid tab switching, predictive back, and list restoration have no overflow or state loss.
- [ ] Tieba, News, Academic, and Mine keep independent detail stacks; detail pages retain bottom navigation and Back exits one level in the active tab.
- [ ] Academic login uses one outer scroll container; its title, sort action, captcha, refresh action, saved-password checkbox, and login button remain reachable at 320dp and large text.
- [ ] Academic feature drag sorting persists.
- [ ] Theme mode, custom color, AMOLED, navigation style, reduced motion, RSS and Tieba settings persist.
- [ ] Themed launcher icon toggles without losing the launcher entry.
- [ ] Update check chooses the current flavor only; cancel/retry/progress survive expected lifecycle changes.
- [ ] Corrupted, wrong-package, wrong-flavor, and wrong-signer APKs are rejected.
- [ ] Full logs remain local, roll at the size limit, export only on explicit action, and clear successfully.
