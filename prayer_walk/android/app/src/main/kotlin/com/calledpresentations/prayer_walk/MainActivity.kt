package com.calledpresentations.prayer_walk

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * TEMPORARY DIAGNOSTIC SCAFFOLDING — remove once the Play Store Google
 * sign-in failure is resolved.
 *
 * Google's auth servers answer `UNREGISTERED_ON_API_CONSOLE` when the package
 * name and signing certificate presented by the *installed* app are not on an
 * Android OAuth client. The package name is knowable from source; the
 * certificate is not. Play App Signing re-signs the uploaded bundle with keys
 * nobody on this side of the upload holds, so the only honest way to learn
 * which certificate a device is actually verifying against is to ask the
 * device.
 *
 * That is all this channel does: read the signatures off the installed package
 * and hand back their fingerprints. It reads nothing else, changes nothing, and
 * is only ever called when the Dart side has diagnostics explicitly enabled
 * (`--dart-define=PW_ENABLE_DIAGNOSTICS=true`).
 *
 * Fingerprints are public identifiers — they are printed in the Play Console
 * and in Google Cloud Console — so unlike client IDs they are safe to log and
 * display in full.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIGNING_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The structured form, and the one the Dart side calls: both
                    // digests in a single round trip, with any failure reported
                    // as a string rather than as a channel error, so a device
                    // that refuses to answer still puts *something* on screen.
                    "fingerprints" -> result.success(fingerprints())
                    "sha1" -> result.success(digestsOrEmpty(SHA_1))
                    "sha256" -> result.success(digestsOrEmpty(SHA_256))
                    else -> result.notImplemented()
                }
            }
    }

    private fun fingerprints(): Map<String, Any?> = try {
        val certificates = signingCertificates()
        mapOf(
            "sha1" to certificates.map { fingerprint(SHA_1, it) },
            "sha256" to certificates.map { fingerprint(SHA_256, it) },
            "error" to if (certificates.isEmpty()) {
                "PackageManager returned no signing certificates for $packageName."
            } else {
                null
            },
        )
    } catch (error: Throwable) {
        // Never throw across the channel. A diagnostic that crashes the thing
        // it is diagnosing has made the problem worse, not smaller — so the
        // failure travels back as text the screen can show.
        mapOf(
            "sha1" to emptyList<String>(),
            "sha256" to emptyList<String>(),
            "error" to "${error.javaClass.simpleName}: ${error.message ?: "no message"}",
        )
    }

    private fun digestsOrEmpty(algorithm: String): List<String> = try {
        signingCertificates().map { fingerprint(algorithm, it) }
    } catch (error: Throwable) {
        emptyList()
    }

    /**
     * Every signer on the installed package, as raw certificate bytes.
     *
     * All of them, deliberately — not just the first. Which certificates appear
     * here is the entire question: Play's hybrid signing generates more than one
     * key, and a build can be verified against a certificate that was never
     * registered while another one on the same list was.
     */
    private fun signingCertificates(): List<ByteArray> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            // `apkContentsSigners` is the set the platform actually verified the
            // installed APK against, which is what Google's servers see.
            // `signingCertificateHistory` would only add keys this app has been
            // rotated *away* from, and those are not what is being checked.
            info.signingInfo?.apkContentsSigners?.map { it.toByteArray() }.orEmpty()
        } else {
            // Pre-P has no signingInfo at all. Deprecated on the SDK this
            // compiles against, and suppressed explicitly rather than left to
            // warn: on API 23–27 it is the only API that exists.
            @Suppress("DEPRECATION")
            packageManager
                .getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                .signatures
                ?.map { it.toByteArray() }
                .orEmpty()
        }

    /** Colon-separated uppercase hex, matching how Play and Google Cloud print it. */
    private fun fingerprint(algorithm: String, certificate: ByteArray): String =
        MessageDigest.getInstance(algorithm)
            .digest(certificate)
            .joinToString(":") { "%02X".format(it) }

    private companion object {
        const val SIGNING_CHANNEL = "prayer_walk/signing"
        const val SHA_1 = "SHA-1"
        const val SHA_256 = "SHA-256"
    }
}
