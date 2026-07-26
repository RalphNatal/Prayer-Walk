# Credential Manager, used by google_sign_in v7 on Android, loads its Google
# Play Services implementation reflectively. R8 doesn't see those references and
# strips the classes, so Google sign-in fails in *release* builds only — a bug
# that never shows up in debug. Keep them.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
