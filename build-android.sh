#!/usr/bin/env bash
# Build script for PflanzPunkt Android APK
# Requirements: Node.js (npm), Java JDK 17+, Android SDK (ANDROID_HOME must be set)
# Usage: ./build-android.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_DIR="$SCRIPT_DIR"
export BUILD_DIR="/tmp/pflanzpunkt-apk-build"
BT="${ANDROID_HOME}/build-tools/35.0.0"
PLATFORM="${ANDROID_HOME}/platforms/android-35/android.jar"
OUTPUT_APK="$PROJECT_DIR/PflanzPunkt-debug.apk"

echo "=== PflanzPunkt Android APK Build ==="
echo ""

# Check requirements
if [ -z "$ANDROID_HOME" ]; then
    echo "ERROR: ANDROID_HOME is not set. Please install the Android SDK."
    exit 1
fi
if [ ! -f "$BT/aapt2" ]; then
    echo "ERROR: Android build-tools 35.0.0 not found at $BT"
    echo "Install via: sdkmanager 'build-tools;35.0.0'"
    exit 1
fi
if [ ! -f "$PLATFORM" ]; then
    echo "ERROR: Android platform 35 not found."
    echo "Install via: sdkmanager 'platforms;android-35'"
    exit 1
fi

# Step 1: Install npm dependencies and bundle web assets
echo "[1/7] Bundling web assets..."
cd "$PROJECT_DIR"
npm install --silent

# Generate Tailwind CSS
cat > tailwind-input.css << 'EOF'
@import "tailwindcss";
EOF
node_modules/.bin/tailwindcss -i tailwind-input.css -o www/tailwind.min.css --minify

# Copy Lucide icons from npm package
cp node_modules/lucide/dist/umd/lucide.min.js www/lucide.min.js

# Create www/index.html with local asset references
sed 's|<script src="https://cdn.tailwindcss.com"></script>|<link rel="stylesheet" href="tailwind.min.css">|g' index.html | \
sed 's|<script src="https://unpkg.com/lucide@latest"></script>|<script src="lucide.min.js"></script>|g' > www/index.html

cp manifest.json www/manifest.json

# Step 2: Prepare build directory
echo "[2/7] Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{src/com/pflanzpunkt/app,res/{layout,values,mipmap-hdpi,mipmap-mdpi,mipmap-xhdpi,mipmap-xxhdpi,mipmap-xxxhdpi},assets,gen,class_out,dex_out}

# Copy web assets
cp www/index.html "$BUILD_DIR/assets/"
cp www/tailwind.min.css "$BUILD_DIR/assets/"
cp www/lucide.min.js "$BUILD_DIR/assets/"
cp www/manifest.json "$BUILD_DIR/assets/"

# Create AndroidManifest.xml
cat > "$BUILD_DIR/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.pflanzpunkt.app"
    android:versionCode="1"
    android:versionName="1.0">

    <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:theme="@android:style/Theme.NoTitleBar.Fullscreen">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:configChanges="orientation|screenSize|keyboardHidden">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# Create strings.xml
cat > "$BUILD_DIR/res/values/strings.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">PflanzPunkt</string>
</resources>
EOF

# Create app icon from ic_launcher.svg
pip install --quiet cairosvg
python3 << 'PYEOF'
import cairosvg, os

svg_path = os.path.join(os.environ.get('PROJECT_DIR', '.'), 'ic_launcher.svg')
build_dir = os.environ.get('BUILD_DIR', '/tmp/pflanzpunkt-apk-build')
for size, dirname in [(48, 'mdpi'), (72, 'hdpi'), (96, 'xhdpi'), (144, 'xxhdpi'), (192, 'xxxhdpi')]:
    path = f'{build_dir}/res/mipmap-{dirname}/ic_launcher.png'
    cairosvg.svg2png(url=svg_path, write_to=path, output_width=size, output_height=size)
PYEOF

# Create MainActivity.java
cat > "$BUILD_DIR/src/com/pflanzpunkt/app/MainActivity.java" << 'EOF'
package com.pflanzpunkt.app;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.view.Window;

public class MainActivity extends Activity {
    private WebView webView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        webView = new WebView(this);
        setContentView(webView);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setMediaPlaybackRequiresUserGesture(false);

        webView.setWebViewClient(new WebViewClient());
        webView.setWebChromeClient(new WebChromeClient());
        webView.loadUrl("file:///android_asset/index.html");
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
EOF

# Step 3: Compile resources
echo "[3/7] Compiling resources..."
"$BT/aapt2" compile --dir "$BUILD_DIR/res" -o "$BUILD_DIR/compiled_res.zip"

# Step 4: Link resources
echo "[4/7] Linking resources..."
"$BT/aapt2" link \
    -o "$BUILD_DIR/linked.apk" \
    -I "$PLATFORM" \
    --manifest "$BUILD_DIR/AndroidManifest.xml" \
    --java "$BUILD_DIR/gen" \
    -A "$BUILD_DIR/assets" \
    "$BUILD_DIR/compiled_res.zip" \
    --allow-reserved-package-id \
    --min-sdk-version 24 \
    --target-sdk-version 35 \
    --version-code 1 \
    --version-name "1.0"

# Step 5: Compile Java sources
echo "[5/7] Compiling Java..."
javac \
    -classpath "$PLATFORM" \
    -sourcepath "$BUILD_DIR/gen:$BUILD_DIR/src" \
    -d "$BUILD_DIR/class_out" \
    -source 8 -target 8 \
    "$BUILD_DIR/src/com/pflanzpunkt/app/MainActivity.java" \
    "$BUILD_DIR/gen/com/pflanzpunkt/app/R.java" 2>&1 | grep -v "^Note:" | grep -v "^warning:" || true

"$BT/d8" \
    --output "$BUILD_DIR/dex_out" \
    --min-api 24 \
    $(find "$BUILD_DIR/class_out" -name "*.class")

# Step 6: Package APK
echo "[6/7] Packaging APK..."
cp "$BUILD_DIR/linked.apk" "$BUILD_DIR/unaligned.apk"
cd "$BUILD_DIR/dex_out" && zip -j "$BUILD_DIR/unaligned.apk" classes.dex
"$BT/zipalign" -f 4 "$BUILD_DIR/unaligned.apk" "$BUILD_DIR/aligned.apk"

# Step 7: Sign APK
echo "[7/7] Signing APK..."
KEYSTORE="$BUILD_DIR/debug.keystore"
if [ ! -f "$KEYSTORE" ]; then
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -alias debugkey \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -dname "CN=PflanzPunkt Debug, OU=Debug, O=PflanzPunkt, L=Juelich, ST=NRW, C=DE" \
        -storepass android \
        -keypass android 2>/dev/null
fi

"$BT/apksigner" sign \
    --ks "$KEYSTORE" \
    --ks-key-alias debugkey \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "$OUTPUT_APK" \
    "$BUILD_DIR/aligned.apk"

echo ""
echo "=== Build successful! ==="
echo "APK: $OUTPUT_APK ($(du -h "$OUTPUT_APK" | cut -f1))"
