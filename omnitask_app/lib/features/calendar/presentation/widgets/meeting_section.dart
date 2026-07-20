import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../models/activity.dart';
import 'meeting_field.dart';

/// Muestra el link de reunión (si existe) y sus acciones — copiar, abrir y
/// compartir (SPEC-003 §3 RF3-RF7). Si no hay link, no se renderiza nada
/// (RF7: acciones ocultas, no solo deshabilitadas).
class MeetingSection extends StatelessWidget {
  const MeetingSection({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final url = activity.meetingUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final providerLabel =
        MeetingField.providerLabels[activity.meetingProvider] ?? 'Reunión';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.videocam_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(providerLabel, style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(url, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copy(context, url),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copiar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open(context, url),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _share(context, url),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Compartir'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copiado al portapapeles')),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final launched = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || launched) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el link de la reunión')),
    );
  }

  Future<void> _share(BuildContext context, String url) async {
    final title = activity.title;
    final text = 'Te comparto el link de la reunión "$title": $url';
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
