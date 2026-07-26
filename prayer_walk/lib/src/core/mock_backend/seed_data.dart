import 'package:latlong2/latlong.dart';

import '../../features/activity/domain/activity.dart';
import '../../features/admin/domain/admin_models.dart';
import '../../features/devotionals/domain/devotional.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/social/domain/social.dart';
import 'route_shapes.dart';

/// Everything the fake backend starts life holding.
class MockSeed {
  const MockSeed({
    required this.users,
    required this.activities,
    required this.devotionals,
    required this.comments,
    required this.encouragements,
    required this.follows,
    required this.reports,
    required this.announcements,
  });

  final List<UserProfile> users;
  final List<Activity> activities;
  final List<Devotional> devotionals;
  final List<Comment> comments;
  final List<Encouragement> encouragements;
  final List<Follow> follows;
  final List<ModerationReport> reports;
  final List<Announcement> announcements;

  /// The seeded person the mock session signs in as.
  static const currentUserId = 'u_maria';

  static MockSeed build() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 5, 40);
    DateTime daysAgo(int d, {int hour = 6, int minute = 0}) =>
        today.subtract(Duration(days: d)).copyWith(hour: hour, minute: minute);

    // --------------------------------------------------------------- people ---
    final users = <UserProfile>[
      UserProfile(
        id: currentUserId,
        displayName: 'Maria Reyes',
        handle: '@mariawalks',
        role: UserRole.member,
        status: MemberStatus.active,
        joinedAt: daysAgo(412),
        accentIndex: 0,
        bio: 'Out before the jeepneys. Six laps of the village, then coffee.',
        parish: 'San Roque Parish, Mandaluyong',
        followerCount: 3,
        followingCount: 5,
        stats: const LifetimeStats(
          totalDistanceMeters: 1284300,
          totalDuration: Duration(hours: 214, minutes: 35),
          activityCount: 186,
          streakDays: 12,
          intentionCount: 341,
        ),
      ),
      UserProfile(
        id: 'u_ben',
        displayName: 'Ben Ocampo',
        handle: '@frben',
        role: UserRole.admin,
        status: MemberStatus.active,
        joinedAt: daysAgo(520),
        accentIndex: 3,
        bio: 'Parish priest. Keeper of the devotional shelf.',
        parish: 'San Roque Parish, Mandaluyong',
        followerCount: 5,
        followingCount: 2,
        stats: const LifetimeStats(
          totalDistanceMeters: 402100,
          totalDuration: Duration(hours: 88, minutes: 10),
          activityCount: 74,
          streakDays: 3,
          intentionCount: 198,
        ),
      ),
      UserProfile(
        id: 'u_dan',
        displayName: 'Daniel Cruz',
        handle: '@dcruz',
        role: UserRole.member,
        status: MemberStatus.active,
        joinedAt: daysAgo(288),
        accentIndex: 1,
        bio: 'Marathon in November. Praying the whole way there.',
        parish: 'Christ the King, Quezon City',
        followerCount: 4,
        followingCount: 3,
        stats: const LifetimeStats(
          totalDistanceMeters: 2310800,
          totalDuration: Duration(hours: 196, minutes: 5),
          activityCount: 241,
          streakDays: 31,
          intentionCount: 156,
        ),
      ),
      UserProfile(
        id: 'u_ana',
        displayName: 'Ana Villanueva',
        handle: '@anav',
        role: UserRole.member,
        status: MemberStatus.active,
        joinedAt: daysAgo(151),
        accentIndex: 2,
        bio: 'Nurse. Night shift, morning hills.',
        parish: 'Our Lady of Peace, Antipolo',
        followerCount: 6,
        followingCount: 4,
        stats: const LifetimeStats(
          totalDistanceMeters: 688400,
          totalDuration: Duration(hours: 141, minutes: 50),
          activityCount: 97,
          streakDays: 6,
          intentionCount: 220,
        ),
      ),
      UserProfile(
        id: 'u_jon',
        displayName: 'Jonas Lim',
        handle: '@jonaslim',
        role: UserRole.member,
        status: MemberStatus.active,
        joinedAt: daysAgo(96),
        accentIndex: 4,
        bio: 'Two wheels, one rosary.',
        parish: 'Sto. Niño, Pasig',
        followerCount: 2,
        followingCount: 5,
        stats: const LifetimeStats(
          totalDistanceMeters: 4120500,
          totalDuration: Duration(hours: 172, minutes: 20),
          activityCount: 88,
          streakDays: 0,
          intentionCount: 64,
        ),
      ),
      UserProfile(
        id: 'u_grace',
        displayName: 'Grace Tan',
        handle: '@gracetan',
        role: UserRole.member,
        status: MemberStatus.active,
        joinedAt: daysAgo(63),
        accentIndex: 5,
        bio: 'Novena walker. Day 3 of 9.',
        parish: 'San Roque Parish, Mandaluyong',
        followerCount: 3,
        followingCount: 6,
        stats: const LifetimeStats(
          totalDistanceMeters: 96200,
          totalDuration: Duration(hours: 22, minutes: 45),
          activityCount: 21,
          streakDays: 3,
          intentionCount: 58,
        ),
      ),
      UserProfile(
        id: 'u_pia',
        displayName: 'Pia Mendoza',
        handle: '@piam',
        role: UserRole.member,
        status: MemberStatus.suspended,
        joinedAt: daysAgo(38),
        accentIndex: 1,
        bio: '',
        parish: '',
        followerCount: 0,
        followingCount: 1,
        stats: const LifetimeStats(
          totalDistanceMeters: 12400,
          totalDuration: Duration(hours: 3, minutes: 5),
          activityCount: 4,
          streakDays: 0,
          intentionCount: 2,
        ),
      ),
      UserProfile(
        id: 'u_rex',
        displayName: 'Rex Santiago',
        handle: '@rexs',
        role: UserRole.member,
        status: MemberStatus.active,
        joinedAt: daysAgo(4),
        accentIndex: 4,
        bio: 'Just started. Be gentle.',
        parish: 'Christ the King, Quezon City',
        followerCount: 1,
        followingCount: 2,
        stats: const LifetimeStats(
          totalDistanceMeters: 8300,
          totalDuration: Duration(hours: 1, minutes: 52),
          activityCount: 3,
          streakDays: 2,
          intentionCount: 5,
        ),
      ),
    ];

    // ------------------------------------------------------------- follows ---
    const follows = <Follow>[
      Follow(followerId: currentUserId, followeeId: 'u_ben'),
      Follow(followerId: currentUserId, followeeId: 'u_dan'),
      Follow(followerId: currentUserId, followeeId: 'u_ana'),
      Follow(followerId: currentUserId, followeeId: 'u_jon'),
      Follow(followerId: currentUserId, followeeId: 'u_grace'),
      Follow(followerId: 'u_dan', followeeId: currentUserId),
      Follow(followerId: 'u_ana', followeeId: currentUserId),
      Follow(followerId: 'u_grace', followeeId: currentUserId),
      Follow(followerId: 'u_ben', followeeId: 'u_ana'),
      Follow(followerId: 'u_rex', followeeId: 'u_dan'),
      Follow(followerId: 'u_jon', followeeId: 'u_dan'),
    ];

    // ------------------------------------------------------------- routes ---
    const mandaluyong = LatLng(14.5794, 121.0359);
    const marikina = LatLng(14.6507, 121.1029);
    const quezonCity = LatLng(14.6760, 121.0437);
    const cubao = LatLng(14.6199, 121.0530);
    const baguio = LatLng(16.4023, 120.5960);
    const tagaytayRoad = LatLng(14.2450, 121.0100);
    const pasig = LatLng(14.5764, 121.0851);
    const antipolo = LatLng(14.5878, 121.1760);
    const roxasBoulevard = LatLng(14.5570, 120.9820);

    final routes = <String, List<LatLng>>{
      'a_1': RouteShapes.loop(mandaluyong, radiusKm: 0.85, seed: 11),
      'a_2': RouteShapes.meander(marikina, lengthKm: 4.6, amplitudeKm: 0.35),
      'a_3': RouteShapes.spiral(quezonCity, maxRadiusKm: 0.62, turns: 3.4),
      'a_4': RouteShapes.cityBlocks(cubao, blockKm: 0.38, blocks: 6, seed: 17),
      'a_5': RouteShapes.switchbacks(baguio, riseKm: 2.4, widthKm: 0.6, seed: 23),
      'a_6': RouteShapes.meander(
        tagaytayRoad,
        lengthKm: 14.5,
        amplitudeKm: 0.9,
        bearingDeg: 250,
        waves: 3.4,
        points: 150,
      ),
      'a_7': RouteShapes.figureEight(mandaluyong, radiusKm: 0.72),
      'a_8': RouteShapes.outAndBack(pasig, lengthKm: 1.9, bearingDeg: 15, seed: 29),
      'a_9': RouteShapes.switchbacks(antipolo, riseKm: 1.7, widthKm: 0.44, seed: 31),
      'a_10': RouteShapes.crescent(roxasBoulevard, radiusKm: 1.35, sweepDeg: 150),
    };

    Waypoint waypoint(
      String id,
      List<LatLng> route,
      int index,
      int of,
      WaypointKind kind,
      String label,
      Duration elapsed, {
      String note = '',
    }) {
      final points = RouteShapes.along(route, of);
      return Waypoint(
        id: id,
        point: points[index],
        kind: kind,
        label: label,
        note: note,
        elapsed: elapsed,
      );
    }

    PrayerIntention intention(
      String id,
      String text,
      PrayerCategory category,
      DateTime at,
    ) => PrayerIntention(id: id, text: text, category: category, createdAt: at);

    Activity make({
      required String id,
      required String userId,
      required ActivityType type,
      required String title,
      required DateTime startedAt,
      required Duration duration,
      required double elevationGainMeters,
      List<Waypoint> waypoints = const [],
      List<PrayerIntention> intentions = const [],
      String note = '',
    }) {
      final route = routes[id]!;
      return Activity(
        id: id,
        userId: userId,
        type: type,
        title: title,
        startedAt: startedAt,
        duration: duration,
        distanceMeters: RouteShapes.lengthMeters(route),
        elevationGainMeters: elevationGainMeters,
        route: route,
        waypoints: waypoints,
        intentions: intentions,
        note: note,
      );
    }

    final activities = <Activity>[
      make(
        id: 'a_1',
        userId: currentUserId,
        type: ActivityType.walk,
        title: 'First light at San Roque',
        startedAt: daysAgo(0, hour: 5, minute: 42),
        duration: const Duration(minutes: 52, seconds: 18),
        elevationGainMeters: 28,
        note: 'Quiet all the way to the market. Stayed for the 6am bell.',
        intentions: [
          intention('i_1', "For Lola Iding's biopsy results", PrayerCategory.healing, daysAgo(0)),
          intention('i_2', 'For the families on Ilaya Street', PrayerCategory.community, daysAgo(0)),
        ],
        waypoints: [
          waypoint('w_1', routes['a_1']!, 0, 3, WaypointKind.intercession,
              'Chapel gate', const Duration(minutes: 11),
              note: 'Prayed the first decade here.'),
          waypoint('w_2', routes['a_1']!, 1, 3, WaypointKind.gratitude,
              'The bakery corner', const Duration(minutes: 26)),
          waypoint('w_3', routes['a_1']!, 2, 3, WaypointKind.stillness,
              'Bench by the covered court', const Duration(minutes: 41)),
        ],
      ),
      make(
        id: 'a_2',
        userId: currentUserId,
        type: ActivityType.walk,
        title: 'Rosary along the river',
        startedAt: daysAgo(2, hour: 17, minute: 20),
        duration: const Duration(minutes: 58, seconds: 4),
        elevationGainMeters: 14,
        intentions: [
          intention('i_3', 'For patience with my brother', PrayerCategory.family, daysAgo(2)),
        ],
        waypoints: [
          waypoint('w_4', routes['a_2']!, 0, 2, WaypointKind.scripture,
              'Read Psalm 121 at the bench', const Duration(minutes: 19)),
          waypoint('w_5', routes['a_2']!, 1, 2, WaypointKind.stillness,
              'Silence by the water', const Duration(minutes: 44)),
        ],
      ),
      make(
        id: 'a_3',
        userId: currentUserId,
        type: ActivityType.run,
        title: 'Six laps before work',
        startedAt: daysAgo(4, hour: 5, minute: 15),
        duration: const Duration(minutes: 31, seconds: 47),
        elevationGainMeters: 9,
        intentions: [
          intention('i_4', 'For the students sitting exams this week',
              PrayerCategory.guidance, daysAgo(4)),
        ],
        waypoints: [
          waypoint('w_6', routes['a_3']!, 0, 1, WaypointKind.intercession,
              'The school gate', const Duration(minutes: 14)),
        ],
      ),
      make(
        id: 'a_4',
        userId: 'u_dan',
        type: ActivityType.run,
        title: 'Tempo through Cubao',
        startedAt: daysAgo(0, hour: 6, minute: 5),
        duration: const Duration(minutes: 44, seconds: 12),
        elevationGainMeters: 36,
        note: 'Legs heavy. Offered the last two kilometres up.',
        intentions: [
          intention('i_5', 'For work to come through for Nanay',
              PrayerCategory.family, daysAgo(0)),
        ],
        waypoints: [
          waypoint('w_7', routes['a_4']!, 0, 2, WaypointKind.gratitude,
              'The overpass', const Duration(minutes: 16)),
          waypoint('w_8', routes['a_4']!, 1, 2, WaypointKind.intercession,
              'Jeepney terminal', const Duration(minutes: 33)),
        ],
      ),
      make(
        id: 'a_5',
        userId: 'u_ana',
        type: ActivityType.hike,
        title: 'Up to the ridge before shift',
        startedAt: daysAgo(1, hour: 5, minute: 5),
        duration: const Duration(hours: 1, minutes: 48, seconds: 30),
        elevationGainMeters: 412,
        intentions: [
          intention('i_6', 'For the ward, and the ones who did not go home',
              PrayerCategory.healing, daysAgo(1)),
          intention('i_7', 'Thanks for the rain last night',
              PrayerCategory.gratitude, daysAgo(1)),
        ],
        waypoints: [
          waypoint('w_9', routes['a_5']!, 0, 3, WaypointKind.stillness,
              'First clearing', const Duration(minutes: 24)),
          waypoint('w_10', routes['a_5']!, 1, 3, WaypointKind.scripture,
              'Pine bend', const Duration(minutes: 51)),
          waypoint('w_11', routes['a_5']!, 2, 3, WaypointKind.gratitude,
              'The ridge', const Duration(minutes: 83)),
        ],
      ),
      make(
        id: 'a_6',
        userId: 'u_jon',
        type: ActivityType.cycle,
        title: 'Long ride to Tagaytay',
        startedAt: daysAgo(1, hour: 4, minute: 50),
        duration: const Duration(hours: 2, minutes: 21, seconds: 9),
        elevationGainMeters: 638,
        intentions: [
          intention('i_8', 'For safe roads for everyone out this early',
              PrayerCategory.world, daysAgo(1)),
        ],
        waypoints: [
          waypoint('w_12', routes['a_6']!, 0, 2, WaypointKind.intercession,
              'Silang junction', const Duration(minutes: 48)),
          waypoint('w_13', routes['a_6']!, 1, 2, WaypointKind.gratitude,
              'The ridge view', const Duration(minutes: 104)),
        ],
      ),
      make(
        id: 'a_7',
        userId: 'u_grace',
        type: ActivityType.walk,
        title: 'Novena walk, day 3',
        startedAt: daysAgo(0, hour: 18, minute: 30),
        duration: const Duration(minutes: 41, seconds: 55),
        elevationGainMeters: 18,
        intentions: [
          intention('i_9', 'For my sister to come home', PrayerCategory.family, daysAgo(0)),
          intention('i_10', 'For steady work', PrayerCategory.guidance, daysAgo(0)),
        ],
        waypoints: [
          waypoint('w_14', routes['a_7']!, 0, 2, WaypointKind.intercession,
              'Where the two roads cross', const Duration(minutes: 15)),
          waypoint('w_15', routes['a_7']!, 1, 2, WaypointKind.stillness,
              'Back at the gate', const Duration(minutes: 36)),
        ],
      ),
      make(
        id: 'a_8',
        userId: 'u_ben',
        type: ActivityType.walk,
        title: 'Evening rounds',
        startedAt: daysAgo(3, hour: 19, minute: 10),
        duration: const Duration(minutes: 36, seconds: 2),
        elevationGainMeters: 11,
        note: 'Two house blessings on the way back.',
        intentions: [
          intention('i_11', 'For the Dizon family', PrayerCategory.community, daysAgo(3)),
        ],
        waypoints: [
          waypoint('w_16', routes['a_8']!, 0, 1, WaypointKind.intercession,
              'The Dizon house', const Duration(minutes: 18)),
        ],
      ),
      make(
        id: 'a_9',
        userId: currentUserId,
        type: ActivityType.hike,
        title: 'Antipolo climb with Tita',
        startedAt: daysAgo(9, hour: 6, minute: 0),
        duration: const Duration(hours: 1, minutes: 24, seconds: 40),
        elevationGainMeters: 288,
        intentions: [
          intention('i_12', "For Tita's knees", PrayerCategory.healing, daysAgo(9)),
          intention('i_13', 'Thanks for twenty years of these walks',
              PrayerCategory.gratitude, daysAgo(9)),
        ],
        waypoints: [
          waypoint('w_17', routes['a_9']!, 0, 2, WaypointKind.gratitude,
              'Halfway marker', const Duration(minutes: 32)),
          waypoint('w_18', routes['a_9']!, 1, 2, WaypointKind.scripture,
              'The shrine steps', const Duration(minutes: 66)),
        ],
      ),
      make(
        id: 'a_10',
        userId: 'u_ana',
        type: ActivityType.walk,
        title: 'Bay walk at dusk',
        startedAt: daysAgo(6, hour: 17, minute: 45),
        duration: const Duration(minutes: 63, seconds: 21),
        elevationGainMeters: 6,
        intentions: [
          intention('i_14', 'For the ones sleeping out here tonight',
              PrayerCategory.world, daysAgo(6)),
        ],
        waypoints: [
          waypoint('w_19', routes['a_10']!, 0, 2, WaypointKind.stillness,
              'Facing the water', const Duration(minutes: 22)),
          waypoint('w_20', routes['a_10']!, 1, 2, WaypointKind.intercession,
              'Under the acacia', const Duration(minutes: 47)),
        ],
      ),
    ];

    // --------------------------------------------------------- devotionals ---
    final devotionals = <Devotional>[
      Devotional(
        id: 'd_1',
        title: 'Before the street wakes',
        summary: 'A short prayer for the first hundred steps of the day.',
        body:
            'Begin before you have decided anything. Step out, and let the first '
            'hundred steps be given away rather than used.\n\n'
            'Notice the sound your feet make. Notice that you did not have to '
            'ask for this morning; it arrived while you slept.\n\n'
            'When the noise starts — the first engine, the first shutter going '
            'up — do not resent it. Pray for whoever is behind it.',
        scriptureRef: 'Lamentations 3:22-23',
        scriptureText:
            'The steadfast love of the Lord never ceases; his mercies never come '
            'to an end; they are new every morning.',
        category: DevotionalCategory.morningLight,
        authorName: 'Ben Ocampo',
        updatedAt: daysAgo(21),
        publishedAt: daysAgo(21),
        isPublished: true,
        readMinutes: 2,
      ),
      Devotional(
        id: 'd_2',
        title: 'Count five things on this street',
        summary: 'Gratitude at walking pace, one block at a time.',
        body:
            'Pick a block you know too well to see. Walk it slowly and find five '
            'things you have never thanked anyone for.\n\n'
            'The tree someone planted before you were born. The light that works. '
            'The person who sweeps this corner at four in the morning.\n\n'
            'Say each one out loud if you can. Gratitude that stays in the head '
            'tends to evaporate.',
        scriptureRef: 'Psalm 118:24',
        scriptureText:
            'This is the day that the Lord has made; let us rejoice and be glad in it.',
        category: DevotionalCategory.gratitude,
        authorName: 'Ben Ocampo',
        updatedAt: daysAgo(14),
        publishedAt: daysAgo(14),
        isPublished: true,
        readMinutes: 3,
      ),
      Devotional(
        id: 'd_3',
        title: 'Carry one name the whole way',
        summary: 'One person, one route. Set them down only at the end.',
        body:
            'Choose one name before you start. Not a list — one.\n\n'
            'Every time your mind wanders, and it will, come back to the name '
            'rather than to yourself. Let the distance be for them.\n\n'
            'At the end, mark the spot where you finished. You are allowed to '
            'set them down there. You are not carrying them alone.',
        scriptureRef: 'Galatians 6:2',
        scriptureText: "Bear one another's burdens, and so fulfil the law of Christ.",
        category: DevotionalCategory.intercession,
        authorName: 'Ben Ocampo',
        updatedAt: daysAgo(9),
        publishedAt: daysAgo(9),
        isPublished: true,
        readMinutes: 2,
      ),
      Devotional(
        id: 'd_4',
        title: 'For the walk you did not want to take',
        summary: 'When the route is heavy and the words have run out.',
        body:
            'Some days the walk is not devotion, it is escape. Take it anyway.\n\n'
            'You do not owe anyone a well-formed prayer. Say the true thing, even '
            'if the true thing is that you are tired of saying things.\n\n'
            'Lament is not the absence of faith. It is faith that has stopped '
            'pretending.',
        scriptureRef: 'Psalm 13:1-2',
        scriptureText:
            'How long, O Lord? Will you forget me for ever? How long will you hide '
            'your face from me?',
        category: DevotionalCategory.lament,
        authorName: 'Ana Villanueva',
        updatedAt: daysAgo(6),
        publishedAt: daysAgo(6),
        isPublished: true,
        readMinutes: 3,
      ),
      Devotional(
        id: 'd_5',
        title: 'Twenty minutes, no words',
        summary: 'Walk the loop without asking for anything.',
        body:
            'Leave the phone in your pocket. Do not name a single intention.\n\n'
            'Twenty minutes is long enough to get bored, and boredom is usually '
            'where the noise finally drops.\n\n'
            'If something surfaces, let it. You are not required to do anything '
            'with it today.',
        category: DevotionalCategory.stillness,
        authorName: 'Ben Ocampo',
        updatedAt: daysAgo(3),
        publishedAt: daysAgo(3),
        isPublished: true,
        readMinutes: 1,
      ),
      Devotional(
        id: 'd_6',
        title: 'Psalm 121, one line per kilometre',
        summary: 'A passage paced out across the route.',
        body:
            'Take one line at the start of each kilometre and carry it until the '
            'next.\n\n'
            'Do not analyse it. Repeat it until it stops sounding like words and '
            'starts sounding like something you are walking through.\n\n'
            'If the route is short, take fewer lines. The passage is not a target.',
        scriptureRef: 'Psalm 121:1-2',
        scriptureText:
            'I lift up my eyes to the hills. From where does my help come? My help '
            'comes from the Lord, who made heaven and earth.',
        category: DevotionalCategory.scriptureWalk,
        authorName: 'Ben Ocampo',
        updatedAt: daysAgo(30),
        publishedAt: daysAgo(30),
        isPublished: true,
        readMinutes: 4,
      ),
      Devotional(
        id: 'd_7',
        title: 'Walking the novena',
        summary: 'Nine days, nine routes, one request.',
        body:
            'Draft — needs the nine daily prompts written out before this goes '
            'live.\n\n'
            'The shape: same request each day, different street each day, so the '
            'asking does not calcify into a formula.',
        category: DevotionalCategory.intercession,
        authorName: 'Ben Ocampo',
        updatedAt: daysAgo(1),
        isPublished: false,
        readMinutes: 5,
      ),
      Devotional(
        id: 'd_8',
        title: 'For the ones on night shift',
        summary: 'A prayer for the walk home at 6am.',
        body:
            'Draft — Ana is writing this one. Needs a scripture pairing and a '
            'shorter opening.',
        category: DevotionalCategory.lament,
        authorName: 'Ana Villanueva',
        updatedAt: daysAgo(0, hour: 9),
        isPublished: false,
        readMinutes: 2,
      ),
    ];

    // -------------------------------------------------------------- social ---
    final encouragements = <Encouragement>[
      for (final e in <(String, String, int)>[
        ('a_1', 'u_dan', 40),
        ('a_1', 'u_ana', 90),
        ('a_1', 'u_grace', 150),
        ('a_2', 'u_grace', 2100),
        ('a_2', 'u_ben', 2400),
        ('a_3', 'u_dan', 5000),
        ('a_4', currentUserId, 30),
        ('a_4', 'u_rex', 75),
        ('a_4', 'u_jon', 120),
        ('a_5', 'u_ben', 600),
        ('a_5', currentUserId, 700),
        ('a_6', 'u_dan', 900),
        ('a_7', 'u_ben', 20),
        ('a_9', 'u_ana', 12000),
        ('a_10', 'u_grace', 8000),
      ])
        Encouragement(
          id: 'e_${e.$1}_${e.$2}',
          activityId: e.$1,
          fromUserId: e.$2,
          createdAt: now.subtract(Duration(minutes: e.$3)),
        ),
    ];

    final comments = <Comment>[
      Comment(
        id: 'c_1',
        activityId: 'a_1',
        authorId: 'u_grace',
        body: 'Holding Lola Iding with you today.',
        createdAt: now.subtract(const Duration(minutes: 95)),
      ),
      Comment(
        id: 'c_2',
        activityId: 'a_1',
        authorId: 'u_dan',
        body: 'That bell at six is the best part of the whole village.',
        createdAt: now.subtract(const Duration(minutes: 62)),
      ),
      Comment(
        id: 'c_3',
        activityId: 'a_1',
        authorId: 'u_ben',
        body: 'Come by after. I will put her name on the list.',
        createdAt: now.subtract(const Duration(minutes: 30)),
      ),
      Comment(
        id: 'c_4',
        activityId: 'a_4',
        authorId: currentUserId,
        body: 'Heavy legs still count. Praying for Nanay.',
        createdAt: now.subtract(const Duration(minutes: 44)),
      ),
      Comment(
        id: 'c_5',
        activityId: 'a_5',
        authorId: 'u_ben',
        body: '412 metres before a shift. Ana, please sleep.',
        createdAt: now.subtract(const Duration(hours: 14)),
      ),
      Comment(
        id: 'c_6',
        activityId: 'a_5',
        authorId: currentUserId,
        body: 'The rain last night was something else. Thank you for this.',
        createdAt: now.subtract(const Duration(hours: 11)),
      ),
      Comment(
        id: 'c_7',
        activityId: 'a_6',
        authorId: 'u_dan',
        body: 'Two hours twenty. Next time wake me.',
        createdAt: now.subtract(const Duration(hours: 18)),
      ),
      Comment(
        id: 'c_8',
        activityId: 'a_7',
        authorId: currentUserId,
        body: 'Six more days. We are walking them with you.',
        createdAt: now.subtract(const Duration(minutes: 18)),
      ),
    ];

    // ---------------------------------------------------------- moderation ---
    final reports = <ModerationReport>[
      ModerationReport(
        id: 'r_1',
        targetType: ReportTargetType.comment,
        targetId: 'c_x1',
        targetExcerpt:
            'Cheap shoes at half price, message me — best deal in Manila!!',
        targetAuthorName: 'Pia Mendoza',
        reportedByName: 'Daniel Cruz',
        reason: 'Spam or advertising',
        createdAt: now.subtract(const Duration(hours: 5)),
        status: ReportStatus.pending,
      ),
      ModerationReport(
        id: 'r_2',
        targetType: ReportTargetType.activity,
        targetId: 'a_x2',
        targetExcerpt: 'Route appears to pass through a private residence.',
        targetAuthorName: 'Rex Santiago',
        reportedByName: 'Grace Tan',
        reason: 'Privacy concern',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
        status: ReportStatus.pending,
      ),
      ModerationReport(
        id: 'r_3',
        targetType: ReportTargetType.comment,
        targetId: 'c_x3',
        targetExcerpt: 'Nobody here actually prays, this app is a joke.',
        targetAuthorName: 'Pia Mendoza',
        reportedByName: 'Ana Villanueva',
        reason: 'Harassment',
        createdAt: now.subtract(const Duration(days: 3)),
        status: ReportStatus.resolved,
      ),
      ModerationReport(
        id: 'r_4',
        targetType: ReportTargetType.activity,
        targetId: 'a_x4',
        targetExcerpt: 'Title contains a phone number.',
        targetAuthorName: 'Rex Santiago',
        reportedByName: 'Jonas Lim',
        reason: 'Personal information',
        createdAt: now.subtract(const Duration(days: 6)),
        status: ReportStatus.dismissed,
      ),
    ];

    // -------------------------------------------------------- announcements ---
    final announcements = <Announcement>[
      Announcement(
        id: 'an_1',
        title: 'Parish walk this Saturday, 5:30am',
        body:
            'We start at the San Roque gate and finish at the shrine. Bring water. '
            'Log it in the app so we can see the whole route together afterwards.',
        audience: AnnouncementAudience.everyone,
        sentAt: daysAgo(2, hour: 10),
        sentByName: 'Ben Ocampo',
        recipientCount: 8,
      ),
      Announcement(
        id: 'an_2',
        title: 'New devotionals for the novena',
        body:
            'Three new prompts are up under Intercession. One per day for the '
            'first three days.',
        audience: AnnouncementAudience.activeMembers,
        sentAt: daysAgo(11, hour: 15),
        sentByName: 'Ben Ocampo',
        recipientCount: 7,
      ),
      Announcement(
        id: 'an_3',
        title: 'Moderation queue is live',
        body: 'Reports now land in the admin console. Please clear it weekly.',
        audience: AnnouncementAudience.admins,
        sentAt: daysAgo(19, hour: 9),
        sentByName: 'Ben Ocampo',
        recipientCount: 1,
      ),
    ];

    return MockSeed(
      users: users,
      activities: activities,
      devotionals: devotionals,
      comments: comments,
      encouragements: encouragements,
      follows: List.of(follows),
      reports: reports,
      announcements: announcements,
    );
  }

  /// Prompts offered by the "Add intentions" sheet so it never opens blank.
  static List<PrayerIntention> suggestedIntentions(DateTime now) => [
    PrayerIntention(
      id: 's_1',
      text: 'For my family',
      category: PrayerCategory.family,
      createdAt: now,
    ),
    PrayerIntention(
      id: 's_2',
      text: 'For someone who is ill',
      category: PrayerCategory.healing,
      createdAt: now,
    ),
    PrayerIntention(
      id: 's_3',
      text: 'For this street and the people on it',
      category: PrayerCategory.community,
      createdAt: now,
    ),
    PrayerIntention(
      id: 's_4',
      text: 'In thanks for this morning',
      category: PrayerCategory.gratitude,
      createdAt: now,
    ),
    PrayerIntention(
      id: 's_5',
      text: 'For a decision I have to make',
      category: PrayerCategory.guidance,
      createdAt: now,
    ),
    PrayerIntention(
      id: 's_6',
      text: 'For places at war',
      category: PrayerCategory.world,
      createdAt: now,
    ),
  ];

  /// The route the mock recording traces. Phase 3 replaces this with the
  /// device's location stream.
  static List<LatLng> mockRecordingRoute() =>
      RouteShapes.loop(mockCurrentLocation, radiusKm: 0.64, seed: 77, wobble: 0.34);

  /// Where the record screen centres its map. MOCK — no device GPS this phase.
  static const LatLng mockCurrentLocation = LatLng(14.5794, 121.0359);
}
