import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/copper_transaction.dart';
import '../models/employee.dart';
import '../models/job_card.dart';
import 'connectivity_service.dart';
import 'sync_service.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Employee operations
  Future<Employee?> getEmployee(String clockNo) async {
    try {
      final doc = await _firestore.collection('employees').doc(clockNo).get();
      if (!doc.exists) return null;
      return Employee.fromFirestore(doc.data()!, clockNo);
    } catch (e) {
      throw Exception('Failed to load employee: $e');
    }
  }

  Future<void> updateEmployee(Employee employee) async {
    try {
      await _firestore.collection('employees').doc(employee.clockNo).set(
            employee.toFirestore(),
            SetOptions(merge: true),
          );
    } catch (e) {
      throw Exception('Failed to update employee: $e');
    }
  }

  Future<void> createEmployee(Employee employee) async {
    try {
      await _firestore.collection('employees').doc(employee.clockNo).set(employee.toFirestore());
    } catch (e) {
      throw Exception('Failed to create employee: $e');
    }
  }

  Future<void> deleteEmployee(String clockNo) async {
    try {
      await _firestore.collection('employees').doc(clockNo).delete();
    } catch (e) {
      throw Exception('Failed to delete employee: $e');
    }
  }

  Future<void> deleteAllEmployees() async {
    try {
      final snapshot = await _firestore.collection('employees').get();
      const int chunkSize = 500;
      final docs = snapshot.docs;

      for (var i = 0; i < docs.length; i += chunkSize) {
        final batch = _firestore.batch();
        final end = (i + chunkSize < docs.length) ? i + chunkSize : docs.length;
        for (var j = i; j < end; j++) {
          batch.delete(docs[j].reference);
        }
        await batch.commit();
      }
    } catch (e) {
      throw Exception('Failed to delete all employees: $e');
    }
  }

  Future<List<Employee>> getAllEmployees() async {
    try {
      final snapshot = await _firestore.collection('employees').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromFirestore(data, doc.id);
      }).toList();
    } catch (e) {
      throw Exception('Failed to load employees: $e');
    }
  }

  Stream<List<Employee>> getEmployeesStream() {
    return _firestore.collection('employees').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Employee.fromFirestore(data, doc.id);
      }).toList();
    });
  }

  // Job Card operations
  Future<void> createJobCard(JobCard jobCard) async {
    try {
      await _firestore.runTransaction((transaction) async {
        // Get the counter document
        final counterRef = _firestore.collection('counters').doc('jobCards');
        final counterSnapshot = await transaction.get(counterRef);

        int nextNumber;
        if (counterSnapshot.exists) {
          nextNumber = counterSnapshot.data()?['nextJobCardNumber'] as int? ?? 1;
        } else {
          // Initialize counter if it doesn't exist
          nextNumber = 1;
        }

        // Update counter
        transaction.set(counterRef, {'nextJobCardNumber': nextNumber + 1}, SetOptions(merge: true));

        // Create job card with the number
        final jobCardWithNumber = jobCard.copyWith(jobCardNumber: nextNumber);
        final jobCardRef = _firestore.collection('job_cards').doc(); // Auto-ID
        transaction.set(jobCardRef, jobCardWithNumber.toFirestore());
      });
    } catch (e) {
      throw Exception('Failed to create job card: $e');
    }
  }

  Future<void> updateJobCard(String jobCardId, JobCard jobCard) async {
    try {
      await _firestore.collection('job_cards').doc(jobCardId).set(jobCard.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update job card: $e');
    }
  }

  Future<void> deleteJobCard(String jobCardId) async {
    try {
      await _firestore.collection('job_cards').doc(jobCardId).delete();
    } catch (e) {
      throw Exception('Failed to delete job card: $e');
    }
  }

  Future<JobCard?> getJobCard(String jobCardId) async {
    try {
      final doc = await _firestore.collection('job_cards').doc(jobCardId).get();
      if (!doc.exists) return null;
      return JobCard.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to get job card: $e');
    }
  }

  Stream<JobCard> getJobCardStream(String jobCardId) {
    return _firestore.collection('job_cards').doc(jobCardId).snapshots().map((doc) => JobCard.fromFirestore(doc));
  }

  Stream<List<JobCard>> getOpenJobCards() {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'open')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Stream<List<JobCard>> getAssignedJobCards(String employeeClockNo) {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'open')
        .where('assignedClockNos', arrayContains: employeeClockNo)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Stream<List<JobCard>> getCompletedJobCards() {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'closed')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Stream<List<JobCard>> getAllJobCards() {
    return _firestore
        .collection('job_cards')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  // ============================================================
    // TEST VERSION - WITHOUT jobCardNumber FILTER
    // Use this temporarily to debug
    // ============================================================

    /// 1. Exact Related Jobs
    Stream<List<JobCard>> getExactRelatedJobCardsStream({
      required String department,
      required String area,
      required String machine,
      required String part,
      required String type,
    }) {
      return _firestore
          .collection('job_cards')
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('part', isEqualTo: part)
          .where('type', isEqualTo: type)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
    }

    /// 2. Similar Jobs (Excluding Part)
    Stream<List<JobCard>> getRelatedExcludingPartStream({
      required String department,
      required String area,
      required String machine,
      required String type,
    }) {
      return _firestore
          .collection('job_cards')
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('type', isEqualTo: type)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
    }

    /// 2. Exact All Types (same dept/area/machine/part, different type)
    Stream<List<JobCard>> getExactAllTypesStream({
      required String department,
      required String area,
      required String machine,
      required String part,
    }) {
      return _firestore
          .collection('job_cards')
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('part', isEqualTo: part)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
    }

    /// 3. All Parts (same dept/area/machine, different part, all types)
    Stream<List<JobCard>> getAllPartsStream({
      required String department,
      required String area,
      required String machine,
    }) {
      return _firestore
          .collection('job_cards')
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .where('status', whereIn: ['monitor', 'closed'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
    }

  Future<List<JobCard>> getAllJobCardsFuture() async {
    try {
      final snapshot = await _firestore.collection('job_cards').limit(1000).get();
      return snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get all job cards: $e');
    }
  }

  Future<List<String>> getDepartmentsForJobCards(String status) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: status)
          .get();

      final departments = <String>{};
      for (var doc in snapshot.docs) {
        final dept = doc['department'] as String?;
        if (dept != null && dept.isNotEmpty) departments.add(dept);
      }
      return departments.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load departments: $e');
    }
  }

  Future<List<String>> getAreasForJobCards(String status, String department) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: status)
          .where('department', isEqualTo: department)
          .get();

      final areas = <String>{};
      for (var doc in snapshot.docs) {
        final area = doc['area'] as String?;
        if (area != null && area.isNotEmpty) areas.add(area);
      }
      return areas.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load areas: $e');
    }
  }

  Future<List<String>> getMachinesForJobCards(String status, String department, String area) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: status)
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .get();

      final machines = <String>{};
      for (var doc in snapshot.docs) {
        final machine = doc['machine'] as String?;
        if (machine != null && machine.isNotEmpty) machines.add(machine);
      }
      return machines.toList()..sort();
    } catch (e) {
      throw Exception('Failed to load machines: $e');
    }
  }

  Future<List<String>> getPreviousParts(String department, String area, String machine) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('department', isEqualTo: department)
          .where('area', isEqualTo: area)
          .where('machine', isEqualTo: machine)
          .get();

      final parts = snapshot.docs
          .map((doc) => (doc.data()['part'] as String? ?? '').trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .toList();
      return parts;
    } catch (e) {
      throw Exception('Failed to load previous parts: $e');
    }
  }

  // Factory structure operations
  Future<Map<String, dynamic>> getFactoryStructure() async {
    try {
      final doc = await _firestore.collection('structures').doc('factory').get();
      return doc.data()?['data'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      throw Exception('Failed to load factory structure: $e');
    }
  }

  Future<void> updateFactoryStructure(Map<String, dynamic> structure) async {
    try {
      await _firestore.collection('structures').doc('factory').set({'data': structure});
    } catch (e) {
      throw Exception('Failed to update factory structure: $e');
    }
  }

  // Settings operations
  Future<void> initializeSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('app').get();
      
      if (doc.exists) {
        debugPrint('Settings loaded successfully');
      } else {
        debugPrint('Warning: settings/app document does not exist');
      }
    } catch (e) {
      debugPrint('Warning: Could not load settings: $e');
      // Do NOT throw - let the app continue
    }
  }

  Future<String> getSwitchUserPassword() async {
    try {
      final doc = await _firestore.collection('settings').doc('app').get();
      return doc.data()?['switchUserPassword'] as String? ?? 'admin123';
    } catch (e) {
      throw Exception('Failed to get switch user password: $e');
    }
  }

  Future<void> updateSwitchUserPassword(String newPassword) async {
    try {
      await _firestore.collection('settings').doc('app').set({
        'switchUserPassword': newPassword,
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to update switch user password: $e');
    }
  }

  Future<String?> getCopperPassword() async {
    try {
      final doc = await _firestore.collection('settings').doc('app').get();
      return doc.data()?['copperPassword'] as String?;
    } catch (e) {
      throw Exception('Failed to get copper password: $e');
    }
  }

  // Authentication persistence
  Future<void> saveLoggedInEmployee(String clockNo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loggedInClockNo', clockNo);
  }

  Future<String?> getLoggedInEmployeeClockNo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loggedInClockNo');
  }

  Future<void> clearLoggedInEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedInClockNo');
  }

  // Dashboard aggregation methods
  Future<int> getOpenJobCardsCount() async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'open')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      throw Exception('Failed to get open job cards count: $e');
    }
  }

  Future<int> getCompletedJobCardsCountInPeriod(DateTime startDate) async {
    try {
      final startTimestamp = Timestamp.fromDate(startDate);
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'closed')
          .where('completedAt', isGreaterThanOrEqualTo: startTimestamp)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      throw Exception('Failed to get completed job cards count: $e');
    }
  }

  Future<Map<String, int>> getEmployeePerformance() async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'closed')
          .get();

      final performance = <String, int>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final completedBy = data['completedBy'] as String?;
        if (completedBy != null && completedBy.isNotEmpty) {
          performance[completedBy] = (performance[completedBy] ?? 0) + 1;
        }
      }
      return performance;
    } catch (e) {
      throw Exception('Failed to get employee performance: $e');
    }
  }

  Future<Duration?> getAverageCompletionTime() async {
    try {
      // Get all completed job cards and filter in memory to avoid composite index requirement
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'closed')
          .get();

      if (snapshot.docs.isEmpty) return null;

      var totalDuration = Duration.zero;
      var count = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

        if (createdAt != null && completedAt != null) {
          totalDuration += completedAt.difference(createdAt);
          count++;
        }
      }

      return count > 0 ? totalDuration ~/ count : null;
    } catch (e) {
      throw Exception('Failed to get average completion time: $e');
    }
  }

  Future<Map<String, int>> getJobCardsByPriority() async {
    try {
      final snapshot = await _firestore.collection('job_cards').get();

      final priorityCounts = <String, int>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final priority = data['priority'] as int? ?? 3;
        final status = data['status'] as String? ?? 'open';

        final key = status == 'open' ? 'Open P$priority' : 'Completed P$priority';
        priorityCounts[key] = (priorityCounts[key] ?? 0) + 1;
      }
      return priorityCounts;
    } catch (e) {
      throw Exception('Failed to get job cards by priority: $e');
    }
  }

  Future<Map<String, int>> getJobCardsByType() async {
    try {
      final snapshot = await _firestore.collection('job_cards').get();

      final typeCounts = <String, int>{};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? 'Mechanical';
        final status = data['status'] as String? ?? 'open';

        final key = status == 'open' ? 'Open $type' : 'Completed $type';
        typeCounts[key] = (typeCounts[key] ?? 0) + 1;
      }
      return typeCounts;
    } catch (e) {
      throw Exception('Failed to get job cards by type: $e');
    }
  }

  Stream<List<JobCard>> getMonitoringJobCards() {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'monitor')
        .orderBy('monitoringStartedAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  Future<List<JobCard>> getRecentlyAutoClosed(DateTime startDate) async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'closed')
          .where('closedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .orderBy('closedAt', descending: true)
          .get();
      return snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList();
    } catch (e) {
      throw Exception('Failed to get recently auto-closed jobs: $e');
    }
  }

  Stream<List<JobCard>> getClosedJobCards() {
    return _firestore
        .collection('job_cards')
        .where('status', isEqualTo: 'closed')
        .orderBy('closedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobCard.fromFirestore(doc)).toList());
  }

  // Copper transaction operations
  Future<void> createCopperTransaction(CopperTransaction transaction) async {
    try {
      await _firestore.collection('copper_transactions').doc(transaction.id).set(transaction.toFirestore());
    } catch (e) {
      throw Exception('Failed to create copper transaction: $e');
    }
  }

  // Offline-aware save for Job Cards
  Future<void> saveJobCardOfflineAware(JobCard jobCard) async {
    final isOnline = await ConnectivityService().isOnline();

    if (isOnline) {
      if (jobCard.id == null) {
        await createJobCard(jobCard);
      } else {
        await updateJobCard(jobCard.id!, jobCard);
      }
      debugPrint('✅ JobCard saved directly to Firestore');
    } else {
      if (jobCard.id != null) {
        await SyncService().addToQueue(
          collection: 'job_cards',
          operation: 'update',
          data: jobCard.toFirestore(),
          documentId: jobCard.id,
        );
        debugPrint('📤 JobCard queued for later sync (offline)');
      } else {
        debugPrint('❌ Cannot save new JobCard offline - requires online connection');
        throw Exception('Cannot create new job card offline');
      }
    }
  }

  // Offline-aware save for Copper Transactions
  Future<void> saveCopperTransactionOfflineAware(CopperTransaction transaction) async {
    final isOnline = await ConnectivityService().isOnline();

    if (isOnline) {
      await createCopperTransaction(transaction);
      debugPrint('✅ CopperTransaction saved directly to Firestore');
    } else {
      await SyncService().addToQueue(
        collection: 'copper_transactions',
        operation: 'create',
        data: transaction.toFirestore(),
        documentId: transaction.id,
      );
      debugPrint('📤 CopperTransaction queued for later sync (offline)');
    }
  }
}
