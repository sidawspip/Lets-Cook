class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://xynk.in/api',
  );
  static const authBaseUrl = String.fromEnvironment(
    'AUTH_BASE_URL',
    defaultValue: 'https://xynk.in',
  );
  static const appBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: 'https://xynk.in',
  );
  static const realm = 'xynk';
  static const clientId = 'lets-cook-mobile';
  static const registrationClientId = 'lets-cook-web';
  static const oauthRedirectUrl = 'world.letscook.app:/oauthredirect';
  static const googleWebClientId =
      '964609721877-vne7f4q1uu6lb7oalj55h67irqm8hva5.apps.googleusercontent.com';
  static String get oidcDiscoveryUrl =>
      '$authBaseUrl/realms/$realm/.well-known/openid-configuration';

  static Uri get registrationUri =>
      Uri.parse(
        '$authBaseUrl/realms/$realm/protocol/openid-connect/registrations',
      ).replace(
        queryParameters: {
          'client_id': registrationClientId,
          'response_type': 'code',
          'scope': 'openid profile email',
          'redirect_uri': appBaseUrl,
        },
      );
}
