# Keystore — SJ ACT

This folder holds the Android release keystore. It is NOT committed to git
(see .gitignore). The file must exist locally for local release builds, and
on Codemagic it is uploaded via the Code Signing dashboard.

## Generate the keystore (run once on your machine)

```bash
keytool -genkey -v \
  -keystore sj_act_release.jks \
  -alias sj_act \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "smartjamb@8505" \
  -keypass "smartjamb@8505" \
  -dname "CN=SmartJAMB ACT, OU=SmartJAMB, O=SmartJAMB, L=Lagos, S=Lagos, C=NG"
```

## Upload to Codemagic

1. Go to https://codemagic.io → Your App → Code signing → Android
2. Upload `sj_act_release.jks`
3. Set alias = `sj_act`, store password = `smartjamb@8505`, key password = `smartjamb@8505`
4. Name the signing identity: `sj_act_keystore` (must match codemagic.yaml)

## Local builds

Copy `android/key.properties.example` → `android/key.properties`
(already in .gitignore — never commit it).
