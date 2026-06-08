import 'package:cloud_firestore/cloud_firestore.dart';

class SharedRoomInfo {
  final String syllabusId;
  final String roomName;
  final DateTime updatedAt;
  final String lastUpdatedBy;

  SharedRoomInfo({
    required this.syllabusId,
    required this.roomName,
    required this.updatedAt,
    required this.lastUpdatedBy,
  });

  factory SharedRoomInfo.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SharedRoomInfo(
      syllabusId: doc.id,
      roomName: data['room_name'] ?? '',
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUpdatedBy: data['last_updated_by'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'room_name': roomName,
      'updated_at': Timestamp.fromDate(updatedAt),
      'last_updated_by': lastUpdatedBy,
    };
  }
}
