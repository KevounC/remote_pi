import 'package:app/domain/contracts/disposable.dart';

abstract class Repository implements Disposable {
  @override
  void dispose() {}
}
