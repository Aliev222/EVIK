import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../network/api_client.dart';

class GlobalErrorHandler {
  static void initialize() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logError('Flutter Error', details.exception, details.stack);
    };

    // Handle platform errors
    PlatformDispatcher.instance.onError = (error, stack) {
      _logError('Platform Error', error, stack);
      return true;
    };
  }

  static void _logError(String type, dynamic error, StackTrace? stack) {
    if (kDebugMode) {
      debugPrint('=== $type ===');
      debugPrint('Error: $error');
      if (stack != null) {
        debugPrint('Stack: $stack');
      }
      debugPrint('================');
    }

    // TODO: В production здесь можно отправлять ошибки в crash analytics
  }

  static String getErrorMessage(dynamic error) {
    if (error is ApiClientException) {
      return error.message;
    }

    if (error is PlatformException) {
      return error.message ?? 'Системная ошибка';
    }

    // Generic fallback
    return 'Произошла неожиданная ошибка';
  }

  static void handleError(dynamic error, {VoidCallback? onRetry}) {
    final message = getErrorMessage(error);

    // TODO: Показать snackbar или dialog с ошибкой
    debugPrint('Handled error: $message');
  }
}