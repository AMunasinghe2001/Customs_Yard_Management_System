import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/core/db_client.dart'; // Adjust path if needed

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  final supabase = Supabase.instance.client;

  print('Fetching entries to fix...');
  final entries = await supabase.from('warehouse_entries').select('*, package_items(quantity, itemName:item_name, status)');
  
  for(var e in entries) {
     if (e['package_items'] != null) {
       final trueQuant = e['package_items']['quantity'];
       // If standard quantity was actually higher, and item count is equal to trueQuant (or 1 in bugged state)
       // Let's just fix the test packages for now. If there's an issue with 13 items...
       if (e['item_count'] == trueQuant && e['is_returned'] == true) {
         // Reset anything returned back to pending/held so the user can test again!
         print('Fixing \${e['id']} (Returned -> Held) for testing');
         await supabase.from('warehouse_entries').update({
           'item_count': trueQuant,
           'is_returned': false,
         }).eq('id', e['id']);
         await supabase.from('package_items').update({'status': 'pending'}).eq('id', e['package_item_id']);
         print('Done.');
       }
     }
  }
}
