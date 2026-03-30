import 'package:equatable/equatable.dart';

class PlannerState extends Equatable {
  const PlannerState({required this.revision});

  const PlannerState.initial() : revision = 0;

  final int revision;

  PlannerState bump() => PlannerState(revision: revision + 1);

  @override
  List<Object?> get props => [revision];
}
