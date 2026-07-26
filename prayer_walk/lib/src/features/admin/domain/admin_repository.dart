import '../../profile/domain/user_profile.dart';
import 'admin_models.dart';

abstract interface class AdminRepository {
  Future<AdminMetrics> metrics();

  Future<List<UserProfile>> members(MemberQuery query);

  Future<UserProfile> memberById(String id);

  /// How many activities this member has logged — shown on member detail.
  Future<int> activityCountFor(String userId);

  Future<UserProfile> setRole(String userId, UserRole role);

  Future<UserProfile> setStatus(String userId, MemberStatus status);

  Future<List<ModerationReport>> reports({ReportStatus? status});

  Future<ModerationReport> resolveReport(String id, ReportStatus outcome);

  Future<List<Announcement>> announcements();

  Future<Announcement> sendAnnouncement({
    required String title,
    required String body,
    required AnnouncementAudience audience,
    required String sentByName,
  });

  /// Recipients the given audience currently resolves to, so the compose
  /// screen can state the blast radius before it is sent.
  Future<int> audienceSize(AnnouncementAudience audience);
}
