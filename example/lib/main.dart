import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:reachbell/reachbell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  ReachBell.init(apiKey: 'rb_live_your_public_key');
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  String _status = 'Not registered';

  Future<void> _register() async {
    try {
      final result = await ReachBell.register(externalId: 'user_42');
      await ReachBell.tag(['example']);
      setState(
          () => _status = 'Registered ${result.subscriberId ?? result.token}');
    } on ReachBellException catch (error) {
      setState(
          () => _status = 'Error ${error.statusCode ?? '-'}: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ReachBell example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _register,
                child: const Text('Enable notifications'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
