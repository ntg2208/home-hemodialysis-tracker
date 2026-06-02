import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/rest_client.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/secure_store.dart';

/// Pre-auth gate. Single API-key field, verified against the API before saving.
/// No drawer, no Chat FAB — it lives outside the app shell.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Enter your main API key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Probe an authenticated endpoint to verify the key before we store it.
      final client = ref.read(restClientFactoryProvider)(key);
      await client.get('/api/treatment/token');
      await ref.read(authControllerProvider).signIn(AuthSettings(mainKey: key));
      // Router redirect (refreshListenable) takes us to Treatment Home.
    } on CloudRunError catch (e) {
      setState(() {
        _error = e.code == CloudErrorCode.unauthorized
            ? 'That key was rejected.'
            : 'Could not verify the key. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.hd;
    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.monitor_heart_outlined, size: 40, color: t.accent),
                  const SizedBox(height: 16),
                  Text('Home HD',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Main API key',
                      prefixIcon: Icon(Icons.key),
                    ),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: t.danger)),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: t.accentOn))
                        : const Icon(Icons.save_outlined),
                    label: Text(_busy ? 'Verifying…' : 'Save and continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
