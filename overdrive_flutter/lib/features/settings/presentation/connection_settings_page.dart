import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../services/backend_service.dart';
import '../../../services/connection_config.dart';
import '../../../services/connection_controller.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../theme/dimensions.dart';

/// Sub-page for editing the head-unit connection.
///
/// Lets the user paste the base URL (LAN or tunnel), assign a friendly
/// label, and run a one-shot connection test that mirrors what the
/// dashboard's poller does.
class ConnectionSettingsPage extends ConsumerStatefulWidget {
  const ConnectionSettingsPage({super.key});

  @override
  ConsumerState<ConnectionSettingsPage> createState() =>
      _ConnectionSettingsPageState();
}

class _ConnectionSettingsPageState
    extends ConsumerState<ConnectionSettingsPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _labelCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _initialized = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Seed the controllers once from the persisted config. We can't do this
    // in initState because the widget rebuilds when the controller updates
    // and we'd clobber the user's in-progress edit.
    if (!_initialized) {
      final config = ref.read(connectionControllerProvider);
      _urlCtrl.text = config.baseUrl;
      _labelCtrl.text = config.label;
      _initialized = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Head unit connection')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.space16),
          children: [
            Text(
              'The OverDrive head unit (the APK running on your car) exposes '
              'an HTTP server. Paste its address here. You can use the LAN '
              'address when on the same WiFi, or any tunnel URL (Cloudflared, '
              'Zrok, Tailscale) when remote.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppDimensions.space24),

            TextFormField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Home LAN, Zrok, Tailscale',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: AppDimensions.space12),

            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://192.168.1.50:8080',
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: _validateUrl,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppDimensions.space16),

            // Live status while the user types.
            const _LiveProbeCard(),
            const SizedBox(height: AppDimensions.space16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: AppDimensions.space12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveAndProbe,
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('Save & test'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.space16),
            if (ref.watch(connectionControllerProvider).isConfigured)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear connection'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _validateUrl(String? value) {
    final s = value?.trim() ?? '';
    if (s.isEmpty) return 'Required';
    final uri = Uri.tryParse(s);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Must start with http:// or https://';
    }
    if (uri.host.isEmpty) return 'Host missing';
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final config = ConnectionConfig(
      baseUrl: _urlCtrl.text.trim(),
      label: _labelCtrl.text.trim().isEmpty
          ? 'Head unit'
          : _labelCtrl.text.trim(),
    );
    await ref.read(connectionControllerProvider.notifier).update(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection saved.')),
      );
    }
  }

  Future<void> _saveAndProbe() async {
    await _save();
    if (!mounted) return;
    await ref.read(connectionProbeProvider.notifier).run();
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear connection?'),
        content: const Text(
            'The dashboard and features that depend on the head unit will be disabled.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(connectionControllerProvider.notifier).clear();
    _urlCtrl.clear();
    _labelCtrl.clear();
  }
}

/// One-shot connection probe triggered by the "Save & test" button.
///
/// Separate from [connectionStatusProvider] (which polls continuously while
/// the dashboard is mounted) so we get a single, immediate result without
/// disrupting the polling lifecycle.
final connectionProbeProvider =
    NotifierProvider<_ConnectionProbe, AsyncValue<String?>>(
  _ConnectionProbe.new,
);

class _ConnectionProbe extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() => const AsyncData(null);

  Future<void> run() async {
    state = const AsyncLoading();
    final backend = ref.read(backendServiceProvider);
    final result = await backend.healthCheck();
    switch (result) {
      case Success(:final data):
        final msg = data.version != null
            ? 'Reachable — head unit ${data.version}'
            : 'Reachable.';
        state = AsyncData(msg);
      case Failure(:final error):
        state = AsyncError(error, StackTrace.current);
    }
  }
}

class _LiveProbeCard extends ConsumerWidget {
  const _LiveProbeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.watch(connectionProbeProvider);

    return AppCard(
      child: probe.when(
        data: (msg) => msg == null
            ? const StatusChip(
                icon: Icons.touch_app_outlined,
                label: 'Test',
                value: 'Press “Save & test”',
                severity: StatusSeverity.idle,
              )
            : StatusChip(
                icon: Icons.check_circle_rounded,
                label: 'Test result',
                value: msg,
                severity: StatusSeverity.success,
              ),
        loading: () => const StatusChip(
          icon: Icons.sync_rounded,
          label: 'Testing',
          value: 'Probing head unit…',
          severity: StatusSeverity.info,
        ),
        error: (e, _) => StatusChip(
          icon: Icons.error_outline_rounded,
          label: 'Test failed',
          value: (e is AppError) ? e.message : '$e',
          severity: StatusSeverity.danger,
        ),
      ),
    );
  }
}
