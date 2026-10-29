enum PocStepStatus { notRun, running, passed, denied, failed, unsupported }

class PocStepResult {
  const PocStepResult({
    required this.name,
    required this.status,
    required this.message,
  });

  final String name;
  final PocStepStatus status;
  final String message;
}