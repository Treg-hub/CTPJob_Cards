import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/apk_install_service.dart';
import '../services/kiosk_mode_service.dart';
import '../theme/app_theme.dart';

/// Full-screen update flow: notes → download progress → system installer.
///
/// Used for soft prompts, RC force updates, and the kill-switch screen.
/// Primary path is in-app APK download + install; browser is a fallback.
class UpdateAvailableScreen extends StatefulWidget {
  final String version;
  final String? releaseNotes;
  final String downloadUrl;
  final bool forceUpdate;
  final String? apkSha256;
  final String? latestBuild;

  /// When true, wraps itself in a dark [MaterialApp] for pre-runApp kill-switch.
  final bool standalone;

  const UpdateAvailableScreen({
    super.key,
    required this.version,
    required this.downloadUrl,
    this.releaseNotes,
    this.forceUpdate = false,
    this.apkSha256,
    this.latestBuild,
    this.standalone = false,
  });

  @override
  State<UpdateAvailableScreen> createState() => _UpdateAvailableScreenState();
}

enum _UpdatePhase { idle, downloading, readyToInstall, installing, error }

class _UpdateAvailableScreenState extends State<UpdateAvailableScreen>
    with WidgetsBindingObserver {
  final _install = ApkInstallService();

  _UpdatePhase _phase = _UpdatePhase.idle;
  double? _progress; // 0..1 when total known
  String? _statusLine;
  String? _error;
  File? _apkFile;
  bool _kioskActive = false;
  bool _awaitingInstallPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadKiosk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_phase == _UpdatePhase.downloading) {
      _install.cancelDownload();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingInstallPermission) {
      _awaitingInstallPermission = false;
      // User may have granted install permission — retry install if we have a file.
      if (_apkFile != null && mounted) {
        unawaited(_installDownloaded());
      }
    }
  }

  Future<void> _loadKiosk() async {
    if (kIsWeb) return;
    final enabled = await KioskModeService.instance.isKioskModeEnabled();
    final lockTask = await KioskModeService.instance.isLockTaskActive();
    if (mounted) {
      setState(() => _kioskActive = enabled || lockTask);
    }
  }

  Future<void> _startDownloadAndInstall() async {
    if (widget.downloadUrl.isEmpty) {
      setState(() {
        _phase = _UpdatePhase.error;
        _error = 'No download URL configured. Ask an administrator.';
      });
      return;
    }
    if (_kioskActive) {
      setState(() {
        _phase = _UpdatePhase.error;
        _error =
            'This device is in Kiosk Mode. Exit Kiosk Mode from Settings (admin) before installing an update, then try again.';
      });
      return;
    }

    setState(() {
      _phase = _UpdatePhase.downloading;
      _progress = null;
      _statusLine = 'Starting download…';
      _error = null;
    });

    try {
      final hint = widget.latestBuild != null && widget.latestBuild!.isNotEmpty
          ? 'ctp-job-cards-${widget.latestBuild}.apk'
          : 'ctp-job-cards-v${widget.version}.apk';

      final file = await _install.downloadApk(
        widget.downloadUrl,
        fileNameHint: hint,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            if (total != null && total > 0) {
              // Clamp so a wrong Content-Length never shows >100%.
              _progress = (received / total).clamp(0.0, 1.0);
              _statusLine =
                  'Downloading… ${_formatBytes(received)} / ${_formatBytes(total)}';
            } else {
              _progress = null;
              _statusLine = 'Downloading… ${_formatBytes(received)}';
            }
          });
        },
      );

      if (mounted) {
        final size = await file.length();
        setState(() {
          _progress = 1.0;
          _statusLine = 'Download complete (${_formatBytes(size)})';
        });
      }

      await _install.verifySha256(file, widget.apkSha256);
      if (!mounted) return;
      setState(() {
        _apkFile = file;
        _phase = _UpdatePhase.readyToInstall;
        _statusLine = 'Download complete';
      });
      await _installDownloaded();
    } on ApkInstallException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = e.message;
        _statusLine = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = 'Download failed: $e';
        _statusLine = null;
      });
    }
  }

  Future<void> _installDownloaded() async {
    final file = _apkFile;
    if (file == null) return;

    final canInstall = await _install.canInstallPackages();
    if (!canInstall) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.readyToInstall;
        _statusLine =
            'Android needs permission for CTP Job Cards to install updates.';
      });
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Allow install permission'),
          content: const Text(
            'On the next screen, allow CTP Job Cards to install apps / unknown apps, then return here. The installer will open automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandOrange,
                foregroundColor: Colors.black,
              ),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (go == true) {
        _awaitingInstallPermission = true;
        try {
          await _install.openInstallPermissionSettings();
        } catch (e) {
          if (mounted) {
            setState(() {
              _phase = _UpdatePhase.error;
              _error = 'Could not open install settings: $e';
            });
          }
        }
      }
      return;
    }

    setState(() {
      _phase = _UpdatePhase.installing;
      _statusLine = 'Opening system installer…';
      _error = null;
    });

    try {
      await _install.installApk(file);
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.readyToInstall;
        _statusLine =
            'Confirm the update in the system installer, then reopen CTP Job Cards.';
      });
    } on ApkInstallException catch (e) {
      if (!mounted) return;
      // Permission race: open settings path.
      if (e.message.toLowerCase().contains('permission')) {
        setState(() {
          _phase = _UpdatePhase.readyToInstall;
          _error = e.message;
        });
        return;
      }
      setState(() {
        _phase = _UpdatePhase.error;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _error = 'Could not open installer: $e';
      });
    }
  }

  Future<void> _openBrowserFallback() async {
    if (widget.downloadUrl.isEmpty) return;
    try {
      await launchUrl(
        Uri.parse(widget.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link.\n${widget.downloadUrl}')),
      );
    }
  }

  void _cancelDownload() {
    _install.cancelDownload();
    setState(() {
      _phase = _UpdatePhase.idle;
      _progress = null;
      _statusLine = 'Download cancelled';
    });
  }

  static String _formatBytes(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      final kb = bytes / 1024;
      return kb < 10
          ? '${kb.toStringAsFixed(1)} KB'
          : '${kb.toStringAsFixed(0)} KB';
    }
    final mb = bytes / (1024 * 1024);
    // One decimal for multi‑MB APKs so ~44 MB does not look like "22".
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.standalone) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(primary: kBrandOrange),
        ),
        home: body,
      );
    }
    return body;
  }

  Widget _buildBody(BuildContext context) {
    final notes = widget.releaseNotes?.trim();
    final versionLabel = widget.latestBuild != null &&
            widget.latestBuild!.isNotEmpty
        ? 'v${widget.version} (build ${widget.latestBuild})'
        : 'v${widget.version}';

    return PopScope(
      canPop: !widget.forceUpdate,
      child: Scaffold(
        backgroundColor: widget.standalone ? Colors.black : null,
        appBar: widget.forceUpdate
            ? null
            : AppBar(
                title: const Text('Update available'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.forceUpdate) ...[
                  const SizedBox(height: 12),
                  Icon(
                    Icons.system_update,
                    size: 72,
                    color: kBrandOrange,
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  widget.forceUpdate
                      ? 'Update required'
                      : 'Update available',
                  textAlign:
                      widget.forceUpdate ? TextAlign.center : TextAlign.start,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  versionLabel,
                  textAlign:
                      widget.forceUpdate ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    color: kBrandOrange,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                if (notes != null && notes.isNotEmpty) ...[
                  Text(
                    "What's new",
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(notes, style: const TextStyle(height: 1.4)),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      widget.forceUpdate
                          ? 'Please install the latest version of CTP Job Cards to continue.\n\n'
                              'On first update, Android may ask you to allow CTP Job Cards to install apps — open Settings, allow it, then return here.'
                          : 'A newer version is ready. Download and install without leaving the app.\n\n'
                              'First time: Android may require “Allow from this source” for CTP Job Cards before the installer opens.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (_kioskActive) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Kiosk Mode is on. Exit Kiosk Mode before installing, or the system installer may be blocked.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
                if (_statusLine != null) ...[
                  const SizedBox(height: 12),
                  Text(_statusLine!, textAlign: TextAlign.center),
                ],
                if (_phase == _UpdatePhase.downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _progress,
                    color: kBrandOrange,
                    backgroundColor: kBrandOrange.withValues(alpha: 0.2),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, height: 1.3),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                ..._actionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actionButtons() {
    final busy = _phase == _UpdatePhase.downloading ||
        _phase == _UpdatePhase.installing;

    return [
      if (_phase == _UpdatePhase.downloading)
        OutlinedButton(
          onPressed: _cancelDownload,
          child: const Text('Cancel download'),
        )
      else ...[
        ElevatedButton.icon(
          onPressed: busy
              ? null
              : (_phase == _UpdatePhase.readyToInstall && _apkFile != null
                  ? () => unawaited(_installDownloaded())
                  : () => unawaited(_startDownloadAndInstall())),
          icon: Icon(
            _phase == _UpdatePhase.readyToInstall
                ? Icons.install_mobile
                : Icons.download,
          ),
          label: Text(
            _phase == _UpdatePhase.readyToInstall && _apkFile != null
                ? 'Install now'
                : (_phase == _UpdatePhase.error
                    ? 'Retry download & install'
                    : 'Download & install'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: kBrandOrange,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : _openBrowserFallback,
          child: const Text('Open download in browser'),
        ),
        if (!widget.forceUpdate)
          TextButton(
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Later'),
          ),
      ],
    ];
  }
}
