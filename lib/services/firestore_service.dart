import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/job_card.dart';

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
      await _firestore.collection('job_cards').add(jobCard.toFirestore());
    } catch (e) {
      throw Exception('Failed to create job card: $e');
    }
  }

  Future<void> updateJobCard(String jobCardId, JobCard jobCard) async {
    try {
      await _firestore.collection('job_cards').doc(jobCardId).update(jobCard.toFirestore());
    } catch (e) {
      throw Exception('Failed to update job card: $e');
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
        .where('status', isEqualTo: 'completed')
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

  Future<List<JobCard>> getAllJobCardsFuture() async {
    try {
      final snapshot = await _firestore.collection('job_cards').get();
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
      if (!doc.exists) {
        await _firestore.collection('settings').doc('app').set({
          'switchUserPassword': 'admin123',
          'initialized': true,
        });
      }
    } catch (e) {
      throw Exception('Failed to initialize settings: $e');
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
      // Get all completed job cards and filter in memory to avoid composite index requirement
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'completed')
          .get();

      final startTimestamp = Timestamp.fromDate(startDate);
      final count = snapshot.docs.where((doc) {
        final data = doc.data();
        final completedAt = data['completedAt'] as Timestamp?;
        return completedAt != null && completedAt.compareTo(startTimestamp) >= 0;
      }).length;

      return count;
    } catch (e) {
      throw Exception('Failed to get completed job cards count: $e');
    }
  }

  Future<Map<String, int>> getEmployeePerformance() async {
    try {
      final snapshot = await _firestore
          .collection('job_cards')
          .where('status', isEqualTo: 'completed')
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
          .where('status', isEqualTo: 'completed')
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
}
