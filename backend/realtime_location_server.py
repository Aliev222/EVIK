#!/usr/bin/env python3
"""
Real-time Location Server for EVIK
Архитектура как в Uber - WebSocket сервер для GPS координат водителей
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, Set, Optional, List
import websockets
from websockets.server import WebSocketServerProtocol
from dataclasses import dataclass, asdict
from threading import Lock
import math

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class DriverLocation:
    """Местоположение водителя"""
    driver_id: str
    lat: float
    lng: float
    bearing: float  # Направление движения в градусах
    speed: float    # Скорость в км/ч
    status: str     # online, to_pickup, to_destination, offline
    order_id: Optional[str] = None
    last_update: Optional[str] = None

    def __post_init__(self):
        self.last_update = datetime.utcnow().isoformat()

@dataclass
class ClientOrder:
    """Заказ клиента"""
    order_id: str
    client_id: str
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    status: str  # searching, assigned, pickup, delivery, completed
    assigned_driver_id: Optional[str] = None
    created_at: Optional[str] = None

    def __post_init__(self):
        if not self.created_at:
            self.created_at = datetime.utcnow().isoformat()

class RealTimeLocationServer:
    """Real-time сервер для обработки GPS координат как в Uber"""

    def __init__(self):
        # Хранилище активных соединений
        self.driver_connections: Dict[str, WebSocketServerProtocol] = {}
        self.client_connections: Dict[str, WebSocketServerProtocol] = {}
        self.admin_connections: Set[WebSocketServerProtocol] = set()

        # Данные в памяти (в продакшене используй Redis)
        self.driver_locations: Dict[str, DriverLocation] = {}
        self.active_orders: Dict[str, ClientOrder] = {}

        # Thread safety
        self.lock = Lock()

        logger.info("🚀 Real-time Location Server initialized")

    async def register_driver(self, websocket: WebSocketServerProtocol, driver_id: str):
        """Регистрация водителя в системе"""
        with self.lock:
            self.driver_connections[driver_id] = websocket

            # Инициализация позиции водителя если его еще нет
            if driver_id not in self.driver_locations:
                # Начальная позиция в Москве
                self.driver_locations[driver_id] = DriverLocation(
                    driver_id=driver_id,
                    lat=55.7558 + (hash(driver_id) % 100) * 0.001,  # Случайная позиция в Москве
                    lng=37.6173 + (hash(driver_id) % 100) * 0.001,
                    bearing=0.0,
                    speed=0.0,
                    status="online"
                )

        logger.info(f"👨‍💼 Driver {driver_id} connected")

        # Уведомляем админов о новом водителе
        await self.broadcast_to_admins({
            "type": "driver_connected",
            "driver_id": driver_id,
            "location": asdict(self.driver_locations[driver_id])
        })

    async def register_client(self, websocket: WebSocketServerProtocol, client_id: str):
        """Регистрация клиента в системе"""
        with self.lock:
            self.client_connections[client_id] = websocket
        logger.info(f"👤 Client {client_id} connected")

    async def register_admin(self, websocket: WebSocketServerProtocol):
        """Регистрация админ панели"""
        with self.lock:
            self.admin_connections.add(websocket)
        logger.info("🔧 Admin panel connected")

        # Отправляем текущие данные
        await self.send_current_state_to_admin(websocket)

    async def send_current_state_to_admin(self, websocket: WebSocketServerProtocol):
        """Отправляем админу текущее состояние всех водителей"""
        with self.lock:
            locations = [asdict(loc) for loc in self.driver_locations.values()]
            orders = [asdict(order) for order in self.active_orders.values()]

        await websocket.send(json.dumps({
            "type": "initial_state",
            "drivers": locations,
            "orders": orders,
            "timestamp": datetime.utcnow().isoformat()
        }))

    async def update_driver_location(self, driver_id: str, data: dict):
        """Обновление GPS координат водителя"""
        try:
            # Валидация данных
            lat = float(data.get('lat', 0))
            lng = float(data.get('lng', 0))
            bearing = float(data.get('bearing', 0))
            speed = float(data.get('speed', 0))
            status = data.get('status', 'online')
            order_id = data.get('order_id')

            with self.lock:
                # Обновляем позицию водителя
                self.driver_locations[driver_id] = DriverLocation(
                    driver_id=driver_id,
                    lat=lat,
                    lng=lng,
                    bearing=bearing,
                    speed=speed,
                    status=status,
                    order_id=order_id
                )

                # Если водитель выполняет заказ, уведомляем клиента
                if order_id and order_id in self.active_orders:
                    client_id = self.active_orders[order_id].client_id
                    if client_id in self.client_connections:
                        await self.client_connections[client_id].send(json.dumps({
                            "type": "driver_location_update",
                            "driver_id": driver_id,
                            "location": asdict(self.driver_locations[driver_id]),
                            "order_id": order_id
                        }))

            # Уведомляем админов о движении
            await self.broadcast_to_admins({
                "type": "driver_location_update",
                "driver_id": driver_id,
                "location": asdict(self.driver_locations[driver_id])
            })

            logger.debug(f"📍 Driver {driver_id}: {lat:.6f}, {lng:.6f}, speed: {speed} km/h")

        except Exception as e:
            logger.error(f"❌ Error updating driver location: {e}")

    async def create_order(self, client_id: str, data: dict):
        """Создание нового заказа клиентом"""
        try:
            order_id = f"order_{int(time.time())}_{client_id}"

            order = ClientOrder(
                order_id=order_id,
                client_id=client_id,
                pickup_lat=float(data['pickup_lat']),
                pickup_lng=float(data['pickup_lng']),
                dropoff_lat=float(data['dropoff_lat']),
                dropoff_lng=float(data['dropoff_lng']),
                status="searching"
            )

            with self.lock:
                self.active_orders[order_id] = order

            # Ищем ближайшего свободного водителя
            nearest_driver = await self.find_nearest_driver(
                order.pickup_lat, order.pickup_lng
            )

            if nearest_driver:
                # Назначаем заказ водителю
                await self.assign_order_to_driver(order_id, nearest_driver.driver_id)
            else:
                # Уведомляем клиента что водителей нет
                if client_id in self.client_connections:
                    await self.client_connections[client_id].send(json.dumps({
                        "type": "no_drivers_available",
                        "order_id": order_id,
                        "message": "В данный момент нет свободных водителей"
                    }))

            logger.info(f"📋 Order {order_id} created for client {client_id}")

        except Exception as e:
            logger.error(f"❌ Error creating order: {e}")

    async def find_nearest_driver(self, pickup_lat: float, pickup_lng: float) -> Optional[DriverLocation]:
        """Поиск ближайшего свободного водителя"""
        with self.lock:
            available_drivers = [
                driver for driver in self.driver_locations.values()
                if driver.status == "online"
            ]

        if not available_drivers:
            return None

        # Находим ближайшего по расстоянию
        nearest = min(available_drivers, key=lambda d: self.calculate_distance(
            pickup_lat, pickup_lng, d.lat, d.lng
        ))

        # Проверяем что водитель в разумном радиусе (до 10 км)
        distance = self.calculate_distance(pickup_lat, pickup_lng, nearest.lat, nearest.lng)
        if distance <= 10:  # 10 км
            return nearest

        return None

    def calculate_distance(self, lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        """Расчет расстояния между двумя точками в километрах"""
        # Формула гаверсинуса
        R = 6371  # Радиус Земли в км

        lat1_rad = math.radians(lat1)
        lat2_rad = math.radians(lat2)
        delta_lat = math.radians(lat2 - lat1)
        delta_lng = math.radians(lng2 - lng1)

        a = (math.sin(delta_lat / 2) ** 2 +
             math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lng / 2) ** 2)
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

        return R * c

    async def assign_order_to_driver(self, order_id: str, driver_id: str):
        """Назначение заказа водителю"""
        try:
            with self.lock:
                if order_id in self.active_orders and driver_id in self.driver_locations:
                    # Обновляем заказ
                    self.active_orders[order_id].assigned_driver_id = driver_id
                    self.active_orders[order_id].status = "assigned"

                    # Обновляем статус водителя
                    self.driver_locations[driver_id].status = "to_pickup"
                    self.driver_locations[driver_id].order_id = order_id

                    order = self.active_orders[order_id]

            # Уведомляем водителя о новом заказе
            if driver_id in self.driver_connections:
                await self.driver_connections[driver_id].send(json.dumps({
                    "type": "new_order_assigned",
                    "order": asdict(order),
                    "message": "Вам назначен новый заказ!"
                }))

            # Уведомляем клиента что водитель найден
            client_id = order.client_id
            if client_id in self.client_connections:
                await self.client_connections[client_id].send(json.dumps({
                    "type": "driver_found",
                    "order_id": order_id,
                    "driver": asdict(self.driver_locations[driver_id]),
                    "message": "Водитель найден и едет к вам!"
                }))

            # Уведомляем админов
            await self.broadcast_to_admins({
                "type": "order_assigned",
                "order": asdict(order),
                "driver": asdict(self.driver_locations[driver_id])
            })

            logger.info(f"✅ Order {order_id} assigned to driver {driver_id}")

        except Exception as e:
            logger.error(f"❌ Error assigning order: {e}")

    async def broadcast_to_admins(self, message: dict):
        """Отправка сообщения всем админам"""
        if self.admin_connections:
            message_str = json.dumps(message)
            dead_connections = set()

            for connection in self.admin_connections:
                try:
                    await connection.send(message_str)
                except websockets.exceptions.ConnectionClosed:
                    dead_connections.add(connection)
                except Exception as e:
                    logger.error(f"Error sending to admin: {e}")
                    dead_connections.add(connection)

            # Удаляем мертвые соединения
            self.admin_connections -= dead_connections

    async def handle_connection(self, websocket: WebSocketServerProtocol, path: str):
        """Обработка WebSocket соединений"""
        try:
            await websocket.send(json.dumps({
                "type": "connection_established",
                "message": "Connected to EVIK Real-time Server",
                "server_time": datetime.utcnow().isoformat()
            }))

            async for raw_message in websocket:
                try:
                    message = json.loads(raw_message)
                    message_type = message.get('type')

                    if message_type == 'register_driver':
                        driver_id = message.get('driver_id')
                        if driver_id:
                            await self.register_driver(websocket, driver_id)

                    elif message_type == 'register_client':
                        client_id = message.get('client_id')
                        if client_id:
                            await self.register_client(websocket, client_id)

                    elif message_type == 'register_admin':
                        await self.register_admin(websocket)

                    elif message_type == 'location_update':
                        driver_id = message.get('driver_id')
                        if driver_id:
                            await self.update_driver_location(driver_id, message.get('data', {}))

                    elif message_type == 'create_order':
                        client_id = message.get('client_id')
                        if client_id:
                            await self.create_order(client_id, message.get('data', {}))

                    else:
                        logger.warning(f"Unknown message type: {message_type}")

                except json.JSONDecodeError:
                    logger.error(f"Invalid JSON received: {raw_message}")
                except Exception as e:
                    logger.error(f"Error handling message: {e}")

        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as e:
            logger.error(f"Connection error: {e}")
        finally:
            # Убираем соединение при отключении
            await self.cleanup_connection(websocket)

    async def cleanup_connection(self, websocket: WebSocketServerProtocol):
        """Очистка при отключении"""
        with self.lock:
            # Удаляем из водителей
            driver_to_remove = None
            for driver_id, connection in self.driver_connections.items():
                if connection == websocket:
                    driver_to_remove = driver_id
                    break

            if driver_to_remove:
                del self.driver_connections[driver_to_remove]
                # Обновляем статус водителя на offline
                if driver_to_remove in self.driver_locations:
                    self.driver_locations[driver_to_remove].status = "offline"
                logger.info(f"👨‍💼 Driver {driver_to_remove} disconnected")

            # Удаляем из клиентов
            client_to_remove = None
            for client_id, connection in self.client_connections.items():
                if connection == websocket:
                    client_to_remove = client_id
                    break

            if client_to_remove:
                del self.client_connections[client_to_remove]
                logger.info(f"👤 Client {client_to_remove} disconnected")

            # Удаляем из админов
            if websocket in self.admin_connections:
                self.admin_connections.remove(websocket)
                logger.info("🔧 Admin panel disconnected")

async def main():
    """Запуск WebSocket сервера"""
    server = RealTimeLocationServer()

    logger.info("🚀 Starting EVIK Real-time Location Server...")
    logger.info("📡 WebSocket server will run on ws://localhost:8765")
    logger.info("🔧 Admin panel: ws://localhost:8765")
    logger.info("👨‍💼 Driver apps: ws://localhost:8765")
    logger.info("👤 Client apps: ws://localhost:8765")

    async with websockets.serve(server.handle_connection, "localhost", 8765):
        logger.info("✅ Server is running and ready for connections!")
        await asyncio.Future()  # Бесконечный цикл

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("🛑 Server stopped by user")
    except Exception as e:
        logger.error(f"💥 Server error: {e}")