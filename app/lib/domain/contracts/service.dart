import 'package:app/domain/contracts/disposable.dart';

abstract class Service implements Disposable {
  @override
  void dispose() {}
}
