import 'dart:convert';
import 'dart:io';
import 'package:sorynth/core/config/supabase_credentials.dart';
import 'package:sorynth/core/constants/app_constants.dart';

void main(List<String> args) async {
  final projectUrl = AppConstants.defaultSupabaseUrl;
  final apiKey = args.isNotEmpty && args[0].isNotEmpty
      ? args[0].trim()
      : SupabaseCredentials.publishableKey.trim();

  stdout.writeln('====================================================');
  stdout.writeln('SORYNTH SUPABASE LIVE CONNECTIVITY TESTER');
  stdout.writeln('====================================================');
  stdout.writeln('Project URL: $projectUrl');
  stdout.writeln('Key configured: ${apiKey.isNotEmpty ? "YES (${apiKey.substring(0, 10)}...)" : "NO (Awaiting Key)"}');

  if (apiKey.isEmpty) {
    stdout.writeln('\n[STATUS] Awaiting publishable key.');
    stdout.writeln('Paste your key into: lib/core/config/supabase_credentials.dart');
    stdout.writeln('Or run: dart run tool/verify_supabase_connection.dart <YOUR_KEY>');
    exit(1);
  }

  final client = HttpClient();

  // 1. Boundary Validation RPC Test (Non-destructive: Zero records committed)
  stdout.writeln('\n1. Non-Destructive Boundary Probe on submit_sos_alert...');
  final boundaryPayload = {
    'p_emergency_code': 'SOR_PROBE_BOUNDARY',
    'p_sender_name': 'Automated Boundary Verifier',
    'p_sender_phone': null,
    'p_emergency_type': 'OTHER',
    'p_custom_message': 'Non-destructive probe',
    'p_latitude': 999.0, // Intentionally out-of-bounds to trigger rollback
    'p_longitude': 74.8560,
    'p_accuracy_meters': 5.0,
    'p_communication_method': 'INTERNET',
    'p_hop_count': 0,
    'p_relay_path': <String>[],
  };

  try {
    final req = await client.postUrl(Uri.parse('$projectUrl/rest/v1/rpc/submit_sos_alert'));
    req.headers.set('apikey', apiKey);
    req.headers.set('Authorization', 'Bearer $apiKey');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(boundaryPayload));

    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();

    stdout.writeln('Boundary Test HTTP Status: ${resp.statusCode}');
    stdout.writeln('Boundary Test Response: $respBody');

    if (respBody.contains('Invalid GPS coordinates provided')) {
      stdout.writeln('✓ PASSED: Database function executed, validated coordinates, and rolled back with 0 inserted rows.');
    } else {
      stdout.writeln('Response: $respBody');
    }
  } catch (e) {
    stdout.writeln('✗ Error testing RPC boundary: $e');
  }

  // 2. Verified Active Submission Test
  stdout.writeln('\n2. Live Submission Probe on submit_sos_alert...');
  final testEmergencyCode = 'SOR_PROBE_${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  final validPayload = {
    'p_emergency_code': testEmergencyCode,
    'p_sender_name': 'SORYNTH Live Verifier',
    'p_sender_phone': '+910000000000',
    'p_emergency_type': 'OTHER',
    'p_custom_message': 'Automated Supabase connectivity verification probe.',
    'p_latitude': 12.914142,
    'p_longitude': 74.856012,
    'p_accuracy_meters': 4.5,
    'p_communication_method': 'INTERNET',
    'p_hop_count': 0,
    'p_relay_path': <String>[],
  };

  try {
    final req = await client.postUrl(Uri.parse('$projectUrl/rest/v1/rpc/submit_sos_alert'));
    req.headers.set('apikey', apiKey);
    req.headers.set('Authorization', 'Bearer $apiKey');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(validPayload));

    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();

    stdout.writeln('Valid Insertion HTTP Status: ${resp.statusCode}');
    stdout.writeln('Valid Insertion Response: $respBody');

    final parsed = jsonDecode(respBody);
    if (resp.statusCode == 200 && parsed is Map && parsed['success'] == true) {
      stdout.writeln('✓ PASSED: Valid SOS successfully created and acknowledged by Supabase (HTTP 200).');

      // Stand down / Cancel probe emergency immediately so no open crisis remains
      stdout.writeln('\n3. Cleaning up probe record via cancel_emergency RPC...');
      final cancelReq = await client.postUrl(Uri.parse('$projectUrl/rest/v1/rpc/cancel_emergency'));
      cancelReq.headers.set('apikey', apiKey);
      cancelReq.headers.set('Authorization', 'Bearer $apiKey');
      cancelReq.headers.set('Content-Type', 'application/json');
      cancelReq.write(jsonEncode({
        'p_emergency_code': testEmergencyCode,
        'p_reason': 'Automated probe cleanup',
      }));

      final cancelResp = await cancelReq.close();
      final cancelBody = await cancelResp.transform(utf8.decoder).join();
      stdout.writeln('Cleanup Status: ${cancelResp.statusCode} -> $cancelBody');
      final cancelParsed = jsonDecode(cancelBody);
      if (cancelResp.statusCode == 200 && cancelParsed is Map && cancelParsed['status'] == 'CANCELLED') {
        stdout.writeln('✓ PASSED: Test probe stood down (CANCELLED). No open emergency remains in the system.');
      }
    }
  } catch (e) {
    stdout.writeln('✗ Error during live probe: $e');
  } finally {
    client.close();
  }
}
