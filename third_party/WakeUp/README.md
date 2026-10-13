# WakeUp timetable references

Source: https://github.com/xianfei/WakeupSchedule_BUPT
Commit: 88d5b2ff93b946b40e8ade6851d4440188443a7f
Upstream: YZune/WakeupSchedule_Kotlin (currently unavailable), WakeUp 3.612/3.621 lineage.
License: Apache-2.0 (unmodified license included).
Copyright 2019 YZune. BUPT adaptation by xianfei.

Read `bean/TimeDetailBean.kt`, `schedule/ScheduleFragment.kt`,
`schedule/CourseDetailFragment.kt`, `course_add/AddCourseViewModel.kt`,
and `settings/TimeSettingsFragment.kt`.

Flutter adaptations in `timetable_time.dart` and `timetable_editor_screen.dart`
follow the independent per-section timetable, start-section/span geometry,
course detail timing, and manual course editing model. Minute interpolation,
compressed breaks, local actual-time overrides, revision/history validation,
and Flutter controls are implemented for Cithub. No upstream Kotlin app,
resources or binaries are embedded.
