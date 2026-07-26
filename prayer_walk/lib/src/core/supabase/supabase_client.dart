import 'package:supabase_flutter/supabase_flutter.dart';

/// The one initialized Supabase client, for reuse across the app.
///
/// Safe to read only after [Supabase.initialize] has completed in `main`. It is
/// a getter rather than a captured `final` so nothing evaluates it before that.
SupabaseClient get supabase => Supabase.instance.client;
