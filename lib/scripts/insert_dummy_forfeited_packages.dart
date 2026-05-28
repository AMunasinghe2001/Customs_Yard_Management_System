import 'package:supabase_flutter/supabase_flutter.dart';

/// Script to insert dummy forfeited packages data
/// Run this from main.dart or a test environment
Future<void> insertDummyForfeitedPackages() async {
  final supabase = Supabase.instance.client;

  try {
    // Get admin user
    final adminResponse = await supabase
        .from('profiles')
        .select('id')
        .eq('role', 'admin')
        .limit(1)
        .single();

    final adminId = adminResponse['id'] as String;

    // Get some existing packages
    final packagesResponse = await supabase
        .from('packages')
        .select('id')
        .limit(10);

    final packages = packagesResponse as List;

    if (packages.length < 6) {
      print('⚠️ Need at least 6 packages in database. Found: ${packages.length}');
      return;
    }

    // Prepare dummy data
    final dummyData = [
      {
        'package_id': packages[0]['id'],
        'sr_number': 'SR-2026-00105',
        'consignee_name': 'ABC Trading Company Ltd',
        'forfeited_at': DateTime.now().subtract(Duration(days: 15)).toIso8601String(),
        'appeal_deadline': DateTime.now().add(Duration(days: 15)).toIso8601String(),
        'reason': 'Non-compliant documentation',
        'created_by': adminId,
      },
      {
        'package_id': packages[1]['id'],
        'sr_number': 'SR-2026-00106',
        'consignee_name': 'XYZ Imports Pvt Ltd',
        'forfeited_at': DateTime.now().subtract(Duration(days: 18)).toIso8601String(),
        'appeal_deadline': DateTime.now().add(Duration(days: 12)).toIso8601String(),
        'reason': 'Expired permits',
        'created_by': adminId,
      },
      {
        'package_id': packages[2]['id'],
        'sr_number': 'SR-2026-00107',
        'consignee_name': 'Global Logistics Co',
        'forfeited_at': DateTime.now().subtract(Duration(days: 20)).toIso8601String(),
        'appeal_deadline': DateTime.now().add(Duration(days: 10)).toIso8601String(),
        'reason': 'Restricted items detected',
        'created_by': adminId,
      },
      // Expired appeals
      {
        'package_id': packages[3]['id'],
        'sr_number': 'SR-2026-00102',
        'consignee_name': 'Prime Importers Inc',
        'forfeited_at': DateTime.now().subtract(Duration(days: 35)).toIso8601String(),
        'appeal_deadline': DateTime.now().subtract(Duration(days: 5)).toIso8601String(),
        'reason': 'Missing customs declaration',
        'created_by': adminId,
      },
      {
        'package_id': packages[4]['id'],
        'sr_number': 'SR-2026-00103',
        'consignee_name': 'Metro Trade Solutions',
        'forfeited_at': DateTime.now().subtract(Duration(days: 40)).toIso8601String(),
        'appeal_deadline': DateTime.now().subtract(Duration(days: 10)).toIso8601String(),
        'reason': 'Undervalued goods',
        'created_by': adminId,
      },
      {
        'package_id': packages[5]['id'],
        'sr_number': 'SR-2026-00104',
        'consignee_name': 'Universal Shipping Ltd',
        'forfeited_at': DateTime.now().subtract(Duration(days: 45)).toIso8601String(),
        'appeal_deadline': DateTime.now().subtract(Duration(days: 15)).toIso8601String(),
        'reason': 'Prohibited items found',
        'created_by': adminId,
      },
    ];

    // Insert data
    final response = await supabase.from('forfeited_packages').insert(dummyData);

    print('✅ Successfully inserted ${dummyData.length} dummy forfeited packages!');
    print('Response: $response');
  } catch (e) {
    print('❌ Error inserting dummy data: $e');
  }
}

/// Script to delete all dummy forfeited packages (for cleanup)
Future<void> deleteDummyForfeitedPackages() async {
  final supabase = Supabase.instance.client;

  try {
    final response = await supabase
        .from('forfeited_packages')
        .delete()
        .in_('sr_number', [
          'SR-2026-00102',
          'SR-2026-00103',
          'SR-2026-00104',
          'SR-2026-00105',
          'SR-2026-00106',
          'SR-2026-00107',
        ]);

    print('✅ Successfully deleted dummy forfeited packages!');
  } catch (e) {
    print('❌ Error deleting dummy data: $e');
  }
}
