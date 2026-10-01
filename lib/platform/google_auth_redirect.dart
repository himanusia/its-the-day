import 'google_auth_redirect_stub.dart'
    if (dart.library.js_interop) 'google_auth_redirect_web.dart'
    as implementation;

void redirectToGoogleAuth(String url) => implementation.redirectToGoogleAuth(url);
