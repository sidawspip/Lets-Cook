# Xynk realm and local stack

The local Docker Compose project is `xynk`. It uses fresh `xynk_*` volumes, a PostgreSQL database and user named `xynk`, and one Keycloak application realm named `xynk`. The legacy `lets-cook` realm and volumes were removed on 2026-11-14 at the owner's request. Existing human accounts, social links, room data, history, uploads, and cache were erased. The Keycloak `master` administrator and the Xynk internal service account remain.

Keycloak OIDC client IDs (`lets-cook-web`, `lets-cook-mobile`, `lets-cook-native-google`), Android package/redirect scheme, Java package names, and the private secrets directory keep their legacy identifiers for compatibility with registered OAuth callbacks, installed apps, and existing signing material. They are not displayed as the product name.

To start the clean local stack, run `docker compose up -d --build`. New users must register or sign in with a configured provider. Local `demo` and `test` accounts no longer exist until explicitly recreated.
