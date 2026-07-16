import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/collections.dart';
import '../utils/persona_audit.dart';

/// Photos + create/ack/done helpers for Dept Requests.
///
/// Create goes through `createDeptRequest` (DR-NNNN + Wave B counter).
/// No notification_inbox — activity is Home-tile only.
class DeptRequestService {
  DeptRequestService._();
  static final DeptRequestService instance = DeptRequestService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'africa-south1');

  static const int maxPhotosPerMessage = 3;
  static const String lastVisitedPrefsKey = 'deptRequestsLastVisitedAtMs';

  void _guardWrite() => assertPersonaSubmitAllowed();

  DocumentReference<Map<String, dynamic>> docRef(String id) =>
      _db.collection(Collections.deptRequests).doc(id);

  CollectionReference<Map<String, dynamic>> commentsCol(String requestId) =>
      docRef(requestId).collection(Collections.deptRequestComments);

  /// Mint a client-side id for photo upload before CF create (idempotent client_ref).
  String mintClientRef() => const Uuid().v4();

  Future<String?> pickAndCompressPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return null;

    final tempDir = await getTemporaryDirectory();
    final outPath = '${tempDir.path}/${const Uuid().v4()}.jpg';

    final compressed = await FlutterImageCompress.compressAndGetFile(
      picked.path,
      outPath,
      minWidth: 1024,
      minHeight: 1024,
      quality: 70,
      rotate: 0,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    return compressed?.path;
  }

  Future<List<String>> uploadPhotos({
    required String requestId,
    required List<String> localPaths,
  }) async {
    _guardWrite();
    if (localPaths.isEmpty) return const [];
    final urls = <String>[];
    for (final path in localPaths) {
      final file = File(path);
      if (!file.existsSync()) {
        throw Exception('Photo file was cleaned up before upload — please re-add it');
      }
      final fileName = '${const Uuid().v4()}.jpg';
      final ref = _storage.ref('dept_requests/$requestId/photos/$fileName');
      final task = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await task.ref.getDownloadURL());
    }
    return urls;
  }

  /// Creates a Dept Request; returns `{ id, requestNumber }`.
  Future<({String id, String requestNumber})> create({
    required String targetDepartment,
    required String area,
    required String message,
    required String createdByName,
    List<String> localPhotoPaths = const [],
  }) async {
    _guardWrite();
    final clientRef = mintClientRef();
    List<String> photoUrls = const [];
    if (localPhotoPaths.isNotEmpty) {
      photoUrls = await uploadPhotos(
        requestId: clientRef,
        localPaths: localPhotoPaths,
      );
    }

    final payload = <String, dynamic>{
      'client_ref': clientRef,
      'targetDepartment': targetDepartment.trim(),
      'area': area.trim(),
      'message': message.trim(),
      'createdByName': createdByName.trim(),
      if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      ...personaAuditFields(),
    };

    final result = await _functions.httpsCallable('createDeptRequest').call(payload);
    final data = Map<String, dynamic>.from(result.data as Map? ?? {});
    final id = (data['id'] as String?) ?? clientRef;
    final number = (data['requestNumber'] as String?) ?? '';
    return (id: id, requestNumber: number);
  }

  Future<void> acknowledge({
    required String requestId,
    required String clockNo,
    required String name,
  }) async {
    _guardWrite();
    final now = FieldValue.serverTimestamp();
    await docRef(requestId).update({
      'status': 'acknowledged',
      'acknowledgedAt': now,
      'acknowledgedByClockNo': clockNo,
      'acknowledgedByName': name,
      'lastActivityAt': now,
    });
  }

  Future<void> markDone({
    required String requestId,
    required String clockNo,
    required String name,
    String? doneNote,
  }) async {
    _guardWrite();
    final now = FieldValue.serverTimestamp();
    await docRef(requestId).update({
      'status': 'done',
      'doneAt': now,
      'doneByClockNo': clockNo,
      'doneByName': name,
      if (doneNote != null && doneNote.trim().isNotEmpty)
        'doneNote': doneNote.trim(),
      'lastActivityAt': now,
    });
  }

  Future<void> withdraw({
    required String requestId,
    required String clockNo,
  }) async {
    _guardWrite();
    final now = FieldValue.serverTimestamp();
    await docRef(requestId).update({
      'status': 'withdrawn',
      'withdrawnAt': now,
      'withdrawnByClockNo': clockNo,
      'lastActivityAt': now,
    });
  }

  Future<void> addComment({
    required String requestId,
    required String text,
    required String byClockNo,
    required String byName,
    List<String> localPhotoPaths = const [],
  }) async {
    _guardWrite();
    final commentRef = commentsCol(requestId).doc();
    List<String> photoUrls = const [];
    if (localPhotoPaths.isNotEmpty) {
      photoUrls = await uploadPhotos(
        requestId: requestId,
        localPaths: localPhotoPaths,
      );
    }
    await commentRef.set({
      'text': text.trim(),
      'byClockNo': byClockNo,
      'byName': byName,
      'createdAt': FieldValue.serverTimestamp(),
      if (photoUrls.isNotEmpty) 'photoUrls': photoUrls,
      ...personaAuditFields(),
    });
  }

  /// Active requests targeting [department] (Home badge + To my dept).
  Query<Map<String, dynamic>> queryForTargetDept(String department) {
    return _db
        .collection(Collections.deptRequests)
        .where('targetDepartment', isEqualTo: department)
        .orderBy('lastActivityAt', descending: true)
        .limit(50);
  }

  Query<Map<String, dynamic>> queryRaisedBy(String clockNo) {
    return _db
        .collection(Collections.deptRequests)
        .where('createdByClockNo', isEqualTo: clockNo)
        .orderBy('lastActivityAt', descending: true)
        .limit(50);
  }

  Query<Map<String, dynamic>> queryAllForAdmin() {
    return _db
        .collection(Collections.deptRequests)
        .orderBy('lastActivityAt', descending: true)
        .limit(100);
  }

  Future<void> markListVisited() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      lastVisitedPrefsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DateTime?> lastVisitedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(lastVisitedPrefsKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
