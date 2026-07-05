/// Result of parsing a SA license disc or ID document (PDF417 or manual).
enum SecurityDocumentType {
  licenseDisc,
  idDocument,
  /// SA driver's licence card (PDF417 on back — encrypted payload).
  driverLicence,
  unknown,
}

class ParsedDocument {
  final SecurityDocumentType documentType;
  final String? vehicleReg;
  final DateTime? expiryDate;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColour;
  final String? firstName;
  final String? lastName;
  final String? idNumber;
  final String? rawPayload;
  final bool manualEntry;

  const ParsedDocument({
    this.documentType = SecurityDocumentType.unknown,
    this.vehicleReg,
    this.expiryDate,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColour,
    this.firstName,
    this.lastName,
    this.idNumber,
    this.rawPayload,
    this.manualEntry = false,
  });

  String? get fullName {
    final parts = [
      if (firstName != null && firstName!.isNotEmpty) firstName,
      if (lastName != null && lastName!.isNotEmpty) lastName,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  bool get hasVehicleData =>
      vehicleReg != null ||
      expiryDate != null ||
      vehicleMake != null ||
      vehicleModel != null;

  bool get hasIdData =>
      idNumber != null || firstName != null || lastName != null;

  bool get hasDriverLicenceData =>
      documentType == SecurityDocumentType.driverLicence &&
      (manualEntry
          ? hasIdData
          : (idNumber?.replaceAll(RegExp(r'\D'), '').length == 13 &&
              (firstName != null || lastName != null)));

  ParsedDocument copyWith({
    SecurityDocumentType? documentType,
    String? vehicleReg,
    DateTime? expiryDate,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleColour,
    String? firstName,
    String? lastName,
    String? idNumber,
    String? rawPayload,
    bool? manualEntry,
  }) {
    return ParsedDocument(
      documentType: documentType ?? this.documentType,
      vehicleReg: vehicleReg ?? this.vehicleReg,
      expiryDate: expiryDate ?? this.expiryDate,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleColour: vehicleColour ?? this.vehicleColour,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      idNumber: idNumber ?? this.idNumber,
      rawPayload: rawPayload ?? this.rawPayload,
      manualEntry: manualEntry ?? this.manualEntry,
    );
  }
}