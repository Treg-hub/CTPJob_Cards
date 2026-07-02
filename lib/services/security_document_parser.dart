import 'dart:typed_data';

import 'package:rsa_driver_license_parsing/rsa_driver_license_parsing.dart';

import '../models/parsed_document.dart';
import '../models/security_vehicle.dart';
import '../utils/barcode_payload_util.dart';

/// Parses SA vehicle license disc and ID document PDF417 payloads from mobile_scanner.
class SecurityDocumentParser {
  SecurityDocumentParser._();

  static final RegExp _saReg = RegExp(
    r'\b([A-Z]{2}\d{6}|[A-Z]{1,3}\s?\d{2,4}\s?[A-Z]{0,3}|\d{2,3}\s?[A-Z]{2,3}\s?\d{2,4})\b',
    caseSensitive: false,
  );

  static final RegExp _saIdNumber = RegExp(r'\b\d{13}\b');

  static final RegExp _isoDate = RegExp(
    r'\b(\d{4})[/-](\d{2})[/-](\d{2})\b',
  );

  static final RegExp _saDate = RegExp(
    r'\b(\d{2})[/-](\d{2})[/-](\d{4})\b',
  );

  static final RegExp _vin = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  static const _knownMakes = {
    'TOYOTA', 'FORD', 'VOLKSWAGEN', 'VW', 'BMW', 'MERCEDES', 'NISSAN', 'HYUNDAI',
    'KIA', 'MAZDA', 'HONDA', 'ISUZU', 'SUZUKI', 'AUDI', 'CHEVROLET', 'RENAULT',
    'OPEL', 'PEUGEOT', 'CITROEN', 'JEEP', 'LAND ROVER', 'VOLVO', 'MAN', 'IVECO',
  };

