import 'package:flutter_test/flutter_test.dart';
import 'package:ctp_job_cards/models/parsed_document.dart';
import 'package:ctp_job_cards/services/security_document_parser.dart';

void main() {
  group('SecurityDocumentParser — live Firestore golden samples', () {
    test('national ID pipe-delimited PDF417 (Ykexow0PIsOs4UE9HWKD)', () {
      const raw =
          'PEENS|GERT JACOBUS PETRUS|M|RSA|8901215025082|21 JAN 1989|RSA|CITIZEN|22 OCT 2015|40204|100606163|123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
      final doc = SecurityDocumentParser.parseIdDocument(raw);
      expect(doc.documentType, SecurityDocumentType.idDocument);
      expect(doc.lastName, 'PEENS');
      expect(doc.firstName, 'GERT JACOBUS PETRUS');
      expect(doc.idNumber, '8901215025082');
    });

    test('vehicle licence disc MVL PDF417 — plate, make, model', () {
      const raw =
          '%MVL1CC09%0158%2055A1D5%1%205500567LPF%ND663248%DPH802L%Sedan (closed top) / Sedan (toe-kap)%TOYOTA%YARIS%Blue / Blou%JTDBW903601218167%2NZ5924086%2022-10-31%';
      final doc = SecurityDocumentParser.parseLicenseDisc(raw);
      expect(doc.documentType, SecurityDocumentType.licenseDisc);
      expect(doc.vehicleReg, 'ND663248');
      expect(doc.vehicleMake, 'TOYOTA');
      expect(doc.vehicleModel, 'YARIS');
      expect(doc.expiryDate?.toIso8601String().split('T').first, '2022-10-31');
    });

    test('driver licence is separate from vehicle licence disc', () {
      const disc =
          '%MVL1CC09%0158%2055A1D5%1%205500567LPF%ND663248%DPH802L%Sedan (closed top) / Sedan (toe-kap)%TOYOTA%YARIS%Blue / Blou%JTDBW903601218167%2NZ5924086%2022-10-31%';
      final driver = SecurityDocumentParser.parseDriverLicence(disc);
      expect(driver.documentType, SecurityDocumentType.driverLicence);
      expect(driver.vehicleReg, isNull);
    });

    test('driver licence parses decrypted PDF417 golden sample', () {
      const sampleB64 =
          'Am0WAwAyARaCWkLh4eFTQU5ERVJT4ErhWkHgWkHgMOHh4TYyMzQ1NjAwMDFBQuA4NjA5MTM1MTM5MDEyAiAHAhmqoQoBGYYJEyASERQgFxIUAVdJBAD6AMhDLihAAChCNFWnQrzo0jDnNeVd2987O9NM9v45zkHm/ll7Ivb5cBQx7vfrFr3e975/m97of/HDQKGCh/LRixwt8OqE5KhYXoNDmoVPDQKFWdbMIXtUo8+40zll0RmpShJw785Ys/luDajQ1gRRksEkr7FjiKHRMO4wpyFBGMJfagh7iuNxHOEMJFrGOBpRg5UETHrDTx0mx9RmWuHQjFA+Naa7abq64z0qL5B3ktR5oFuN4rtWXoZeql6MiPthbIY+vGEUN5mPczaChm0UvGwwkQckiCBP+LSAAVexEcEgAKywW4F+62PhksQeG6Zx/0fCjSQUBWD4fEwVwSnz5ARYJAVimcsOERK2EkQ0kXYSqR2NGSxZ9JY1ADb8Y2aC1hQPh/F/NXq+j/IVV3ratkIa1ETAaPu91/FhMgl1MdUWp5yn8UVVm+wFiWW1IC/UsvkUOkKHhSYCaMqt5loAOXGqumWXwtoOK4QcqHboj8RwAqatEPFrOGDu9ChjRI9HpjPpgvTsB3VGApj8Q8RXRPC8zi097mSBVqhNcGcO2vSTKjjIPC5yG+ISRwvFBBnEW9tarAR3lZ98IAMIQgu0VTRca4lsqeIB8xjXXuw1l24bRDiPYi5JEwAlWO09CP+G+6jYdgVLBYskCWGukFDX2g2NLBGjvYB47rCucJ8Yhgjdik1EAgNiKFN3KCCS6qCixBMkBqrbd0FnPWnX3eYFjOWqLbVoEAUARFpF1RRFEBRZS4YgoqogABY7UAEAFFAFVVUBBEVAVVQQAAAAAAAAAAAAAAAA';
      final doc = SecurityDocumentParser.parseDriverLicence('base64:$sampleB64');
      expect(doc.documentType, SecurityDocumentType.driverLicence);
      expect(doc.lastName, 'SANDERS');
      expect(doc.firstName, 'J');
      expect(doc.idNumber, '8609135139012');
      expect(doc.expiryDate?.toIso8601String().split('T').first, '2017-12-14');
    });
  });

  group('SecurityDocumentParser — legacy percent sample', () {
    test('last reg token wins in older FORD sample', () {
      const raw =
          '%FORD%ND795940%WZ439W%2019-09-30%Hatch back%Engine WF05XXGC5FT62244%';
      final doc = SecurityDocumentParser.parseLicenseDisc(raw);
      expect(doc.vehicleReg, 'WZ439W');
      expect(doc.expiryDate?.toIso8601String().split('T').first, '2019-09-30');
    });
  });
}