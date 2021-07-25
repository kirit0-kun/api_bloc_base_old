import 'package:api_bloc_base/src/data/model/remote/base_errors.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

class ResponseEntity extends Equatable {
  final String? message;

  const ResponseEntity(this.message);

  @override
  List<Object?> get props => [this.message];
}

class Success extends ResponseEntity {
  const Success([String? message = '']) : super(message);

  @override
  List<Object?> get props => [...super.props];
}

class Failure extends ResponseEntity {
  final BaseErrors? errors;

  const Failure(String? message, [this.errors]) : super(message);

  @override
  List<Object?> get props => [...super.props, this.errors];
}

class InternetFailure extends Failure {
  final DioError dioError;
  const InternetFailure(String message, this.dioError, [BaseErrors? errors])
      : super(message, errors);

  @override
  List<Object?> get props => [...super.props, this.dioError];
}

class Cancellation extends ResponseEntity {
  const Cancellation() : super(null);

  @override
  List<Object?> get props => [...super.props];
}
