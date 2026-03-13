import 'package:supabase_flutter/supabase_flutter.dart';

// ⚠️ Replace with your Supabase project credentials
// Get from: Supabase Dashboard → Project Settings → API
const String supabaseUrl = 'https://tstlaauujhrrpjxhvorf.supabase.co';
const String supabaseAnonKey = 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa';

SupabaseClient get supabase => Supabase.instance.client;
