import 'dart:js_interop';

@JS('window.location.reload')
external void _jsReload();

void reloadPage() => _jsReload();
