import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/core/db_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const FixApp());
}

class FixApp extends StatefulWidget {
  const FixApp({super.key});

  @override
  State<FixApp> createState() => _FixAppState();
}

class _FixAppState extends State<FixApp> {
  String status = "Starting...";

  @override
  void initState() {
    super.initState();
    _fixData();
  }

  Future<void> _fixData() async {
    try {
      final supabase = Supabase.instance.client;
      final entries = await supabase.from('warehouse_entries').select('*, package_items(quantity, itemName:item_name, status)');
      
      for(var e in entries) {
         if (e['package_items'] != null) {
           final trueQuant = e['package_items']['quantity'];
           // If it's 1 but should be > 1
           if (e['item_count'] == 1 && trueQuant > 1) {
             print('Fixing id ${e["id"]} from 1 to $trueQuant');
             // Always reset it back to held if it was accidentally returned, so the user can test cleanly
             await supabase.from('warehouse_entries').update({
               'item_count': trueQuant,
               'is_returned': false,
               'return_notes': null,
               'returned_at': null,
             }).eq('id', e['id']);
             await supabase.from('package_items').update({'status': 'pending'}).eq('id', e['package_item_id']);
             setState(() { status += "\nFixed entry for $trueQuant packages."; });
           }
         }
      }
      setState(() { status += "\n\nDONE!"; });
    } catch (e) {
      setState(() { status += "\nError: $e"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(status, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}
