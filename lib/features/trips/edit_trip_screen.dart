import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../network/api_exception.dart';
import '../../trips/trip.dart';

/// Edit form for an existing trip's title/description/dates/currency — the
/// "Edit trip metadata" slice of issue #3, alongside archive/delete (see
/// [TripDashboardScreen]'s app bar menu).
///
/// Per docs/offline-first.md, saving applies the edit to the local cache
/// immediately via [TripsRepository.editTrip] — it only fails/blocks on a
/// genuine server rejection, not on being offline, in which case the trip
/// stays updated locally and is retried by the next background refresh.
class EditTripScreen extends ConsumerStatefulWidget {
  const EditTripScreen({super.key, required this.trip});

  final Trip trip;

  @override
  ConsumerState<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends ConsumerState<EditTripScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.trip.title);
  late final _descriptionController = TextEditingController(
    text: widget.trip.description ?? '',
  );
  late final _currencyController = TextEditingController(
    text: widget.trip.currency ?? '',
  );

  late DateTime? _startDate = widget.trip.startDate;
  late DateTime? _endDate = widget.trip.endDate;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final id = widget.trip.id;
    if (id == null) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final trip = await ref
          .read(tripsRepositoryProvider)
          .editTrip(
            id: id,
            title: _titleController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
            startDate: _startDate,
            endDate: _endDate,
            currency: _currencyController.text.trim().isEmpty
                ? null
                : _currencyController.text.trim(),
          );

      if (!mounted) return;
      context.pop(trip);
      AppMessenger.showSuccess(
        trip.hasPendingEdit
            ? '"${trip.title}" saved — will sync once you\'re back online.'
            : '"${trip.title}" updated.',
      );
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit trip')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'A title is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description — optional',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start date',
                        date: _startDate,
                        onTap: () => _pickDate(isStart: true),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _DateField(
                        label: 'End date',
                        date: _endDate,
                        onTap: () => _pickDate(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _currencyController,
                  decoration: const InputDecoration(
                    labelText: 'Currency — optional',
                    hintText: 'USD',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(date == null ? 'Not set' : _format(date!)),
      ),
    );
  }

  static String _format(DateTime d) => '${d.month}/${d.day}/${d.year}';
}
