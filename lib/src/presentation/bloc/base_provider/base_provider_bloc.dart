import 'dart:async';

import 'package:api_bloc_base/src/data/repository/base_repository.dart';
import 'package:api_bloc_base/src/domain/entity/response_entity.dart';
import 'package:async/async.dart' as async;
import 'package:dartz/dartz.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

import 'lifecycle_observer.dart';
import 'provider_state.dart';

export 'provider_state.dart';

class BaseBloc extends Cubit<int> {
  BaseBloc() : super(0);
}

abstract class BaseProviderBloc<Data> extends Cubit<ProviderState<Data>>
    implements LifecycleAware {
  final Duration? refreshInterval = Duration(seconds: 30);
  final LifecycleObserver? observer;
  final BehaviorSubject<Data?> _dataSubject = BehaviorSubject<Data?>();
  final _stateSubject = BehaviorSubject<ProviderState<Data>>();
  var _dataFuture = Completer<Data?>();
  var _stateFuture = Completer<ProviderState<Data>>();

  StreamSubscription<Data>? _subscription;
  bool green = false;
  bool shouldBeGreen = false;

  String get defaultError => 'Error';

  Timer? _retrialTimer;
  Stream<Data?> get dataStream =>
      async.LazyStream(() => _dataSubject.shareValue());
  Stream<ProviderState<Data>> get stateStream =>
      async.LazyStream(() => _stateSubject.shareValue());
  Future<Data?> get dataFuture => _dataFuture.future;
  Future<ProviderState<Data>> get stateFuture => _stateFuture.future;

  Data? get latestData => _dataSubject.value;

  Result<Either<ResponseEntity, Data>>? get dataSource => null;
  Either<ResponseEntity, Stream<Data>>? get dataSourceStream => null;

  BaseProviderBloc(
      {Data? initialDate,
      bool enableRetry = true,
      bool enableRefresh = true,
      bool getOnCreate = true,
      this.observer})
      : super(ProviderLoadingState()) {
    observer?.addListener(this);
    if (initialDate != null) {
      emit(ProviderLoadedState(initialDate));
    }
    _setUpListener(enableRetry, enableRefresh);
    if (getOnCreate) {
      startTries();
    }
  }

  void startTries([bool userLogStateEvent = true]) {
    green = true;
    shouldBeGreen = userLogStateEvent || shouldBeGreen;
    if (userLogStateEvent) {
      _subscription?.cancel();
      _subscription = null;
    } else {
      _subscription?.resume();
    }
    getData();
  }

  void stopRetries([bool userLogStateEvent = true]) {
    green = false;
    shouldBeGreen = !userLogStateEvent && shouldBeGreen;
    _retrialTimer?.cancel();
    _subscription?.pause();
    emitLoading();
  }

  @override
  void onResume() {
    startTries(false);
  }

  @override
  void onPause() {
    stopRetries(false);
  }

  @override
  void onDetach() {}

  @override
  void onInactive() {}

  void _setUpListener(bool enableRetry, bool enableRefresh) {
    stream.listen((state) {
      if (state is InvalidatedState) {
        getData();
      } else {
        _handleState(state);
      }
      if (refreshInterval != null) {
        if (state is ProviderErrorState && enableRetry) {
          _retrialTimer?.cancel();
          _retrialTimer = Timer(refreshInterval!, getData);
        } else if (state is ProviderLoadedState && enableRefresh) {
          _retrialTimer?.cancel();
          _retrialTimer = Timer.periodic(refreshInterval!, (_) => refresh());
        }
      }
    }, onError: (e, s) {
      print(e);
      print(s);
    });
  }

  void _handleState(state) {
    Data data;
    if (state is ProviderLoadedState) {
      data = state.data;
      _retrialTimer?.cancel();
      _dataSubject.add(data);
      if (_dataFuture.isCompleted) {
        _dataFuture = Completer<Data>();
      }
      _dataFuture.complete(data);
    }
    _stateSubject.add(state);
    if (_stateFuture.isCompleted) {
      _stateFuture = Completer<ProviderState<Data>>();
    }
    _stateFuture.complete(state);
  }

  Future<Data?> handleOperation(
      Result<Either<ResponseEntity, Data>> result, bool refresh) async {
    if (!refresh) {
      emitLoading();
    }
    final future = await result.resultFuture!;
    return future.fold<Data?>(
      (l) {
        emitErrorState(l.message, !refresh);
        return null;
      },
      (r) {
        emit(ProviderLoadedState(r));
        return r;
      },
    );
  }

  Future<void> handleStream(
      Either<ResponseEntity, Stream<Data>> result, bool refresh) async {
    result.fold(
      (l) {
        emitErrorState(l.message, !refresh);
      },
      (r) {
        _subscription?.cancel();
        _subscription = r.doOnEach((notification) {
          if (!refresh) {
            emitLoading();
          }
        }).listen((event) {
          emit(ProviderLoadedState(event));
        }, onError: (e, s) {
          print(e);
          print(s);
          emitErrorState(defaultError, !refresh);
        });
      },
    );
  }

  void interceptOperation<S>(Result<Either<ResponseEntity, S>> result,
      {void onSuccess()?, void onFailure()?, void onDate(S data)?}) {
    result.resultFuture!.then((value) {
      value.fold((l) {
        if (l is Success) {
          onSuccess?.call();
        } else if (l is Failure) {
          onFailure?.call();
        }
      }, (r) {
        if (onDate != null) {
          onDate(r);
        } else if (onSuccess != null) {
          onSuccess();
        }
      });
    });
  }

  void interceptResponse(Result<ResponseEntity> result,
      {void onSuccess()?, void onFailure()?}) {
    result.resultFuture!.then((value) {
      if (value is Success) {
        onSuccess?.call();
      } else if (value is Failure) {
        onFailure?.call();
      }
    });
  }

  void clean() {
    _dataSubject.value = null;
    _dataFuture = Completer();
  }

  @mustCallSuper
  Future<Data?> getData({bool refresh = false}) async {
    if (!refresh) clean();
    final Result<Either<ResponseEntity, Data>>? dataSource = this.dataSource;
    final Either<ResponseEntity, Stream<Data>>? dataSourceStream =
        this.dataSourceStream;
    if (green && shouldBeGreen) {
      if (dataSource != null) {
        return handleOperation(dataSource, refresh);
      } else if (dataSourceStream != null && _subscription == null) {
        await handleStream(dataSourceStream, refresh);
        return null;
      }
    }
    return null;
  }

  void invalidate() {
    emit(InvalidatedState<Data>());
  }

  Future<Data?> refresh() {
    return getData(refresh: true);
  }

  void emitLoading() {
    emit(ProviderLoadingState<Data>());
  }

  void emitErrorState(String? message, bool clean) {
    if (clean) this.clean();
    emit(ProviderErrorState<Data>(message));
  }

  Stream<ProviderState<Out>> transformStream<Out>(
      {Out? outData, Stream<Out>? outStream}) {
    return stateStream.flatMap<ProviderState<Out>>((value) {
      if (value is ProviderLoadingState<Data>) {
        return Stream.value(ProviderLoadingState<Out>());
      } else if (value is ProviderErrorState<Data>) {
        return Stream.value(ProviderErrorState<Out>(value.message));
      } else if (value is InvalidatedState<Data>) {
        return Stream.value(InvalidatedState<Out>());
      } else {
        if (outData != null) {
          return Stream.value(ProviderLoadedState<Out>(outData));
        } else if (outStream != null) {
          return outStream.map((event) => ProviderLoadedState<Out>(event));
        }
        return Stream.empty();
      }
    }).asBroadcastStream(onCancel: ((sub) => sub.cancel()));
  }

  @override
  Future<void> close() {
    observer?.removeListener(this);
    _subscription?.cancel();
    _dataSubject.drain().then((value) => _dataSubject.close());
    _stateSubject.drain().then((value) => _stateSubject.close());
    _retrialTimer?.cancel();
    return super.close();
  }
}