  /// Auto-detect disc vs ID and parse.
  static ParsedDocument parseBarcode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const ParsedDocument(rawPayload: '');
    }

    if (_looksLikeMvlDisc(trimmed)) {
      final mvl = _parseMvlLicenseDisc(trimmed);
      if (mvl != null && mvl.hasVehicleData) return mvl;
    }

    final disc = parseLicenseDisc(trimmed);
    if (disc.hasVehicleData) return disc;

    final id = parseIdDocument(trimmed);
    if (id.hasIdData) return id;

    return ParsedDocument(
      documentType: SecurityDocumentType.unknown,
      rawPayload: trimmed,
    );
  }

  /// SA vehicle license disc — PDF417 raw string (delimiter-heavy).
  static ParsedDocument parseLicenseDisc(String raw) {
    final payload = raw.trim();

    if (_looksLikeMvlDisc(payload)) {
      final mvl = _parseMvlLicenseDisc(payload);
      if (mvl != null) return mvl;
    }

    final parts = _splitPayload(payload);
    String? reg;
    DateTime? expiry;
    String? make;
    String? colour;
    final regCandidates = <String>[];

    for (final part in parts) {
      final normalized = part.trim();
      if (normalized.isEmpty) continue;

      final maybeReg = _extractReg(normalized);
      if (maybeReg != null && !_isDiscSerial(normalized)) {
        regCandidates.add(maybeReg);
        continue;
      }

      final maybeDate = _extractDate(normalized);
      if (expiry == null && maybeDate != null) {
        expiry = maybeDate;
        continue;
      }

      if (make == null && _looksLikeMake(normalized)) {
        make = normalized;
        continue;
      }

      if (colour == null && _looksLikeColour(normalized)) {
        colour = normalized;
      }
    }

    if (regCandidates.isNotEmpty) {
      // Legacy %-delimited discs (non-MVL): plate reg is the last reg-like token.
      reg = regCandidates.last;
    } else {
      reg = _extractReg(payload);
    }
    expiry ??= _extractDate(payload);

    return ParsedDocument(
      documentType: SecurityDocumentType.licenseDisc,
      vehicleReg: reg != null ? SecurityVehicle.normalizeReg(reg) : null,
      expiryDate: expiry,
      vehicleMake: make,
      vehicleColour: colour,
      rawPayload: payload,
    );
  }

  /// SA driver's licence card — PDF417 on the **back** of the card (encrypted).
  /// The 1D barcode on the front is not used here.
  static ParsedDocument parseDriverLicence(String raw) {
    final payload = raw.trim();
    if (payload.isEmpty) {
      return const ParsedDocument(
        documentType: SecurityDocumentType.driverLicence,
        rawPayload: '',
      );
    }

    final bytes = BarcodePayloadUtil.decodeBytesPayload(payload);
    if (bytes != null && bytes.isNotEmpty) {
      final license = _parseDrivingLicenseBytes(bytes);
      if (license != null) {
        return _parsedDocumentFromDrivingLicense(license, payload);
      }
    }

    // Plain-text fallback if a scanner returns something readable.
    final id = _saIdNumber.firstMatch(payload)?.group(0);

    return ParsedDocument(
      documentType: SecurityDocumentType.driverLicence,
      idNumber: id,
      rawPayload: payload,
    );
  }

  /// Encrypted PDF417 scans are 720 bytes; some tools yield decrypted 684 bytes.
  static DrivingLicense? _parseDrivingLicenseBytes(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    try {
      if (data.length >= 720) {
        return SadlParser.parseLicense(data);
      }
      // Decrypted payload (post-RSA) — e.g. Scan Tester golden samples.
      // ignore: deprecated_member_use
      const tool = SadlTool();
      // ignore: deprecated_member_use
      return tool.parseData(data);
    } catch (_) {
      return null;
    }
  }

  static ParsedDocument _parsedDocumentFromDrivingLicense(
    DrivingLicense license,
    String rawPayload,
  ) {
    return ParsedDocument(
      documentType: SecurityDocumentType.driverLicence,
      lastName: license.surname.isNotEmpty ? license.surname : null,
      firstName: license.initials.isNotEmpty ? license.initials : null,
      idNumber: license.idNumber.isNotEmpty ? license.idNumber : null,
      expiryDate: _parseSadlDate(license.licenseExpiryDate),
      rawPayload: rawPayload,
    );
  }

  static DateTime? _parseSadlDate(String value) {
    final parts = value.split('/');
    if (parts.length != 3) return null;
    return DateTime.tryParse(
      '${parts[0]}-${parts[1]}-${parts[2]}',
    );
  }

  /// SA ID book/card — PDF417 raw string.
  static ParsedDocument parseIdDocument(String raw) {
    final payload = raw.trim();

    final pipe = _parsePipeDelimitedId(payload);
    if (pipe != null) return pipe;

    final parts = _splitPayload(payload);

    String? idNumber;
    String? surname;
    String? firstNames;

    for (final part in parts) {
      final normalized = part.trim();
      if (normalized.isEmpty) continue;

      final idMatch = _saIdNumber.firstMatch(normalized);
      if (idNumber == null && idMatch != null) {
        idNumber = idMatch.group(0);
        continue;
      }

      if (surname == null && _looksLikeSurnameLabel(normalized, parts)) {
        surname = _valueAfterLabel(normalized) ?? normalized;
        continue;
      }

      if (firstNames == null && _looksLikeNamesLabel(normalized)) {
        firstNames = _valueAfterLabel(normalized) ?? normalized;
      }
    }

    idNumber ??= _saIdNumber.firstMatch(payload)?.group(0);

    if (surname == null || firstNames == null) {
      final nameParts = parts
          .where((p) => p.trim().isNotEmpty && !_saIdNumber.hasMatch(p))
          .map((p) => p.trim())
          .where((p) => p.length > 1 && RegExp(r'[A-Za-z]').hasMatch(p))
          .toList();
      if (nameParts.length >= 2) {
        surname ??= nameParts.first;
        firstNames ??= nameParts.sublist(1).join(' ');
      } else if (nameParts.length == 1) {
        firstNames ??= nameParts.first;
      }
    }

    return ParsedDocument(
      documentType: SecurityDocumentType.idDocument,
      idNumber: idNumber,
      lastName: surname,
      firstName: firstNames,
      rawPayload: payload,
    );
  }

  /// Manual fallback when scan fails.
  static ParsedDocument manualLicenseDisc({
    required String vehicleReg,
    DateTime? expiryDate,
    String? vehicleMake,
    String? vehicleColour,
  }) {
    return ParsedDocument(
      documentType: SecurityDocumentType.licenseDisc,
      vehicleReg: SecurityVehicle.normalizeReg(vehicleReg),
      expiryDate: expiryDate,
      vehicleMake: vehicleMake,
      vehicleColour: vehicleColour,
      manualEntry: true,
    );
  }

  static ParsedDocument manualDriverLicence({
    required String idNumber,
    String? firstName,
    String? lastName,
    DateTime? expiryDate,
  }) {
    return ParsedDocument(
      documentType: SecurityDocumentType.driverLicence,
      idNumber: idNumber.trim(),
      firstName: firstName,
      lastName: lastName,
      expiryDate: expiryDate,
      manualEntry: true,
    );
  }

  static ParsedDocument manualIdDocument({
    required String idNumber,
    String? firstName,
    String? lastName,
    DateTime? expiryDate,
  }) {
    return ParsedDocument(
      documentType: SecurityDocumentType.idDocument,
      idNumber: idNumber.trim(),
      firstName: firstName,
      lastName: lastName,
      expiryDate: expiryDate,
      manualEntry: true,
    );
  }

  static bool _looksLikeMvlDisc(String payload) {
    return payload.toUpperCase().contains('%MVL');
  }

  /// eNaTIS MVL licence disc — `%MVL1CC09%...%SERIAL%LICENCE%PLATE%...%MAKE%...%`.
  /// After the disc serial, visitor discs carry licence number then veh. register
  /// (e.g. CG24MTZN then VCG592W). Fleet/company discs often use plate-first.
  static ParsedDocument? _parseMvlLicenseDisc(String payload) {
    final parts = _splitPayload(payload)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty || !parts.first.toUpperCase().startsWith('MVL')) {
      return null;
    }

    DateTime? expiry;
    String? reg;
    String? make;
    String? model;
    String? colour;
    var afterDiscSerial = false;
    final postSerialCandidates = <String>[];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      expiry ??= _extractDate(part);
      if (_vin.hasMatch(part)) continue;

      if (_isDiscSerial(part)) {
        afterDiscSerial = true;
        postSerialCandidates.clear();
        continue;
      }

      if (afterDiscSerial && reg == null) {
        if (_isPlateCandidate(part)) {
          postSerialCandidates.add(part);
          if (postSerialCandidates.length >= 2) {
            reg = _pickPlateReg(postSerialCandidates);
            afterDiscSerial = false;
          }
          continue;
        }
        if (part.contains(' / ') || _isKnownMake(part)) {
          reg = postSerialCandidates.isEmpty
              ? null
              : _pickPlateReg(postSerialCandidates);
          afterDiscSerial = false;
        }
      }

      if (make == null && _isKnownMake(part)) {
        reg ??= postSerialCandidates.isEmpty
            ? null
            : _pickPlateReg(postSerialCandidates);
        afterDiscSerial = false;
        make = part;
        if (i + 1 < parts.length) {
          final next = parts[i + 1];
          if (_extractDate(next) == null &&
              !_vin.hasMatch(next) &&
              !_isKnownMake(next) &&
              !_looksLikeColour(next)) {
            model = next;
          }
        }
        continue;
      }

      if (colour == null && _looksLikeColour(part)) {
        colour = part;
      } else if (colour == null && part.contains(' / ')) {
        reg ??= postSerialCandidates.isEmpty
            ? null
            : _pickPlateReg(postSerialCandidates);
        afterDiscSerial = false;
        colour = part;
      }
    }

    reg ??= postSerialCandidates.isEmpty
        ? null
        : _pickPlateReg(postSerialCandidates);

    return ParsedDocument(
      documentType: SecurityDocumentType.licenseDisc,
      vehicleReg: reg != null ? SecurityVehicle.normalizeReg(reg) : null,
      expiryDate: expiry,
      vehicleMake: make,
      vehicleModel: model,
      vehicleColour: colour,
      rawPayload: payload,
    );
  }

  static bool _isPlateCandidate(String value) {
    final upper = value.toUpperCase().trim();
    if (upper.isEmpty || _vin.hasMatch(upper)) return false;
    if (_isDiscSerial(upper)) return false;
    if (_extractDate(upper) != null && upper.length <= 12) return false;
    return RegExp(r'^[A-Z0-9]{5,10}$').hasMatch(upper);
  }

  /// Licence numbers (CG24MTZN) precede veh. register (VCG592W) on visitor discs.
  static bool _looksLikeLicenceNumber(String value) {
    final upper = value.toUpperCase().trim();
    return RegExp(r'^[A-Z]{2}\d{2}[A-Z]{2,4}$').hasMatch(upper);
  }

  /// CTP fleet / company register plates (BX33HKZN, CH09TJZN) on MVL barcodes.
  static bool _looksLikeFleetRegisterPlate(String value) {
    final upper = value.toUpperCase().trim();
    return RegExp(r'(GPZN|HKZN|TJZN)$').hasMatch(upper);
  }

  static bool _looksLikeClassicPlate(String value) {
    final upper = value.toUpperCase().trim();
    if (RegExp(r'^[A-Z]{2}\d{6}$').hasMatch(upper)) return true;
    if (RegExp(r'^[A-Z]{2,3}\d{3}[A-Z]$').hasMatch(upper)) return true;
    if (RegExp(r'^[A-Z]{3}\d{3}[A-Z]{2}$').hasMatch(upper)) return true;
    return _extractReg(upper) != null && !_looksLikeFleetRegisterPlate(upper);
  }

  static String _pickPlateReg(List<String> candidates) {
    if (candidates.length == 1) {
      return SecurityVehicle.normalizeReg(candidates.first);
    }
    final first = candidates[0];
    final second = candidates[1];

    if (_looksLikeFleetRegisterPlate(first)) {
      return SecurityVehicle.normalizeReg(first);
    }
    if (_looksLikeLicenceNumber(first) &&
        !_looksLikeFleetRegisterPlate(first) &&
        _looksLikeClassicPlate(second)) {
      return SecurityVehicle.normalizeReg(second);
    }
    if (_looksLikeClassicPlate(first) && _looksLikeClassicPlate(second)) {
      return SecurityVehicle.normalizeReg(first);
    }
    return SecurityVehicle.normalizeReg(first);
  }

  /// SA green ID book / smart ID — `SURNAME|FIRST NAMES|SEX|...|ID|DOB|...`.
  static ParsedDocument? _parsePipeDelimitedId(String payload) {
    if (!payload.contains('|') || payload.startsWith('%')) return null;

    final fields = payload.split('|').map((f) => f.trim()).toList();
    if (fields.length < 5) return null;

    final idField = fields[4];
    final idMatch = _saIdNumber.firstMatch(idField);
    if (idMatch == null) return null;

    return ParsedDocument(
      documentType: SecurityDocumentType.idDocument,
      lastName: fields[0].isNotEmpty ? fields[0] : null,
      firstName: fields.length > 1 && fields[1].isNotEmpty ? fields[1] : null,
      idNumber: idMatch.group(0),
      rawPayload: payload,
    );
  }

  /// eNaTIS disc serial — legacy `…LPF`, `205500575VY0`, or `2008045XWLWVV` styles.
  static bool _isDiscSerial(String value) {
    final upper = value.toUpperCase().trim();
    if (upper.endsWith('LPF') || upper.contains('LICENCE')) return true;
    if (RegExp(r'^2055\d{5,}[A-Z0-9]{3}$').hasMatch(upper)) return true;
    // Printed disc NO. e.g. 2008045XWLWVV (visitor / older format).
    if (RegExp(r'^\d{7}[A-Z0-9]{4,}$').hasMatch(upper)) return true;
    return false;
  }

  static bool _isKnownMake(String value) {
    final upper = value.toUpperCase().trim();
    if (_knownMakes.contains(upper)) return true;
    for (final make in _knownMakes) {
      if (upper.startsWith('$make ')) return true;
    }
    return false;
  }

  static List<String> _splitPayload(String raw) {
    if (raw.contains('%')) {
      return raw.split('%').where((s) => s.trim().isNotEmpty).toList();
    }
    if (raw.contains('|')) {
      return raw.split('|').where((s) => s.trim().isNotEmpty).toList();
    }
    if (raw.contains(';')) {
      return raw.split(';').where((s) => s.trim().isNotEmpty).toList();
    }
    if (raw.contains('\n')) {
      return raw.split('\n').where((s) => s.trim().isNotEmpty).toList();
    }
    return [raw];
  }

  static String? _extractReg(String text) {
    final match = _saReg.firstMatch(text.toUpperCase());
    if (match == null) return null;
    return SecurityVehicle.normalizeReg(match.group(1));
  }

  static DateTime? _extractDate(String text) {
    final iso = _isoDate.firstMatch(text);
    if (iso != null) {
      return DateTime.tryParse(
        '${iso.group(1)}-${iso.group(2)}-${iso.group(3)}',
      );
    }
    final sa = _saDate.firstMatch(text);
    if (sa != null) {
      return DateTime.tryParse(
        '${sa.group(3)}-${sa.group(2)}-${sa.group(1)}',
      );
    }
    return null;
  }

  static bool _looksLikeMake(String value) {
    if (_isKnownMake(value)) return true;
    final v = value.toLowerCase();
    return v.contains('make') ||
        v.contains('model') ||
        (value.length > 2 &&
            RegExp(r'^[A-Za-z][A-Za-z0-9\s\-]{1,}$').hasMatch(value) &&
            !_saReg.hasMatch(value) &&
            !_saIdNumber.hasMatch(value));
  }

  static bool _looksLikeColour(String value) {
    final v = value.toLowerCase();
    const colours = [
      'white', 'black', 'silver', 'grey', 'gray', 'red', 'blue', 'green',
      'yellow', 'orange', 'brown', 'gold', 'maroon', 'beige', 'blou',
    ];
    return colours.any((c) => v == c || v.contains(c));
  }

  static bool _looksLikeSurnameLabel(String value, List<String> parts) {
    final v = value.toLowerCase();
    return v.contains('surname') || parts.indexOf(value) == 0;
  }

  static bool _looksLikeNamesLabel(String value) {
    final v = value.toLowerCase();
    return v.contains('names') || v.contains('firstname');
  }

  static String? _valueAfterLabel(String value) {
    final idx = value.indexOf(':');
    if (idx >= 0 && idx < value.length - 1) {
      return value.substring(idx + 1).trim();
    }
    return null;
  }
}