import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../main.dart' show currentEmployee, realEmployee;
import '../models/dept_request.dart';
import '../services/dept_request_service.dart';
import '../theme/app_theme.dart';
import '../utils/screen_insets.dart';
import '../widgets/ctp_app_bar.dart';
import '../widgets/dept_request_tip.dart';
import 'create_dept_request_screen.dart';
import 'dept_request_thread_screen.dart';

/// Manager list: To my dept | I raised.
class DeptRequestsScreen extends ConsumerStatefulWidget {
  const DeptRequestsScreen({super.key});

  @override
  ConsumerState<DeptRequestsScreen> createState() => _DeptRequestsScreenState();
}

class _DeptRequestsScreenState extends ConsumerState<DeptRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _svc = DeptRequestService.instance;
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _svc.markListVisited();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = realEmployee ?? currentEmployee;
    final dept = me?.department ?? '';
    final clock = me?.clockNo ?? '';
    final colors = Theme.of(context).appColors;

    return Scaffold(
      appBar: CtpAppBar(
        title: 'Dept Requests',
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'To my dept'),
            Tab(text: 'I raised'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showDone ? 'Hide done' : 'Show done',
            icon: Icon(_showDone ? Icons.filter_alt_off : Icons.filter_alt),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const CreateDeptRequestScreen()),
          );
          if (ok == true && mounted) setState(() {});
        },
        backgroundColor: kBrandOrange,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: Column(
        children: [
          DeptRequestTip(
            dismissible: true,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kBrandOrange.withValues(alpha: 0.35)),
              ),
              child: Text(
                'Manager-to-manager notes (including same department). '
                'Opening a request to your dept marks it acknowledged. '
                'Mark Done when handled. No job inbox pings — use this Home tile. '
                'Breakdowns still go to Create Job Card.',
                style: TextStyle(fontSize: 13, color: colors.textMuted, height: 1.35),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _listStream(
                  stream: dept.isEmpty
                      ? null
                      : _svc.queryForTargetDept(dept).snapshots(),
                  emptyLabel: 'No requests for $dept',
                ),
                _listStream(
                  stream: clock.isEmpty
                      ? null
                      : _svc.queryRaisedBy(clock).snapshots(),
                  emptyLabel: 'You have not raised any requests yet',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listStream({
    required Stream<QuerySnapshot<Map<String, dynamic>>>? stream,
    required String emptyLabel,
  }) {
    if (stream == null) {
      return const Center(child: Text('Sign in required'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var items = snap.data!.docs.map(DeptRequest.fromDoc).toList();
        if (!_showDone) {
          items = items
              .where((i) =>
                  i.status != DeptRequestStatus.done &&
                  i.status != DeptRequestStatus.withdrawn)
              .toList();
        }
        if (items.isEmpty) {
          return Center(
            child: Text(emptyLabel,
                style: TextStyle(color: Theme.of(context).appColors.textMuted)),
          );
        }
        return ListView.separated(
          padding: ScreenInsets.listPadding(context),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _RequestTile(item: items[i]),
        );
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  final DeptRequest item;
  const _RequestTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).appColors;
    final fmt = DateFormat('dd MMM HH:mm');
    final when = item.lastActivityAt ?? item.createdAt;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        title: Row(
          children: [
            Text(
              item.requestNumber.isEmpty ? 'Request' : item.requestNumber,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: deptRequestStatusColor(context, item.status)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                item.status.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: deptRequestStatusColor(context, item.status),
                ),
              ),
            ),
            if (item.isOpenOver48h) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('>48h',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item.locationPath, style: TextStyle(fontSize: 12, color: colors.textMuted)),
            Text(
              '${item.fromDepartment} → ${item.targetDepartment}',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
            Text(
              item.message.isEmpty ? '(photo)' : item.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (when != null)
              Text(fmt.format(when),
                  style: TextStyle(fontSize: 11, color: colors.textMuted)),
          ],
        ),
        trailing: item.commentCount > 0
            ? Badge(
                label: Text('${item.commentCount}'),
                child: const Icon(Icons.chat_bubble_outline),
              )
            : const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeptRequestThreadScreen(requestId: item.id),
            ),
          );
        },
      ),
    );
  }
}
