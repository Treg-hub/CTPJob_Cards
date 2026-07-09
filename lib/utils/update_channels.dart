/// Pure cohort / channel resolution for targeted in-app APK updates.
///
/// Match priority (first enabled match wins):
/// 1. Explicit clock list (`match.clockNos`)
/// 2. Department list (`match.departments`)
/// 3. Channel id `default`
///
/// Legacy flat `settings/app` publish fields are treated as the `default`
/// channel so older clients and new clients stay compatible.

class UpdateChannelMatch {
  const UpdateChannelMatch({
    this.clockNos = const [],
    this.departments = const [],
  });

  final List<String> clockNos;
  final List<String> departments;

  bool get isEmpty => clockNos.isEmpty && departments.isEmpty;

  Map<String, dynamic> toMap() => {
        if (clockNos.isNotEmpty) 'clockNos': clockNos,
        if (departments.isNotEmpty) 'departments': departments,
      };

  factory UpdateChannelMatch.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const UpdateChannelMatch();
    final clocks = (m['clockNos'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    final depts = (m['departments'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    return UpdateChannelMatch(clockNos: clocks, departments: depts);
  }
}

class UpdateChannel {
  const UpdateChannel({
    required this.id,
    this.enabled = true,
    this.match = const UpdateChannelMatch(),
    this.latestVersion = '',
    this.latestBuild = '',
    this.downloadUrl = '',
    this.releaseNotes = '',
    this.apkSha256 = '',
    this.forceUpdate = false,
  });

  final String id;
  final bool enabled;
  final UpdateChannelMatch match;
  final String latestVersion;
  final String latestBuild;
  final String downloadUrl;
  final String releaseNotes;
  final String apkSha256;
  final bool forceUpdate;

  bool get hasPublishMetadata =>
      latestVersion.trim().isNotEmpty || latestBuild.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'match': match.toMap(),
        'latestVersion': latestVersion,
        'latestBuild': latestBuild,
        'downloadUrl': downloadUrl,
        'releaseNotes': releaseNotes,
        'apkSha256': apkSha256,
        'forceUpdate': forceUpdate,
      };

  factory UpdateChannel.fromMap(String id, Map<String, dynamic>? m) {
    m ??= {};
    return UpdateChannel(
      id: id,
      enabled: m['enabled'] != false,
      match: UpdateChannelMatch.fromMap(
        m['match'] is Map
            ? Map<String, dynamic>.from(m['match'] as Map)
            : null,
      ),
      latestVersion: (m['latestVersion'] ?? '').toString(),
      latestBuild: (m['latestBuild'] ?? '').toString(),
      downloadUrl: (m['downloadUrl'] ?? '').toString(),
      releaseNotes: (m['releaseNotes'] ?? '').toString(),
      apkSha256: (m['apkSha256'] ?? '').toString(),
      forceUpdate: m['forceUpdate'] == true,
    );
  }

  UpdateChannel copyWith({
    bool? enabled,
    UpdateChannelMatch? match,
    String? latestVersion,
    String? latestBuild,
    String? downloadUrl,
    String? releaseNotes,
    String? apkSha256,
    bool? forceUpdate,
  }) =>
      UpdateChannel(
        id: id,
        enabled: enabled ?? this.enabled,
        match: match ?? this.match,
        latestVersion: latestVersion ?? this.latestVersion,
        latestBuild: latestBuild ?? this.latestBuild,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        releaseNotes: releaseNotes ?? this.releaseNotes,
        apkSha256: apkSha256 ?? this.apkSha256,
        forceUpdate: forceUpdate ?? this.forceUpdate,
      );
}

/// True when [channel] matches this user (clock / department).
/// The `default` channel always matches (caller still checks [enabled]).
bool channelMatchesUser(
  UpdateChannel channel, {
  required String? clockNo,
  required String? department,
}) {
  if (channel.id == 'default') return true;

  final clock = (clockNo ?? '').trim();
  if (clock.isNotEmpty && channel.match.clockNos.isNotEmpty) {
    final set = channel.match.clockNos.map((c) => c.trim()).toSet();
    if (set.contains(clock)) return true;
  }

  final dept = (department ?? '').trim().toLowerCase();
  if (dept.isNotEmpty && channel.match.departments.isNotEmpty) {
    for (final d in channel.match.departments) {
      if (d.trim().toLowerCase() == dept) return true;
    }
  }

  // Non-default channel with empty match matches nobody.
  return false;
}

/// Priority: any non-default matching channel first (testers/ink by map
/// iteration order with clock-list channels typically listed first in admin
/// save order), then `default`.
///
/// Prefer [preferredOrder] when provided: `testers`, `ink`, then others, then
/// `default`.
UpdateChannel? resolveUpdateChannel(
  List<UpdateChannel> channels, {
  required String? clockNo,
  required String? department,
  List<String> preferredOrder = const ['testers', 'ink'],
}) {
  final enabled = channels.where((c) => c.enabled).toList();
  if (enabled.isEmpty) return null;

  final byId = {for (final c in enabled) c.id: c};

  // 1) Preferred named cohorts in order (if they match).
  for (final id in preferredOrder) {
    final c = byId[id];
    if (c == null) continue;
    if (channelMatchesUser(c, clockNo: clockNo, department: department)) {
      // Only win if match is non-empty OR id is default (default handled later).
      if (c.id != 'default' &&
          (c.match.clockNos.isNotEmpty || c.match.departments.isNotEmpty)) {
        if (_explicitMatch(c, clockNo: clockNo, department: department)) {
          return c;
        }
      }
    }
  }

  // 2) Any other non-default enabled channel with explicit match.
  for (final c in enabled) {
    if (c.id == 'default') continue;
    if (preferredOrder.contains(c.id)) continue;
    if (_explicitMatch(c, clockNo: clockNo, department: department)) {
      return c;
    }
  }

  // 3) Default channel, else first enabled.
  if (byId.containsKey('default')) return byId['default'];
  return enabled.isNotEmpty ? enabled.first : null;
}

bool _explicitMatch(
  UpdateChannel c, {
  required String? clockNo,
  required String? department,
}) {
  if (c.match.isEmpty) return false;
  final clock = (clockNo ?? '').trim();
  if (clock.isNotEmpty &&
      c.match.clockNos.map((x) => x.trim()).contains(clock)) {
    return true;
  }
  final dept = (department ?? '').trim().toLowerCase();
  if (dept.isNotEmpty) {
    for (final d in c.match.departments) {
      if (d.trim().toLowerCase() == dept) return true;
    }
  }
  return false;
}

/// Parse `updateChannels` map from Firestore; empty if missing.
List<UpdateChannel> parseUpdateChannels(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <UpdateChannel>[];
  for (final e in raw.entries) {
    final id = e.key.toString();
    if (e.value is Map) {
      out.add(
        UpdateChannel.fromMap(id, Map<String, dynamic>.from(e.value as Map)),
      );
    }
  }
  return out;
}

/// Build channel list from settings/app, applying legacy flat fields as
/// the default channel when `updateChannels` is absent or incomplete.
List<UpdateChannel> channelsFromSettingsApp(Map<String, dynamic> data) {
  final parsed = parseUpdateChannels(
    data['updateChannels'] is Map
        ? Map<String, dynamic>.from(data['updateChannels'] as Map)
        : null,
  );

  final sharedUrl = (data['updateDownloadUrl'] ?? '').toString();
  final legacyDefault = UpdateChannel(
    id: 'default',
    enabled: true,
    latestVersion: (data['publishedLatestVersion'] ?? '').toString(),
    latestBuild: (data['publishedLatestBuild'] ?? '').toString(),
    downloadUrl: sharedUrl,
    releaseNotes: (data['publishedReleaseNotes'] ?? '').toString(),
    apkSha256: (data['publishedApkSha256'] ?? '').toString(),
    forceUpdate: data['publishedForceUpdate'] == true,
  );

  if (parsed.isEmpty) {
    return [legacyDefault];
  }

  // Ensure default exists; fill gaps from legacy.
  final hasDefault = parsed.any((c) => c.id == 'default');
  final list = List<UpdateChannel>.from(parsed);
  if (!hasDefault) {
    list.add(legacyDefault);
  } else {
    final i = list.indexWhere((c) => c.id == 'default');
    final d = list[i];
    list[i] = d.copyWith(
      latestVersion:
          d.latestVersion.isNotEmpty ? d.latestVersion : legacyDefault.latestVersion,
      latestBuild:
          d.latestBuild.isNotEmpty ? d.latestBuild : legacyDefault.latestBuild,
      downloadUrl:
          d.downloadUrl.isNotEmpty ? d.downloadUrl : legacyDefault.downloadUrl,
      releaseNotes:
          d.releaseNotes.isNotEmpty ? d.releaseNotes : legacyDefault.releaseNotes,
      apkSha256: d.apkSha256.isNotEmpty ? d.apkSha256 : legacyDefault.apkSha256,
      forceUpdate: d.forceUpdate || legacyDefault.forceUpdate,
    );
  }

  // Empty per-channel URL → shared updateDownloadUrl.
  return list
      .map(
        (c) => c.downloadUrl.trim().isEmpty && sharedUrl.isNotEmpty
            ? c.copyWith(downloadUrl: sharedUrl)
            : c,
      )
      .toList();
}

/// Mirror default channel into legacy flat fields for old APKs.
Map<String, dynamic> legacyPublishFieldsFromDefault(UpdateChannel defaultChannel) {
  return {
    'publishedLatestVersion': defaultChannel.latestVersion,
    'publishedLatestBuild': defaultChannel.latestBuild,
    'publishedReleaseNotes': defaultChannel.releaseNotes,
    'publishedApkSha256': defaultChannel.apkSha256,
    'publishedForceUpdate': defaultChannel.forceUpdate,
    if (defaultChannel.downloadUrl.isNotEmpty)
      'updateDownloadUrl': defaultChannel.downloadUrl,
  };
}

/// Best APK URL for the pre-login kill-switch screen.
///
/// Order: shared `updateDownloadUrl` → `default` channel → preferred named
/// channels → any channel with a URL. Empty when nothing is configured.
String resolveKillSwitchDownloadUrl(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return '';

  final shared = (data['updateDownloadUrl'] ?? '').toString().trim();
  if (shared.isNotEmpty) return shared;

  final channels = channelsFromSettingsApp(data);
  for (final id in const ['default', 'ink', 'testers']) {
    for (final c in channels) {
      if (c.id == id && c.downloadUrl.trim().isNotEmpty) {
        return c.downloadUrl.trim();
      }
    }
  }
  for (final c in channels) {
    if (c.downloadUrl.trim().isNotEmpty) return c.downloadUrl.trim();
  }
  return '';
}
