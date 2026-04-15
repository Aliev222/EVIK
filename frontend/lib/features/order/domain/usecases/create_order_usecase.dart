import '../entities/order.dart';
import '../repositories/order_repository.dart';

class CreateOrderUseCase {
  const CreateOrderUseCase(this._repository);

  final OrderRepository _repository;

  Future<Order> execute(CreateOrderCommand command) {
    return _repository.createOrder(command);
  }
}
