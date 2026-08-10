import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/collections.dart';
import '../main.dart' show currentEmployee;
import '../services/impression_service.dart';
import '../theme/app_theme.dart';
import '../utils/impression_format.dart';
import '../utils/role.dart' as role_utils;
import '../widgets/impression_actor_picker.dart';
import '../widgets/impression_app_bar.dart';
import '../widgets/impression_tip_banner.dart';

/// Human-readable life review for one impression roller cycle.
class ImpressionCycleDetailScreen extends StatelessWidget {
  final String cycleId;

  const ImpressionCycleDetailScreen({super.key, required this.cycleId});

  static Map<String, dynamic>? asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canEditActors = role_utils.canEditImpressionActors(currentEmployee);
    return Scaffold(
      appBar: const ImpressionAppBar(title: 'Cycle life'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(Collections.impressionCycles)
            .doc(cycleId)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return Center(
              child: Text(
                'This cycle was not found.',
                style: TextStyle(color: scheme.onSurface),
              ),
            );
          }
          final d = snap.data!.data()!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              ImpressionTipBanner(
                tipId: 'cycle_detail',
                text: ImpressionTipBanner.tips['cycle_detail']!,
              ),
              _HeaderCard(data: d, cycleId: cycleId),
              if (canEditActors) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _editActors(context, d),
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Correct who did the work'),
                ),
              ],
              const SizedBox(height: 12),
              _MechanicalSection(data: asMap(d['mechanical'])),
              const SizedBox(height: 12),
              _ElectricalSection(
                data: asMap(d['electrical']),
                esaTop: d['esaSuitability']?.toString(),
              ),
              const SizedBox(height: 12),
              _InstallRemoveSection(
                install: asMap(d['install']),
                remove: asMap(d['remove']),
                sendOut: asMap(d['sendOut']),
              ),
              const SizedBox(height: 12),
              _EventsSection(cycleId: cycleId),
              const SizedBox(height: 12),
              _DailySection(
                title: 'Daily IR (while installed)',
                cycleId: cycleId,
                collection: Collections.impressionDailyIr,
                isIr: true,
              ),
              const SizedBox(height: 12),
              _DailySection(
                title: 'Daily ESA (while installed)',
                cycleId: cycleId,
                collection: Collections.impressionDailyEsa,
                isIr: false,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editActors(BuildContext context, Map<String, dynamic> d) async {
    final mech = asMap(d['mechanical']);
    final elec = asMap(d['electrical']);
    final install = asMap(d['install']);
    final remove = asMap(d['remove']);
    final strip = asMap(d['strip']);
    final sendOut = asMap(d['sendOut']);
    String? mechClock = mech?['byClock']?.toString() ?? currentEmployee?.clockNo;
    String? elecClock = elec?['byClock']?.toString() ?? currentEmployee?.clockNo;
    String? installClock = install?['byClock']?.toString() ?? currentEmployee?.clockNo;
    String? removeClock = remove?['byClock']?.toString();
    String? stripClock = strip?['byClock']?.toString();
    String? sendOutClock = sendOut?['byClock']?.toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Correct who did the work'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Managers and isAdmin only. Floor staff always record as themselves.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (mech != null)
                  ImpressionActorPicker(
                    role: ImpressionActorRole.mechanical,
                    selectedClock: mechClock,
                    onChanged: (e) => setLocal(() => mechClock = e?.clockNo),
                    label: 'Mechanical built by',
                  ),
                if (elec != null)
                  ImpressionActorPicker(
                    role: ImpressionActorRole.electrical,
                    selectedClock: elecClock,
                    onChanged: (e) => setLocal(() => elecClock = e?.clockNo),
                    label: 'Electrical tested by',
                  ),
                if (install != null)
                  ImpressionActorPicker(
                    role: ImpressionActorRole.pressroom,
                    selectedClock: installClock,
                    onChanged: (e) => setLocal(() => installClock = e?.clockNo),
                    label: 'Installed by',
                  ),
                if (remove != null)
                  ImpressionActorPicker(
                    role: ImpressionActorRole.pressroom,
                    selectedClock: removeClock,
                    onChanged: (e) => setLocal(() => removeClock = e?.clockNo),
                    label: 'Removed by',
                  ),
                if (strip != null)
                  ImpressionActorPicker(
                    role: ImpressionActorRole.mechanical,
                    selectedClock: stripClock,
                    onChanged: (e) => setLocal(() => stripClock = e?.clockNo),
                    label: 'Stripped by',
                  ),
                if (sendOut != null)
                  ImpressionActorPicker(
                    role: ImpressionActorRole.mechanical,
                    selectedClock: sendOutClock,
                    onChanged: (e) => setLocal(() => sendOutClock = e?.clockNo),
                    label: 'Sent out by',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    try {
      await ImpressionService.instance.updateCycleActors(
        cycleId: cycleId,
        mechanicalByClock: mech != null ? mechClock : null,
        electricalByClock: elec != null ? elecClock : null,
        installByClock: install != null ? installClock : null,
        removeByClock: remove != null ? removeClock : null,
        stripByClock: strip != null ? stripClock : null,
        sendOutByClock: sendOut != null ? sendOutClock : null,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('People updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String cycleId;

  const _HeaderCard({required this.data, required this.cycleId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cycleNo = data['cycleNo']?.toString() ?? cycleId;
    final shaft = ImpressionFormat.display(data['shaftNo']);
    final sleeve = ImpressionFormat.display(data['sleeveId']);
    final press = ImpressionFormat.press(data['pressId']?.toString());
    final state = ImpressionFormat.state(data['state']?.toString());
    final esa = data['esaSuitability']?.toString();
    final rematch = data['rematch'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cycleNo,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Shaft $shaft  ·  Sleeve $sleeve',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '$press  ·  $state',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.85)),
            ),
            if (esa != null && esa.isNotEmpty) ...[
              const SizedBox(height: 8),
              _StatusChip(
                label: ImpressionFormat.esaFromCycle(data),
                color: (data['electrical'] is Map &&
                            data['electrical']['pass'] == false) ||
                        esa == 'yellow_only'
                    ? Colors.amber.shade800
                    : esa == 'unsuitable'
                        ? scheme.error
                        : const Color(0xFF2E7D32),
              ),
            ],
            if (rematch) ...[
              const SizedBox(height: 8),
              Text(
                'Rematch: sleeve was preferred on another shaft'
                '${ImpressionFormat.nonEmpty(data['rematchReason']) != null ? ' — ${data['rematchReason']}' : ''}',
                style: TextStyle(
                  color: kBrandOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (data['createdAt'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Cycle opened ${ImpressionFormat.dateTime(data['createdAt'])}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Mechanical ───────────────────────────────────────────────────────────────

class _MechanicalSection extends StatelessWidget {
  final Map<String, dynamic>? data;

  const _MechanicalSection({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null || data!.isEmpty) {
      return const _SectionCard(
        title: 'Mechanical',
        child: Text('No mechanical record yet.'),
      );
    }
    final m = data!;
    final pass = m['pass'] == true;
    final shore = m['shoreHardness'];
    final dia = m['rollerDiameter'];

    return _SectionCard(
      title: 'Mechanical',
      trailing: _PassBadge(pass: pass),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('When', ImpressionFormat.dateTime(m['at'])),
          if (m['atOverridden'] == true)
            _kv('Time note', 'Date/time was adjusted by a manager'),
          _kv(
            'Built by (bearings fitted by)',
            ImpressionFormat.nonEmpty(m['bearingsFittedBy']) ??
                ImpressionFormat.person(m),
          ),
          if (ImpressionFormat.nonEmpty(m['bearingsFittedBy']) != null &&
              ImpressionFormat.person(m) != '—')
            _kv('Recorded clock', ImpressionFormat.person(m)),
          if (m['actorOverridden'] == true && m['recordedByName'] != null)
            _kv('Entered by', '${m['recordedByName']} (${m['recordedByClock'] ?? ''})'),
          _kv('Length', _withUnit(m['length'], 'mm')),
          _kv('Shore hardness L / M / R', ImpressionFormat.triad(shore)),
          _kv('Size (diameter)', _withUnit(m['sizeDiameterMm'], 'mm')),
          _kv(
            'Roller diameter L / M / R',
            _withUnit(ImpressionFormat.triad(dia), 'mm', alreadyFormatted: true),
          ),
          _kv('Roller balancing', m['rollerBalancing'] == true ? 'OK' : m['rollerBalancing'] == false ? 'Not OK' : '—'),
          _kv('Roughness', _withUnit(m['roughnessUm'], 'µm')),
          if (ImpressionFormat.nonEmpty(m['comments']) != null)
            _kv('Comments', m['comments'].toString()),
        ],
      ),
    );
  }
}

// ── Electrical ───────────────────────────────────────────────────────────────

class _ElectricalSection extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String? esaTop;

  const _ElectricalSection({required this.data, this.esaTop});

  @override
  Widget build(BuildContext context) {
    if (data == null || data!.isEmpty) {
      return const _SectionCard(
        title: 'Electrical',
        child: Text('No electrical test yet.'),
      );
    }
    final m = data!;
    final pass = m['pass'] == true;
    final cond = m['conductiveResistanceCold'];
    final ins = m['insulationResistance'];
    final esa = m['esaSuitability']?.toString() ?? esaTop;

    return _SectionCard(
      title: 'Electrical',
      trailing: _PassBadge(pass: pass),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('When', ImpressionFormat.dateTime(m['at'])),
          if (m['atOverridden'] == true)
            _kv('Time note', 'Date/time was adjusted by a manager'),
          _kv('Tested by', ImpressionFormat.person(m)),
          if (m['actorOverridden'] == true && m['recordedByName'] != null)
            _kv('Entered by', '${m['recordedByName']} (${m['recordedByClock'] ?? ''})'),
          _kv(
            'ESA suitability',
            m['pass'] == false
                ? 'Electrical FAIL · yellow units only'
                : ImpressionFormat.esa(esa),
          ),
          if (cond is Map) ...[
            const SizedBox(height: 6),
            Text(
              'Conductive resistance cold (mΩ)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            _kv('Row 1  L / C / R', ImpressionFormat.triad(
              cond['row1'],
              keys: const ['left', 'centre', 'right'],
            )),
            _kv('Row 2  L / C / R', ImpressionFormat.triad(
              cond['row2'],
              keys: const ['left', 'centre', 'right'],
            )),
          ],
          if (ins is Map) ...[
            const SizedBox(height: 6),
            Text(
              'Insulation resistance (GΩ)',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            _kv('Row 1  L / R', ImpressionFormat.pair(ins['row1'])),
            _kv('Row 2  L / R', ImpressionFormat.pair(ins['row2'])),
          ],
          if (ImpressionFormat.nonEmpty(m['comments']) != null)
            _kv('Comments', m['comments'].toString()),
        ],
      ),
    );
  }
}

// ── Install / remove ─────────────────────────────────────────────────────────

class _InstallRemoveSection extends StatelessWidget {
  final Map<String, dynamic>? install;
  final Map<String, dynamic>? remove;
  final Map<String, dynamic>? sendOut;

  const _InstallRemoveSection({
    required this.install,
    required this.remove,
    required this.sendOut,
  });

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'On the press',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Install', style: Theme.of(context).textTheme.titleSmall),
          if (install == null || install!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Not installed yet.'),
            )
          else ...[
            _kv(
              'Unit',
              install!['unitNo'] != null ? 'Unit ${install!['unitNo']}' : '—',
            ),
            _kv('Press', ImpressionFormat.press(install!['pressId']?.toString())),
            _kv('When', ImpressionFormat.dateTime(install!['at'])),
            if (install!['atOverridden'] == true)
              _kv('Time note', 'Date/time was adjusted by a manager'),
            _kv('Installed by', ImpressionFormat.person(install)),
            if (install!['actorOverridden'] == true && install!['recordedByName'] != null)
              _kv('Entered by', '${install!['recordedByName']} (${install!['recordedByClock'] ?? ''})'),
            if (install!['yellowOnlyOverride'] == true)
              _kv(
                'Yellow override',
                ImpressionFormat.display(install!['yellowOnlyNote']) == '—'
                    ? 'Yes (installer override)'
                    : install!['yellowOnlyNote'].toString(),
              ),
            const SizedBox(height: 8),
          ],
          Text('Remove', style: Theme.of(context).textTheme.titleSmall),
          if (remove == null || remove!.isEmpty)
            const Text('Still on press (or never installed).')
          else ...[
            _kv('When', ImpressionFormat.dateTime(remove!['at'])),
            _kv('Removed by', ImpressionFormat.person(remove)),
            _kv(
              'Reason',
              ImpressionFormat.removalReason(remove!['reason']?.toString()),
            ),
            _kv(
              'Revolutions',
              remove!['revsMillions'] != null
                  ? '${remove!['revsMillions']} million'
                  : '—',
            ),
            if (ImpressionFormat.nonEmpty(remove!['comments']) != null)
              _kv('Comments', remove!['comments'].toString()),
          ],
          if (sendOut != null && sendOut!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Send-out', style: Theme.of(context).textTheme.titleSmall),
            _kv(
              'Type',
              ImpressionFormat.sendOutType(sendOut!['type']?.toString()),
            ),
            _kv('Vendor', ImpressionFormat.display(sendOut!['vendor'])),
            _kv('Sent', ImpressionFormat.dateTime(sendOut!['sentAt'] ?? sendOut!['at'])),
            _kv('Sent out by', ImpressionFormat.person(sendOut)),
            if (sendOut!['actorOverridden'] == true && sendOut!['recordedByName'] != null)
              _kv(
                'Entered by',
                '${sendOut!['recordedByName']} (${sendOut!['recordedByClock'] ?? ''})',
              ),
            if (sendOut!['receivedAt'] != null)
              _kv('Received', ImpressionFormat.dateTime(sendOut!['receivedAt'])),
          ],
        ],
      ),
    );
  }
}

// ── Events ───────────────────────────────────────────────────────────────────

class _EventsSection extends StatelessWidget {
  final String cycleId;

  const _EventsSection({required this.cycleId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: 'Timeline',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(Collections.impressionCycles)
            .doc(cycleId)
            .collection('events')
            .orderBy('at', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, es) {
          final docs = es.data?.docs ?? [];
          if (docs.isEmpty) {
            return Text(
              'No events yet.',
              style: TextStyle(color: scheme.onSurface),
            );
          }
          return Column(
            children: docs.map((e) {
              final m = e.data();
              final who = ImpressionFormat.person(m);
              final when = ImpressionFormat.dateTime(m['at']);
              final type = ImpressionFormat.eventType(m['type']?.toString());
              final overrideNote = m['atOverridden'] == true
                  ? ' · time adjusted'
                  : '';
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _eventIcon(m['type']?.toString()),
                  color: kBrandOrange,
                  size: 22,
                ),
                title: Text(
                  type,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '$when · $who$overrideNote',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  IconData _eventIcon(String? type) {
    switch (type) {
      case 'start_build':
        return Icons.build_circle_outlined;
      case 'electrical_pass':
      case 'electrical_fail':
        return Icons.bolt_outlined;
      case 'install':
        return Icons.download_done;
      case 'remove':
        return Icons.upload_outlined;
      case 'strip':
        return Icons.content_cut;
      case 'send_out':
        return Icons.local_shipping_outlined;
      case 'receive':
        return Icons.inventory_2_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}

// ── Daily checks ─────────────────────────────────────────────────────────────

class _DailySection extends StatelessWidget {
  final String title;
  final String cycleId;
  final String collection;
  final bool isIr;

  const _DailySection({
    required this.title,
    required this.cycleId,
    required this.collection,
    required this.isIr,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: title,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(collection)
            .orderBy('at', descending: true)
            .limit(40)
            .snapshots(),
        builder: (context, snap) {
          final hits = <Widget>[];
          for (final d in snap.data?.docs ?? []) {
            final m = d.data();
            final units = m['units'];
            if (units is! Map) continue;
            for (final e in units.entries) {
              final line = e.value;
              if (line is! Map || line['cycleId'] != cycleId) continue;
              final dateKey = m['dateKey']?.toString() ??
                  ImpressionFormat.dateOnly(m['at']);
              final over = line['overMax'] == true;
              String detail;
              if (isIr) {
                final a = line['aSideBar'];
                final b = line['bSideBar'];
                final bl = line['bladderBar'];
                final cond = line['condition'] ?? '';
                detail = [
                  if (a != null) 'A $a bar',
                  if (b != null) 'B $b bar',
                  if (bl != null) 'Bladder $bl bar',
                  if ('$cond'.isNotEmpty) '$cond',
                  if (over) 'OVER MAX',
                ].join(' · ');
              } else {
                detail = [
                  line['conditionCharge'] ?? line['condition'] ?? '',
                  if (line['conditionDischarge'] != null)
                    'Discharge: ${line['conditionDischarge']}',
                ].where((s) => '$s'.isNotEmpty).join(' · ');
              }
              hits.add(
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    over ? Icons.warning_amber : Icons.check_circle_outline,
                    color: over ? scheme.error : const Color(0xFF2E7D32),
                    size: 20,
                  ),
                  title: Text(
                    '$dateKey · Unit ${e.key}',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    detail.isEmpty ? 'Recorded' : detail,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              );
            }
          }
          if (hits.isEmpty) {
            return Text(
              'No daily checks linked to this cycle yet.',
              style: TextStyle(color: scheme.onSurface),
            );
          }
          return Column(children: hits);
        },
      ),
    );
  }
}

// ── Shared UI bits ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            DefaultTextStyle(
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
                height: 1.35,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _PassBadge extends StatelessWidget {
  final bool pass;

  const _PassBadge({required this.pass});

  @override
  Widget build(BuildContext context) {
    final color = pass ? const Color(0xFF2E7D32) : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        pass ? 'PASS' : 'FAIL',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

Widget _kv(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 148,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

String _withUnit(dynamic v, String unit, {bool alreadyFormatted = false}) {
  final s = alreadyFormatted
      ? (v is String ? v : ImpressionFormat.display(v))
      : ImpressionFormat.display(v);
  if (s == '—' || s.isEmpty) return '—';
  if (s.contains(unit)) return s;
  return '$s $unit';
}
