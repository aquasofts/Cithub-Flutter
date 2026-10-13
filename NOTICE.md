# Notices and attribution

## Cithub Android source

This project is a clean, standalone Flutter rewrite derived from the behavior, icon resources, protocol contracts, parsers, tests, and documentation of the GPL-3.0 Cithub Android application located in the migration workspace. The launcher vector/adaptive icon resources are reused without visual changes. Migrated or rewritten code remains licensed under GNU GPL-3.0.

Modifications include a new package identity, Flutter Material 3 UI, Pigeon typed interfaces, independent Android flavors, Android Keystore-backed storage, local-only runtime logging, and a release policy for `aquasofts/Cithub-Flutter`. Migrated Kotlin, PB, Helios and flavor code is packaged as the repository-local `packages/cithub_native` Flutter plugin.

The Cloudflare RSS Worker and Pages adapter are migrated to `tools/rss-worker/` so RSS infrastructure remains reproducible without the legacy repository. Deployment secrets, KV contents, and private upstream feed URLs are not included.

## TiebaLite

Tieba protocol behavior and the official-client reply URI are based on TiebaLite commit:

`910fd564c47f77ab6a807f1bc122279e7b9aa0b1`

The repository vendors the pinned protobuf schemas, Helios hashing sources, and classic emoticon assets needed by the read-only Tieba UI. Wire generates only the forum/thread, floor, profile, user-post, and forum-rule roots used by Cithub Flutter. Their source record and an unmodified upstream GPL-3.0 license are in `third_party/TiebaLite/`.

Only behavior reachable from the existing Cithub UI is in scope. The inactive in-app reply implementation is not enabled or generated; replies launch the official Baidu Tieba application. Upstream file headers are retained, and modifications remain under GPL-3.0.

## ML Kit

The `autoCaptcha` flavor uses Google ML Kit Chinese Text Recognition. The `manualCaptcha` flavor has no ML Kit dependency or packaged model. ML Kit is distributed under Google's applicable Android SDK and ML Kit terms; it is not relicensed by GPL-3.0.

## Flutter and packages

Flutter and Dart are distributed under their respective BSD-style licenses. Dart packages retain the licenses declared by their publishers. `pubspec.lock` records the exact resolved package versions used for reproducible builds.

## Campus AI and local timetable

The AI interface uses Flyer Chat (`flutter_chat_ui`, `flutter_chat_core`, and `flyer_chat_text_message`), licensed under Apache-2.0: https://github.com/flyerhq/flutter_chat_ui. Its upstream license notices remain distributed with Flutter dependencies. Chatbox Community Edition (GPL-3.0, https://github.com/chatboxai/chatbox) informs the conversation/model-selection interaction; no Chatbox application source is embedded.

PDF text extraction, scanned-page rendering, and preview use pdfrx (MIT), https://github.com/espresso3389/pdfrx. Office attachments use Dart archive (MIT) and XML parsing. Local schedule versions and conversations use sqflite (BSD-2-Clause). API transport implements the OpenAI-compatible Chat Completions wire format; no OpenAI key, hosted account, or service is bundled.

## RikkaHub chat interface

Chat message layout, thinking preview/collapse state machine, and animations are adapted from RikkaHub (AGPL-3.0), revision `0966502c4d65c1ee4b2a3e49a19703bb1978016c`: https://github.com/rikkahub/rikkahub. The pinned reference files, source record, and unmodified upstream license are in `third_party/RikkaHub/`. The Flutter adaptations retain AGPL-3.0-only attribution and source-availability requirements. Original Cithub source retains its GPL-3.0 notices.

## WakeUp timetable

The section-time model, start-section/span layout and manual-edit interaction reference WakeUp's Apache-2.0 source preserved in xianfei/WakeupSchedule_BUPT, commit 88d5b2ff93b946b40e8ade6851d4440188443a7f (Copyright 2019 YZune; BUPT adaptation by xianfei): https://github.com/xianfei/WakeupSchedule_BUPT. The pinned source record and unmodified license are in third_party/WakeUp/. Flutter adds actual-time boundary interpolation, compressed breaks and local course overrides; no upstream Kotlin application is embedded.
