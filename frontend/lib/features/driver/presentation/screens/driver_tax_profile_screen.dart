import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tow_truck_frontend/shared/widgets/evik_button.dart';
import 'package:tow_truck_frontend/features/auth/presentation/providers/auth_provider.dart';
import 'package:tow_truck_frontend/features/driver/presentation/providers/driver_tax_profile_provider.dart';

class DriverTaxProfileScreen extends ConsumerStatefulWidget {
  const DriverTaxProfileScreen({super.key});

  @override
  ConsumerState<DriverTaxProfileScreen> createState() =>
      _DriverTaxProfileScreenState();
}

class _DriverTaxProfileScreenState
    extends ConsumerState<DriverTaxProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _innController = TextEditingController();
  String _selectedTaxpayerType = 'self_employed';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingProfile();
    });
  }

  void _loadExistingProfile() {
    final userId = ref.read(authProvider).user?.id;
    if (userId != null) {
      ref.read(driverTaxProfileProvider(userId).future).then((profile) {
        if (profile != null && mounted) {
          setState(() {
            _innController.text = profile.inn;
            _selectedTaxpayerType = profile.taxpayerType;
          });
        }
      }).catchError((_) {
        // Profile doesn't exist yet, that's fine
      });
    }
  }

  @override
  void dispose() {
    _innController.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      _showError('Пользователь не авторизован');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repository = ref.read(driverTaxProfileRepositoryProvider);
      await repository.upsert(
        driverId: userId,
        inn: _innController.text.trim(),
        taxpayerType: _selectedTaxpayerType,
      );

      if (mounted) {
        // Invalidate the provider to refresh the data
        ref.invalidate(driverTaxProfileProvider(userId));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Налоговый профиль сохранен'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Ошибка сохранения профиля: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authProvider).user?.id;
    final taxProfileAsync = userId != null
        ? ref.watch(driverTaxProfileProvider(userId))
        : const AsyncValue.data(null);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Налоговый профиль',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: taxProfileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                'Ошибка загрузки данных',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ошибка загрузки профиля. Попробуйте позже.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  if (userId != null) {
                    ref.invalidate(driverTaxProfileProvider(userId));
                  }
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        data: (profile) => _buildForm(context, profile),
      ),
    );
  }

  Widget _buildForm(BuildContext context, DriverTaxProfile? profile) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (profile != null) ...[
              _buildStatusCard(profile),
              const SizedBox(height: 24),
            ],
            _buildInfoCard(),
            const SizedBox(height: 24),
            _buildFormCard(),
            const SizedBox(height: 24),
            _buildSubmitButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(DriverTaxProfile profile) {
    final statusColor = _getStatusColor(profile.verificationStatus);
    final statusText = _getStatusText(profile.verificationStatus);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(profile.verificationStatus),
            color: statusColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Статус верификации',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[600], size: 20),
              const SizedBox(width: 8),
              Text(
                'Информация',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Для работы водителем необходимо указать налоговую информацию. '
            'Выберите подходящий налоговый режим и укажите ИНН.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Налоговый режим',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildTaxpayerTypeSelector(),
          const SizedBox(height: 24),
          const Text(
            'ИНН',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildInnField(),
        ],
      ),
    );
  }

  Widget _buildTaxpayerTypeSelector() {
    return Column(
      children: [
        _buildTaxpayerOption(
          'self_employed',
          'Самозанятый',
          'НПД (Налог на профессиональный доход)',
        ),
        const SizedBox(height: 12),
        _buildTaxpayerOption(
          'ip',
          'Индивидуальный предприниматель',
          'ИП с любой налоговой системой',
        ),
      ],
    );
  }

  Widget _buildTaxpayerOption(String value, String title, String subtitle) {
    final isSelected = _selectedTaxpayerType == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTaxpayerType = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blue[300]! : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? Colors.blue[600] : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.blue[800] : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInnField() {
    return TextFormField(
      controller: _innController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(12),
      ],
      decoration: InputDecoration(
        hintText: 'Введите ИНН (10 или 12 цифр)',
        prefixIcon: const Icon(Icons.business),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.blue),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'ИНН обязателен';
        }
        final cleaned = value.trim();
        if (cleaned.length != 10 && cleaned.length != 12) {
          return 'ИНН должен содержать 10 или 12 цифр';
        }
        return null;
      },
    );
  }

  Widget _buildSubmitButton() {
    return EvikButton(
      text: 'Сохранить профиль',
      onPressed: _isLoading ? null : _submitProfile,
      isLoading: _isLoading,
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'rejected':
      case 'changes_requested':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'verified':
        return 'Подтвержден';
      case 'rejected':
        return 'Отклонен';
      case 'changes_requested':
        return 'Требуются изменения';
      case 'pending':
        return 'На проверке';
      default:
        return 'Не отправлен';
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'verified':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'changes_requested':
        return Icons.edit;
      case 'pending':
        return Icons.schedule;
      default:
        return Icons.radio_button_unchecked;
    }
  }
}
