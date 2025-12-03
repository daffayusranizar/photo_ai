# AI Photo Generator

A Flutter application that transforms selfies into professional travel photos using Google's Gemini 2.0 Flash and Google Cloud Imagen 3.

## 🚀 Setup Instructions

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.10.0 or higher)
- [Node.js](https://nodejs.org/) (v18 or higher)
- [Firebase CLI](https://firebase.google.com/docs/cli)

### Installation

1.  **Clone the repository**
    ```bash
    git clone <repository-url>
    cd photo_ai
    ```

2.  **Install Flutter dependencies**
    ```bash
    flutter pub get
    ```

3.  **Install Cloud Functions dependencies**
    ```bash
    cd functions
    npm install
    cd ..
    ```

### Configuration

1.  **Firebase Setup**
    - Create a new project in the [Firebase Console](https://console.firebase.google.com/).
    - Enable **Authentication** (Anonymous).
    - Enable **Firestore Database**.
    - Enable **Storage**.
    - Upgrade to the **Blaze Plan** (required for Cloud Functions and external APIs).

2.  **Add Firebase Config Files**
    - Download `google-services.json` (Android) and place it in `android/app/`.
    - Download `GoogleService-Info.plist` (iOS) and place it in `ios/Runner/`.

3.  **Configure Environment Variables**
    Set your Gemini API key in the Cloud Functions configuration:
    ```bash
    firebase functions:config:set gemini.key="YOUR_GEMINI_API_KEY"
    ```

4.  **Deploy Cloud Functions**
    ```bash
    firebase deploy --only functions
    ```

5.  **Deploy Security Rules**
    ```bash
    firebase deploy --only firestore
    ```

### Running the App

```bash
flutter run
```

---

## 🏗️ Architecture

This project follows **Clean Architecture** principles to ensure separation of concerns, testability, and maintainability.

### Layers
1.  **Presentation Layer**:
    - **Pages**: `RemixPage` (Main UI), `HistoryPage`, `AuthPage`.
    - **State Management**: Uses `setState` for local UI state and `StreamBuilder` for real-time data updates from Firestore.
2.  **Domain Layer**:
    - **Entities**: `Photo` (Core business object).
    - **Use Cases**: `UploadPhoto`, `GetPhotos`, `SignInAnonymously`.
    - **Repositories**: Abstract interfaces defining data operations.
3.  **Data Layer**:
    - **Data Sources**: `PhotoRemoteDataSource` (Firebase interactions).
    - **Repositories**: `PhotoRepositoryImpl` (Implementation of domain interfaces).
    - **Models**: Data transfer objects (if needed).

### Tech Stack
-   **Frontend**: Flutter (Dart)
-   **Backend**: Firebase Cloud Functions (Node.js)
-   **Database**: Cloud Firestore (NoSQL)
-   **Storage**: Firebase Storage
-   **AI**:
    -   **Gemini 2.0 Flash**: Analyzes user selfies to generate detailed subject descriptions.
    -   **Imagen 3**: Generates high-quality photorealistic travel images based on the prompts.

---

## 🔒 Security Approach

### 1. User Isolation via Security Rules
Firestore security rules are strictly configured to ensure users can only access their own data.
```javascript
match /users/{userId}/{document=**} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```
This prevents unauthorized access to other users' photos or prompts.

### 2. Secrets Management
Sensitive keys, such as the Gemini API key, are **not hardcoded** in the application source code.
-   They are stored securely using **Firebase Functions Configuration**.
-   Accessed at runtime via `functions.config().gemini.key`.

### 3. Backend Logic Protection
The core AI generation logic resides in **Cloud Functions**, which runs in a trusted environment.
-   The client app **cannot** directly call the AI APIs.
-   The client only uploads an image and sets preferences; the backend handles the rest, ensuring quota management and prompt integrity.

### 4. Anonymous Authentication
The app uses Firebase Anonymous Authentication to secure user sessions without requiring an immediate sign-up, lowering the barrier to entry while maintaining security contexts for data access.
