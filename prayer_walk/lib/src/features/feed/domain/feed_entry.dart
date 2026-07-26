import '../../activity/domain/activity.dart';
import '../../profile/domain/user_profile.dart';

/// One pilgrimage card's worth of data: the activity plus the person who
/// walked it, joined for the viewer.
class FeedEntry {
  const FeedEntry({required this.activity, required this.author});

  final Activity activity;
  final UserProfile author;
}
