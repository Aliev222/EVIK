import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/core/services/realtime_location_service.dart';
import 'package:tow_truck_frontend/core/theme/evik_colors.dart';
import 'package:tow_truck_frontend/core/theme/evik_typography.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/animated_driver_marker.dart';
import 'package:tow_truck_frontend/features/map/presentation/widgets/live_driver_map.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final List<DriverLocationUpdate> _activeDrivers = [];
  final List<OrderUpdate> _recentOrders = [];
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initializeAdminConnection();
  }

  void _initializeAdminConnection() async {
    final realTimeService = ref.read(realTimeLocationServiceProvider);

    final connected =
        await realTimeService.connect(userId: 'admin_panel', userType: 'admin');

    setState(() => _isConnected = connected);

    if (connected) {
      // Listen for driver location updates
      realTimeService.driverLocationStream.listen((driverUpdate) {
        if (!mounted) return;
        setState(() {
          // Update or add driver to the list
          final existingIndex = _activeDrivers
              .indexWhere((d) => d.driverId == driverUpdate.driverId);
          if (existingIndex != -1) {
            _activeDrivers[existingIndex] = driverUpdate;
          } else {
            _activeDrivers.add(driverUpdate);
          }
        });
      });

      // Listen for order updates
      realTimeService.orderUpdateStream.listen((orderUpdate) {
        if (!mounted) return;
        setState(() {
          _recentOrders.insert(0, orderUpdate);
          // Keep only last 10 orders
          if (_recentOrders.length > 10) {
            _recentOrders.removeRange(10, _recentOrders.length);
          }
        });
      });

      // Listen for connection status
      realTimeService.connectionStream.listen((status) {
        if (!mounted) return;
        setState(() {
          _isConnected = status == 'connected';
        });
      });
    }
  }

  @override
  void dispose() {
    ref.read(realTimeLocationServiceProvider).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EvikColors.gray50,
      appBar: AppBar(
        backgroundColor: EvikColors.primaryWhite,
        title: Text(
          'Авро Админ',
          style: EvikTypography.h2.copyWith(color: EvikColors.primaryBlack),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color:
                  _isConnected ? EvikColors.successGreen : EvikColors.errorRed,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: EvikColors.primaryWhite,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? 'ONLINE' : 'OFFLINE',
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.primaryWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          // Left Panel - Statistics
          Expanded(
            flex: 1,
            child: Container(
              color: EvikColors.primaryWhite,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Real-Time Statistics',
                    style: EvikTypography.h3.copyWith(
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildStatCard(
                    'Active Drivers',
                    '${_activeDrivers.length}',
                    Icons.local_shipping,
                    EvikColors.infoBlue,
                  ),
                  const SizedBox(height: 16),
                  _buildStatCard(
                    'Recent Orders',
                    '${_recentOrders.length}',
                    Icons.receipt,
                    EvikColors.accentOrange,
                  ),
                  const SizedBox(height: 16),
                  _buildStatCard(
                    'Online Drivers',
                    '${_activeDrivers.where((d) => d.status != DriverMarkerStatus.toPickup).length}',
                    Icons.check_circle,
                    EvikColors.successGreen,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Recent Orders',
                    style: EvikTypography.h3.copyWith(
                      color: EvikColors.primaryBlack,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _recentOrders.length,
                      itemBuilder: (context, index) {
                        final order = _recentOrders[index];
                        return _buildOrderCard(order);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Panel - Live Map
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: EvikColors.primaryWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LiveDriverMap(
                  pickupLocation:
                      null, // Show all drivers without specific pickup
                  destinationLocation: null,
                  showSearchAnimation: false,
                  showRoute: false,
                  adminMode: true, // Show all active drivers
                  activeDrivers: _activeDrivers,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: EvikColors.primaryWhite, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: EvikTypography.h2.copyWith(
                    color: EvikColors.primaryBlack,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: EvikTypography.bodyMedium.copyWith(
                    color: EvikColors.gray600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(OrderUpdate order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EvikColors.gray50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getOrderStatusColor(order.status),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getOrderStatusText(order.status),
                  style: EvikTypography.bodySmall.copyWith(
                    color: EvikColors.primaryWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                order.orderId,
                style: EvikTypography.bodySmall.copyWith(
                  color: EvikColors.gray600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          if (order.message != null) ...[
            const SizedBox(height: 4),
            Text(
              order.message!,
              style: EvikTypography.bodySmall.copyWith(
                color: EvikColors.primaryBlack,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getOrderStatusColor(OrderUpdateType status) {
    switch (status) {
      case OrderUpdateType.driverFound:
        return EvikColors.successGreen;
      case OrderUpdateType.newOrderAssigned:
        return EvikColors.infoBlue;
      case OrderUpdateType.noDriversAvailable:
        return EvikColors.errorRed;
      case OrderUpdateType.orderCompleted:
        return EvikColors.accentOrange;
    }
  }

  String _getOrderStatusText(OrderUpdateType status) {
    switch (status) {
      case OrderUpdateType.driverFound:
        return 'DRIVER FOUND';
      case OrderUpdateType.newOrderAssigned:
        return 'ASSIGNED';
      case OrderUpdateType.noDriversAvailable:
        return 'NO DRIVERS';
      case OrderUpdateType.orderCompleted:
        return 'COMPLETED';
    }
  }
}
