package @@PACKAGE@@;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.View;
import android.view.WindowInsets;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * Single-activity host for the packaged web app in app/src/main/assets/www/.
 *
 * Framework-only on purpose: no AndroidX, no Kotlin plugin, no dependency
 * downloads beyond the Android Gradle Plugin itself. Everything the product
 * needs is expected to live in the HTML/CSS/JS under assets/www/.
 *
 * JavaScript can call into native code through window.AndroidBridge:
 *   AndroidBridge.getAppVersion()        -> "1.0"
 *   AndroidBridge.getVersionCode()       -> 1
 *   AndroidBridge.vibrate(30)            -> haptic pulse, milliseconds
 *   AndroidBridge.share(subject, text)   -> system share sheet
 *   AndroidBridge.openExternal(url)      -> hand a URL to the system browser
 */
public class MainActivity extends Activity {

    /**
     * Entry point of the app. Leave as the bundled asset for an offline app,
     * or replace with an https URL to ship a hosted web app.
     */
    private static final String START_URL = "file:///android_asset/www/index.html";

    private WebView webView;
    private Object predictiveBackCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        webView.setBackgroundColor(Color.parseColor("@@BG_COLOR@@"));
        setContentView(webView);
        applyWindowInsets(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setTextZoom(100);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);

        webView.setWebViewClient(new AppWebViewClient());
        webView.setWebChromeClient(new WebChromeClient());
        webView.addJavascriptInterface(new Bridge(), "AndroidBridge");

        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        } else {
            webView.loadUrl(START_URL);
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        // Android 13+ dispatches back through OnBackInvokedDispatcher and no
        // longer calls onBackPressed() when the app targets API 33 or higher.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && predictiveBackCallback == null && webView != null) {
            predictiveBackCallback = Back33.register(this, webView);
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (webView != null) {
            webView.saveState(outState);
        }
    }

    @Override
    protected void onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && predictiveBackCallback != null) {
            Back33.unregister(this, predictiveBackCallback);
            predictiveBackCallback = null;
        }
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    /** Back handling for Android 12 and below. */
    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    /**
     * Android 15/16 (targetSdk 35+) draw edge to edge and the old opt-out is
     * gone, so pad the WebView by the system bar and cutout insets instead of
     * letting content slide under them.
     */
    private void applyWindowInsets(final View target) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Insets30.apply(target);
        } else {
            target.setFitsSystemWindows(true);
        }
    }

    private boolean launchExternal(String url) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    // ---------------------------------------------------------------- native

    @android.annotation.TargetApi(Build.VERSION_CODES.R)
    private static final class Insets30 {
        static void apply(final View target) {
            target.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
                @Override
                public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                    Insets bars = insets.getInsets(
                            WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                    v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
                    return insets;
                }
            });
        }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.TIRAMISU)
    private static final class Back33 {
        static Object register(final Activity activity, final WebView view) {
            android.window.OnBackInvokedCallback callback =
                    new android.window.OnBackInvokedCallback() {
                        @Override
                        public void onBackInvoked() {
                            if (view != null && view.canGoBack()) {
                                view.goBack();
                            } else {
                                activity.finish();
                            }
                        }
                    };
            activity.getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback);
            return callback;
        }

        static void unregister(Activity activity, Object callback) {
            activity.getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(
                    (android.window.OnBackInvokedCallback) callback);
        }
    }

    // ---------------------------------------------------------------- bridge

    /** Exposed to JavaScript as window.AndroidBridge. Keep names stable. */
    final class Bridge {

        @JavascriptInterface
        public String getAppVersion() {
            try {
                PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
                return info.versionName == null ? "1.0" : info.versionName;
            } catch (Exception ignored) {
                return "1.0";
            }
        }

        @JavascriptInterface
        public int getVersionCode() {
            try {
                PackageInfo info = getPackageManager().getPackageInfo(getPackageName(), 0);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    return (int) info.getLongVersionCode();
                }
                return info.versionCode;
            } catch (Exception ignored) {
                return 1;
            }
        }

        @JavascriptInterface
        public String getPackageName() {
            return MainActivity.this.getPackageName();
        }

        @JavascriptInterface
        @SuppressWarnings("deprecation")
        public void vibrate(long millis) {
            final long ms = Math.max(1L, Math.min(millis, 1000L));
            runOnUiThread(new Runnable() {
                @Override
                @SuppressWarnings("deprecation")
                public void run() {
                    Vibrator vibrator = (Vibrator) getSystemService(VIBRATOR_SERVICE);
                    if (vibrator == null || !vibrator.hasVibrator()) {
                        return;
                    }
                    vibrator.vibrate(VibrationEffect.createOneShot(
                            ms, VibrationEffect.DEFAULT_AMPLITUDE));
                }
            });
        }

        @JavascriptInterface
        public void share(final String subject, final String text) {
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    Intent intent = new Intent(Intent.ACTION_SEND);
                    intent.setType("text/plain");
                    intent.putExtra(Intent.EXTRA_SUBJECT, subject == null ? "" : subject);
                    intent.putExtra(Intent.EXTRA_TEXT, text == null ? "" : text);
                    try {
                        startActivity(Intent.createChooser(intent, null));
                    } catch (Exception ignored) {
                        // No activity can handle the share request.
                    }
                }
            });
        }

        @JavascriptInterface
        public void openExternal(final String url) {
            if (url == null || url.trim().isEmpty()) {
                return;
            }
            runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    launchExternal(url.trim());
                }
            });
        }
    }

    // ---------------------------------------------------------- navigation

    private final class AppWebViewClient extends WebViewClient {

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri url = request == null ? null : request.getUrl();
            if (url == null) {
                return false;
            }
            String scheme = url.getScheme();
            if (scheme == null) {
                return false;
            }
            scheme = scheme.toLowerCase();

            if ("file".equals(scheme) || "about".equals(scheme)
                    || "data".equals(scheme) || "blob".equals(scheme)) {
                return false;
            }
            if ("http".equals(scheme) || "https".equals(scheme)) {
                // For a bundled offline app, keep in-app navigation inside the
                // packaged assets and send real web links to the browser. When
                // START_URL is itself an https URL this returns false and the
                // WebView navigates normally.
                boolean bundledApp = START_URL.startsWith("file:///android_asset/");
                boolean insideAssets = url.toString().startsWith("file:///android_asset/");
                if (bundledApp && !insideAssets) {
                    launchExternal(url.toString());
                    return true;
                }
                return false;
            }
            // mailto:, tel:, geo:, intent: and other custom schemes.
            return launchExternal(url.toString());
        }
    }
}
