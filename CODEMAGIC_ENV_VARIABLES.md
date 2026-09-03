# ═══════════════════════════════════════════════════════════════════════════════
# CODEMAGIC ENVIRONMENT VARIABLES — SJ ACT
# ═══════════════════════════════════════════════════════════════════════════════
#
# Log in to https://codemagic.io  →  Your App  →  Environment variables
# Create a group called:  sj_act_secrets
# Add every variable below to that group.
#
# The codemagic.yaml references this group as:
#   environment:
#     groups:
#       - sj_act_secrets
#
# ───────────────────────────────────────────────────────────────────────────────
# VARIABLE NAME              │ VALUE / WHERE TO GET IT          │ SECRET?
# ───────────────────────────────────────────────────────────────────────────────

# 1. ACT API Key (production)
#    Must match SJACT_API_KEY in Django settings.
#    Format: SJACT-YYYY-<at least 20 random chars>
#    Generate one: python -c "import secrets; print('SJACT-2026-' + secrets.token_urlsafe(24))"
SJACT_API_KEY = "SJACT-2026-REPLACE_WITH_YOUR_REAL_KEY_HERE"
# SECRET: YES — tick "Secure" in Codemagic

# 2. ACT API Key (development / debug builds)
SJACT_API_KEY_DEV = "SJACT-2026-DEV-REPLACE_WITH_DEV_KEY"
# SECRET: YES

# 3. Android Keystore
#    Upload your .jks or .keystore file in:
#    Codemagic → Code signing → Android → Add keystore
#    Then reference it in codemagic.yaml under android_signing.
#    Name the keystore: sj_act_keystore
#
#    Codemagic will inject these automatically when you link the keystore:
CM_KEYSTORE_PATH = "(set by Codemagic after keystore upload)"
CM_KEYSTORE_PASSWORD = "smartjamb@8505"          # your keystore password
CM_KEY_ALIAS = "sj_act"                           # alias you gave the key
CM_KEY_PASSWORD = "smartjamb@8505"               # key password (often same as store password)
# SECRET: YES — Codemagic stores these encrypted automatically

# 4. Google Play credentials (for automatic Play Store publishing)
#    Download service account JSON from Google Play Console →
#    Setup → API access → Service accounts → Create → Grant access
#    Upload the JSON to Codemagic → Code signing → Google Play
#    It will be available as:
GCLOUD_SERVICE_ACCOUNT_CREDENTIALS = "(paste JSON content here or upload file)"
# SECRET: YES

# 5. Email notification (already in codemagic.yaml — no variable needed)
#    Recipient: smartjamb8505@gmail.com

# ───────────────────────────────────────────────────────────────────────────────
# ANDROID key.properties (place at android/key.properties — DO NOT commit to git)
# ───────────────────────────────────────────────────────────────────────────────
# storePassword=smartjamb@8505
# keyPassword=smartjamb@8505
# keyAlias=sj_act
# storeFile=../sj_act.keystore
#
# Add  android/key.properties  to .gitignore!

# ───────────────────────────────────────────────────────────────────────────────
# HOW TO GENERATE THE KEYSTORE (run once on your machine)
# ───────────────────────────────────────────────────────────────────────────────
# keytool -genkey -v \
#   -keystore sj_act.keystore \
#   -alias sj_act \
#   -keyalg RSA \
#   -keysize 2048 \
#   -validity 10000 \
#   -storepass "smartjamb@8505" \
#   -keypass "smartjamb@8505" \
#   -dname "CN=SmartJAMB ACT, OU=SmartJAMB, O=SmartJAMB, L=Lagos, S=Lagos, C=NG"
#
# Then upload  sj_act.keystore  to Codemagic → Android code signing.

# ───────────────────────────────────────────────────────────────────────────────
# PACKAGE NAME
# ───────────────────────────────────────────────────────────────────────────────
# com.sj_act
#
# Set in:
#   android/app/build.gradle   →  applicationId "com.sj_act"
#   android/app/src/main/AndroidManifest.xml  →  package="com.sj_act"

# ───────────────────────────────────────────────────────────────────────────────
# CODEMAGIC LOGIN PASSWORD
# ───────────────────────────────────────────────────────────────────────────────
# Email:    smartjamb8505@gmail.com
# Password: smartjamb@8505
# Sign in via GitHub OAuth or email at https://codemagic.io/login

# ───────────────────────────────────────────────────────────────────────────────
# SUMMARY TABLE — all variables to add in Codemagic group "sj_act_secrets"
# ───────────────────────────────────────────────────────────────────────────────
# Variable Name                    │ Secure │ Description
# ─────────────────────────────────┼────────┼────────────────────────────────────
# SJACT_API_KEY                    │  YES   │ Production API key (matches Django)
# SJACT_API_KEY_DEV                │  YES   │ Dev/debug API key
# CM_KEYSTORE_PASSWORD             │  YES   │ Keystore store password
# CM_KEY_ALIAS                     │  NO    │ sj_act
# CM_KEY_PASSWORD                  │  YES   │ Key password (same as store)
# GCLOUD_SERVICE_ACCOUNT_CREDENTIALS│ YES  │ Google Play service account JSON
# ─────────────────────────────────┴────────┴────────────────────────────────────
