# Technical Context

## Technologies Used

### Core Framework
- **Flutter**: 3.x (Dart 3.x) - Cross-platform mobile development
- **Firebase**: Backend-as-a-Service platform
  - **Firestore**: NoSQL document database
  - **Cloud Functions**: Serverless compute
  - **Cloud Messaging (FCM)**: Push notifications
  - **Authentication**: User management (configured but not heavily used in visible code)

### Development Tools
- **IDE**: Visual Studio Code with Flutter/Dart extensions
- **Version Control**: Git (GitHub repository)
- **Package Management**: Pub (Dart packages)
- **Build Tools**: Gradle (Android), Xcode (iOS implied)
- **CLI Tools**: Flutter CLI, Firebase CLI

### Key Dependencies (from pubspec.yaml)
```yaml
dependencies:
  flutter: SDK
  firebase_core: ^2.x
  cloud_firestore: ^4.x
  firebase_messaging: ^14.x
  provider: ^6.x (state management)
  shared_preferences: ^2.x (theme persistence)
  intl: ^0.19.x (for date formatting)
```

## Development Setup

### Environment Requirements
- **Flutter SDK**: 3.x stable
- **Dart SDK**: 3.x
- **Android Studio**: For Android development
- **Xcode**: For iOS development (implied)
- **Java JDK**: For Android builds
- **Firebase Project**: Configured with Firestore, Functions, Messaging

### Project Structure
```
├── android/          # Android-specific configuration
├── ios/             # iOS-specific configuration (generated)
├── lib/             # Flutter source code
├── functions/       # Firebase Cloud Functions
├── test/            # Unit tests
├── web/             # Web build output
└── windows/         # Windows build output
```

### Firebase Configuration
- **firebase.json**: Hosting and functions configuration
- **firebase_options.dart**: Platform-specific Firebase config
- **serviceAccountKey.json**: Server-side authentication

## Technical Constraints

### Platform Limitations
- **Mobile-First**: Designed for mobile devices, web support secondary
- **Firebase Dependency**: Tied to Firebase ecosystem
- **Real-time Requirements**: Firestore streams drive UI updates

### Performance Constraints
- **Stream Efficiency**: Large employee lists may cause UI lag
- **Network Dependency**: Requires internet for core functionality
- **Battery Impact**: Push notifications and real-time updates

### Development Constraints
- **Null Safety**: Full null safety required (Dart 3.x)
- **Flutter Compatibility**: Must maintain compatibility across Flutter versions
- **Firebase SDK Updates**: Regular updates required for security/features

## Dependencies and Tool Usage Patterns

### Package Usage Patterns
- **firebase_core**: App initialization and Firebase setup
- **cloud_firestore**: All data operations (CRUD, streams, queries)
- **firebase_messaging**: Push notification handling
- **intl**: Date/time formatting and localization

### Code Patterns
- **StreamBuilder**: Reactive UI for real-time data
- **FutureBuilder**: Async operations with loading states
- **StatefulBuilder**: Complex dialog state management
- **ScaffoldMessenger**: User feedback and error messages

### Build Patterns
- **Debug Builds**: Primary development workflow
- **Release Builds**: Production deployment
- **Platform-Specific**: Separate builds for Android/iOS

## Development Workflow

### Local Development
1. **Setup**: `flutter pub get` for dependencies
2. **Firebase**: `firebase init` for local functions
3. **Emulators**: `firebase emulators:start` for local testing
4. **Build**: `flutter run` for device testing

### Deployment
1. **Functions**: `firebase deploy --only functions`
2. **Mobile**: Build APKs/IPAs for distribution
3. **Web**: `flutter build web` for web deployment

### Testing Strategy
- **Unit Tests**: Model and utility testing
- **Integration Tests**: Firebase operations
- **Manual Testing**: UI/UX validation on devices

## Known Technical Debt
- **Deprecated APIs**: Some Flutter widgets use deprecated properties (withOpacity, value in DropdownButtonFormField)
- **Performance**: No optimization for large datasets yet
- **Error Handling**: Basic error handling, could be more robust
- **Code Coverage**: Limited test coverage

## Future Technical Considerations
- **State Management**: May need more robust solution (Bloc, Riverpod) for complex features
- **Offline Support**: Consider local caching for offline functionality
- **Security**: Review Firebase security rules
- **Scalability**: Monitor Firestore costs and performance at scale
- **Multi-platform**: Expand web and desktop support