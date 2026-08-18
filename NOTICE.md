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
