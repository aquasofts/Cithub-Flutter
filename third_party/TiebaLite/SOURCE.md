# TiebaLite source record

- Upstream: https://github.com/0ranko0P/TiebaLite
- Commit: `910fd564c47f77ab6a807f1bc122279e7b9aa0b1`
- License: GNU GPL version 3; see `LICENSE` in this directory.
- Retrieved: 2026-08-18

The Android build vendors the upstream protobuf schemas under
`android/app/src/main/proto`, the Helios hashing implementation under
`android/app/src/main/java/com/huanchengfly/tieba/post/utils/helios`, and the
classic emoticon mapping/assets under `android/app/src/main/assets/tiebalite`.

Wire generates only the message roots required by the read-only Cithub UI:
forum/thread lists, thread/floor pages, profiles, user posts, and forum rules.
TiebaLite's in-app reply protocol is deliberately not generated or connected;
Cithub Flutter dispatches replies to the official Baidu Tieba application.
