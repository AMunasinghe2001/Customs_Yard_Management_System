import 'package:supabase/supabase.dart';
void main() async {
  final client = SupabaseClient('https://tstlaauujhrrpjxhvorf.supabase.co', 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa');
  try {
    final res = await client.rest.rpc('get_service_role');
    print(res);
  } catch(e) { print(e); }
}
