/// A short blessing sent to someone's activity — the app's version of kudos.
class Encouragement {
  const Encouragement({
    required this.id,
    required this.activityId,
    required this.fromUserId,
    required this.createdAt,
  });

  final String id;
  final String activityId;
  final String fromUserId;
  final DateTime createdAt;
}

class Comment {
  const Comment({
    required this.id,
    required this.activityId,
    required this.authorId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String activityId;
  final String authorId;
  final String body;
  final DateTime createdAt;
}

class Follow {
  const Follow({required this.followerId, required this.followeeId});

  final String followerId;
  final String followeeId;
}
