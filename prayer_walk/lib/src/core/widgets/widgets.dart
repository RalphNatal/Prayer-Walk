/// The shared widget kit.
///
/// Screens import this one file rather than a dozen paths. Note that
/// `route_map_view.dart` imports `flutter_map` but does not re-export it — Dart
/// imports are not transitive, so the map package stays sealed inside that
/// widget no matter who imports this barrel.
library;

export 'activity_type_chip.dart';
export 'app_buttons.dart';
export 'async_view.dart';
export 'dialogs.dart';
export 'error_report_dialog.dart';
export 'motion.dart';
export 'pilgrimage_card.dart';
export 'route_map_view.dart';
export 'route_trail_preview.dart';
export 'section_header.dart';
export 'skeletons.dart';
export 'stat_tile.dart';
export 'state_views.dart';
export 'trail_painter.dart';
export 'user_avatar.dart';
