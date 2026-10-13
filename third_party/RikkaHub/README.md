# RikkaHub chat UI source record

Upstream: https://github.com/rikkahub/rikkahub

Pinned revision: `0966502c4d65c1ee4b2a3e49a19703bb1978016c`.

The unmodified `ChatMessage.kt`, `ChatMessageReasoning.kt`, `ChainOfThought.kt`,
`ChatMessageAvatar.kt`, `ChatInput.kt`, and `Shimmer.kt` files here preserve the source used for the Flutter port.
Upstream authors retain their copyrights; the unmodified upstream AGPL-3.0
license is included as `LICENSE`.

`lib/features/ai/ai_reasoning_card.dart` translates the upstream Collapsed /
Preview / Expanded state machine, 100dp preview with vertical fading,
automatic scrolling, 50ms elapsed-time updates, 1200ms shimmer, and automatic
collapse on completion. `ai_screen.dart` adapts the avatar/name row, separate
message actions, rounded user bubble, unboxed assistant Markdown, and message
entrance animations. Kotlin Compose code is translated into Flutter widgets;
the upstream Android application is not a runtime dependency.

Flutter additions include logged state transitions, local persistence of
reasoning timestamps/outcomes, explicit cancelled/failed labels, and disabling
text selection in streaming reasoning (also reflected in the upstream fix).
Derived UI code is distributed under AGPL-3.0-only; retain these source and
license notices in redistribution and provide corresponding source as required
by that license. Original Cithub code retains its GPL-3.0 notices.
