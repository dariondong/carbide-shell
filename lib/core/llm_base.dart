import 'models.dart';

/// Cancel flag shared by the UI and the loop.
class CancelToken {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

/// Raised when a model call cannot be completed.
class LlmException implements Exception {
  LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Narrow seam so the loop can be tested without a network.
abstract class LlmProvider {
  String get label;

  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
  });
}
