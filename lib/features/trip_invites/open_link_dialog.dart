import 'package:flutter/material.dart';

import '../../config/server_config.dart';
import '../../deep_links/deep_link.dart';

/// Asks for a pasted Trek link (e.g. a trip invite link shared in a chat)
/// and returns the [DeepLink] it opens, or `null` if cancelled.
///
/// A web link must be on the configured server ([config]'s public or
/// private URL host) — invite tokens and trip ids only mean something to
/// the server that issued them.
Future<DeepLink?> showOpenLinkDialog(
  BuildContext context, {
  required ServerConfig? config,
}) {
  return showDialog<DeepLink>(
    context: context,
    builder: (context) => _OpenLinkDialog(config: config),
  );
}

/// Validates [text] as a link this app can open against [config]; returns
/// the parsed link or an error message.
({DeepLink? link, String? error}) validateLinkText(
  String text,
  ServerConfig? config,
) {
  final link = DeepLink.tryParseText(text);
  if (link == null) {
    return (link: null, error: 'Paste a Trek trip or invite link.');
  }
  final host = link.sourceHost;
  if (host != null && config != null) {
    final serverHosts = {
      for (final url in [config.publicUrl, config.privateUrl])
        if (url != null) Uri.tryParse(url)?.host.toLowerCase(),
    };
    if (!serverHosts.contains(host)) {
      return (
        link: null,
        error: 'This link is for a different Trek server ($host).',
      );
    }
  }
  return (link: link, error: null);
}

class _OpenLinkDialog extends StatefulWidget {
  const _OpenLinkDialog({required this.config});

  final ServerConfig? config;

  @override
  State<_OpenLinkDialog> createState() => _OpenLinkDialogState();
}

class _OpenLinkDialogState extends State<_OpenLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final result = validateLinkText(_controller.text, widget.config);
    if (result.link == null) {
      setState(() => _error = result.error);
      return;
    }
    Navigator.of(context).pop(result.link);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open a Trek link'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'https://trek.example.com/join/…',
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open')),
      ],
    );
  }
}
