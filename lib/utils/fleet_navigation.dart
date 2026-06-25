import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show currentEmployee, navigatorKey, TopRouteTracker;
import '../models/fleet_issue.dart';
import '../screens/fleet_issue_detail_screen.dart';
import '../screens/fleet_mark_fixed_screen.dart';
import '../screens/fleet_reporter_issue_detail_screen.dart';
import '../services/fleet_service.dart';
import 'role.dart' as role_utils;

/// Opens the appropriate Fleet screen for [issueId] based on role and status.
Future<bool> openFleetIssue(BuildContext context, String issueId) async {
  final service = FleetService();
  final issue = await service.getIssue(issueId);
  if (issue == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fleet issue not found or already removed.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }

  final settings = await service.getSettings();
  final emp = currentEmployee;
  final isMechanic = role_utils.isFleetMechanic(emp, settings);
  final isReporter = role_utils.isFleetReporter(emp, settings);

  final routeName = '/fleet/issue/$issueId';
  if (TopRouteTracker.topRouteName == routeName) return true;

  final Widget screen;
  if (issue.status == FleetIssueStatus.resolved ||
      issue.status == FleetIssueStatus.cancelled) {
    if (isReporter && !isMechanic) {
      screen = FleetReporterIssueDetailScreen(issueId: issueId);
    } else {
      screen = FleetIssueDetailScreen(
        issueId: issueId,
        mechanicMode: isMechanic,
      );
    }
  } else if (isMechanic) {
    screen = FleetMarkFixedScreen(
      preSelectedAssetId: issue.assetId,
      preSelectedAssetName: issue.assetName,
      linkedIssueId: issueId,
    );
  } else if (isReporter) {
    screen = FleetReporterIssueDetailScreen(issueId: issueId);
  } else {
    screen = FleetIssueDetailScreen(
      issueId: issueId,
      mechanicMode: false,
    );
  }

  if (!context.mounted) return false;
  await Navigator.of(context).push(
    MaterialPageRoute(
      settings: RouteSettings(name: routeName),
      builder: (_) => screen,
    ),
  );
  return true;
}

/// Deep-link entry used by FCM and the notification inbox (global navigator).
Future<void> navigateToFleetIssue(String issueId) async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pendingFleetIssueId', issueId);
    return;
  }
  await openFleetIssue(ctx, issueId);
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('pendingFleetIssueId');
}