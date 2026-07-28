import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../admin/data/admin_row_mapper.dart';
import '../../admin/domain/admin_models.dart';

/// Announcements a member is allowed to see, newest first.
///
/// Lives with the feed because the feed is where they surface — an announcement
/// with no member-facing screen would be a row written into a table nobody
/// reads.
///
/// There is no audience filter in this query, deliberately. Which announcements
/// a person is addressed by is decided by the read policy on the table:
/// `everyone` for all, `activeMembers` only while their status is active, and
/// admins-only broadcasts never. Filtering here as well would be a second
/// answer to the same question, and the one that could be wrong.
final memberAnnouncementsProvider = FutureProvider<List<Announcement>>((
  ref,
) async {
  final rows = await supabase
      .from('announcements')
      .select(announcementColumns)
      .order('sent_at', ascending: false)
      .limit(5);
  return [for (final row in rows) announcementFromRow(row)];
});
