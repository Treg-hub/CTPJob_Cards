import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/dept_request.dart';
import '../services/dept_request_service.dart';
import '../theme/app_theme.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import 'create_dept_request_screen.dart';
import 'dept_request_thread_screen.dart';

/// Admin board — all Dept Requests factory-wide.
class DeptRequestAdminScreen extends StatefulWidget {
  const DeptRequestAdminScreen({super.key});

  @override
  State<DeptRequestAdminScreen> createState() => _DeptRequestAdminScreenState();
}

class _DeptRequestAdminScreenState extends State<DeptRequestAdminScreen> {
  final _svc = DeptRequestService.instance;
  DeptRequestStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final me = realEmployee ?? currentEmployee;
    if (me == null || !role_utils.isAdmin(me)) {
      return const Scaffold(
        appBar: CtpAppBar(title: 'Dept Requests (Admin)'),
        body: Center(child: Text('Admin only')),
      );
    }

    return Scaffold(
      appBar: const CtpAppBar(title: 'Dept Requests (Admin)'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateDeptRequestScreen()),
          );
        },
        backgroundColor: kBrandOrange,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                const SizedBox(width: 6),
                ...DeptRequestStatus.values.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(s.label),
                        selected: _filter == s,
                        onSelected: (_) => setState(
                            () => _filter = _filter == s ? null : s),
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _svc.queryAllForAdmin().snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = snap.data!.docs.map(DeptRequest.fromDoc).toList();
                if (_filter != null) {
                  items = items.where((i) => i.status == _filter).toList();
                }
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      'No requests',
                      style: TextStyle(
                          color: Theme.of(context).appColors.textMuted),
                    ),
                  );
                }
                final fmt = DateFormat('dd MMM HH:mm');
                return ListView.separated(
                  padding: ScreenInsets.listPadding(context),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final when = item.lastActivityAt ?? item.createdAt;
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${item.requestNumber} · ${item.status.label}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item.locationPath}\n'
                          '${item.fromDepartment} → ${item.targetDepartment}\n'
                          '${item.message.isEmpty ? '(photo)' : item.message}'
                          '${when != null ? '\n${fmt.format(when)}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DeptRequestThreadScreen(
                                  requestId: item.id),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
