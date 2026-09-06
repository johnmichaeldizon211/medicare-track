import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';

class AddMedicationScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final Map<String, dynamic>? medication;

  const AddMedicationScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    this.medication,
  });

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final ResidentService _residentService = ResidentService.instance;
  final TextEditingController _medicineNameController = TextEditingController();
  final TextEditingController _dosageAmountController = TextEditingController();
  static const List<String> _medicineTypes = [
    'Tablet',
    'Capsule',
    'mg',
    'ml',
    'Drops',
  ];
  static const List<String> _frequencies = ['Daily', 'Weekly', 'Custom'];
  static const List<String> _durations = [
    'Ongoing',
    '1 Week',
    '2 Weeks',
    '1 Month',
  ];
  static const List<String> _weekDayLabels = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];
  static const List<String> _intervalUnits = ['days', 'weeks'];

  // State variables
  String _selectedFrequency = 'Daily';
  String _selectedType = 'Tablet';
  String _customIntervalUnit = 'days';
  DateTime _selectedDate = DateTime.now();
  String _selectedDuration = 'Ongoing';
  bool _isSaving = false;
  bool _customUseInterval = true;
  final TextEditingController _customIntervalController = TextEditingController(
    text: '1',
  );
  final List<bool> _selectedWeekDays = List<bool>.filled(7, false);

  // Dynamic List for Multiple Reminder Times
  final List<Map<String, dynamic>> _reminders = [
    {'time': const TimeOfDay(hour: 8, minute: 0), 'meal': 'Before meal'},
  ];

  bool get _isEditing => widget.medication != null;

  @override
  void initState() {
    super.initState();
    _hydrateMedication();
  }

  @override
  void dispose() {
    _medicineNameController.dispose();
    _dosageAmountController.dispose();
    _customIntervalController.dispose();
    super.dispose();
  }

  void _hydrateMedication() {
    final medication = widget.medication;
    if (medication == null) {
      return;
    }

    _medicineNameController.text = (medication['name'] ?? '').toString();
    _hydrateFrequency((medication['frequency'] ?? 'Daily').toString());
    _selectedType = _dropdownValue(
      (medication['type'] ?? 'Tablet').toString(),
      _medicineTypes,
      'Tablet',
    );
    _selectedDuration = _dropdownValue(
      (medication['duration'] ?? 'Ongoing').toString(),
      _durations,
      'Ongoing',
    );

    final dosage = (medication['dosage'] ?? '').toString().trim();
    final typeSuffix = ' $_selectedType';
    _dosageAmountController.text =
        dosage.endsWith(typeSuffix) && dosage.length > typeSuffix.length
        ? dosage.substring(0, dosage.length - typeSuffix.length)
        : dosage.split(' ').first;

    _selectedDate =
        DateTime.tryParse(
          (medication['startDate'] ?? '').toString(),
        )?.toLocal() ??
        DateTime.now();

    final reminderList = mapListFrom(medication['reminders']);
    if (reminderList.isNotEmpty) {
      _reminders
        ..clear()
        ..addAll(
          reminderList.map((reminder) {
            return {
              'time':
                  _parseTimeOfDay((reminder['time'] ?? '').toString()) ??
                  const TimeOfDay(hour: 8, minute: 0),
              'meal': (reminder['meal'] ?? 'Before meal').toString(),
            };
          }),
        );
    }
  }

  String _dropdownValue(String value, List<String> options, String fallback) {
    return options.contains(value) ? value : fallback;
  }

  void _hydrateFrequency(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('Weekly')) {
      _selectedFrequency = 'Weekly';
      _hydrateWeekDays(trimmed);
      return;
    }

    if (trimmed.startsWith('Custom')) {
      _selectedFrequency = 'Custom';
      _hydrateCustomFrequency(trimmed);
      return;
    }

    _selectedFrequency = _dropdownValue(trimmed, _frequencies, 'Daily');
  }

  void _hydrateWeekDays(String value) {
    final separatorIndex = value.indexOf(':');
    if (separatorIndex == -1) {
      return;
    }

    final selectedDays = value
        .substring(separatorIndex + 1)
        .split(',')
        .map((day) => day.trim())
        .where((day) => day.isNotEmpty)
        .toSet();

    for (var i = 0; i < _weekDayLabels.length; i++) {
      _selectedWeekDays[i] = selectedDays.contains(_weekDayLabels[i]);
    }
  }

  void _hydrateCustomFrequency(String value) {
    final lowerValue = value.toLowerCase();
    if (lowerValue.contains('every')) {
      _customUseInterval = true;
      final match = RegExp(
        r'every\s+(\d+)\s+(day|days|week|weeks)',
        caseSensitive: false,
      ).firstMatch(value);
      if (match != null) {
        _customIntervalController.text = match.group(1) ?? '1';
        final unit = match.group(2)?.toLowerCase() ?? 'days';
        _customIntervalUnit = unit.startsWith('week') ? 'weeks' : 'days';
      }
      return;
    }

    _customUseInterval = false;
    _hydrateWeekDays(value);
  }

  List<String> get _selectedWeekDayLabels {
    final labels = <String>[];
    for (var i = 0; i < _weekDayLabels.length; i++) {
      if (_selectedWeekDays[i]) {
        labels.add(_weekDayLabels[i]);
      }
    }
    return labels;
  }

  String _frequencyConfigLabel() {
    if (_selectedFrequency == 'Weekly') {
      final days = _selectedWeekDayLabels;
      return days.isEmpty ? 'Weekly' : 'Weekly: ${days.join(', ')}';
    }

    if (_selectedFrequency == 'Custom') {
      if (_customUseInterval) {
        final interval = int.tryParse(_customIntervalController.text.trim());
        final safeInterval = interval == null || interval <= 0 ? 1 : interval;
        final unit = safeInterval == 1
            ? _customIntervalUnit.replaceFirst(RegExp(r's$'), '')
            : _customIntervalUnit;
        return 'Custom: every $safeInterval $unit';
      }

      final days = _selectedWeekDayLabels;
      return days.isEmpty ? 'Custom' : 'Custom: ${days.join(', ')}';
    }

    return _selectedFrequency;
  }

  bool _validateFrequencyConfig() {
    if (_selectedFrequency == 'Weekly' && _selectedWeekDayLabels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one repeat day.')),
      );
      return false;
    }

    if (_selectedFrequency == 'Custom') {
      if (_customUseInterval) {
        final interval = int.tryParse(_customIntervalController.text.trim());
        if (interval == null || interval <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a valid interval.')),
          );
          return false;
        }
      } else if (_selectedWeekDayLabels.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one custom repeat day.'),
          ),
        );
        return false;
      }
    }

    return true;
  }

  TimeOfDay? _parseTimeOfDay(String value) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) {
      return null;
    }

    final hourRaw = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hourRaw == null || minute == null || minute > 59) {
      return null;
    }

    var hour = hourRaw;
    final modifier = match.group(3)?.toUpperCase();
    if (modifier == 'PM' && hour < 12) {
      hour += 12;
    } else if (modifier == 'AM' && hour == 12) {
      hour = 0;
    }

    if (hour < 0 || hour > 23) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  // Function to add a new time slot
  void _addReminderTime() {
    setState(() {
      _reminders.add({
        'time': const TimeOfDay(hour: 12, minute: 0),
        'meal': 'After meal',
      });
    });
  }

  // Function to remove a time slot
  void _removeReminderTime(int index) {
    if (_reminders.length > 1) {
      setState(() {
        _reminders.removeAt(index);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must have at least one reminder time.'),
          backgroundColor: Color(0xFFFFA726),
        ),
      );
    }
  }

  // Function to pick time for a specific slot
  Future<void> _selectTime(BuildContext context, int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _reminders[index]['time'],
    );
    if (picked != null) {
      setState(() {
        _reminders[index]['time'] = picked;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: _selectedDate.isBefore(DateTime.now())
          ? _selectedDate
          : DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String _formatReminderTime(TimeOfDay time) {
    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  Future<void> _saveMedication() async {
    final name = _medicineNameController.text.trim();
    final dosageAmount = _dosageAmountController.text.trim();

    if (name.isEmpty || dosageAmount.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter medicine name and dosage.'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    if (!_validateFrequencyConfig()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final reminders = _reminders.map((reminder) {
        return {
          'time': _formatReminderTime(reminder['time'] as TimeOfDay),
          'meal': reminder['meal'].toString(),
        };
      }).toList();
      final startDate = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final frequency = _frequencyConfigLabel();

      if (_isEditing) {
        await _residentService.updateMedication(
          medicationId: (widget.medication?['id'] ?? '').toString(),
          name: name,
          dosage: '$dosageAmount $_selectedType',
          type: _selectedType,
          frequency: frequency,
          startDate: startDate,
          duration: _selectedDuration,
          reminders: reminders,
        );
      } else {
        await _residentService.createMedication(
          residentId: widget.residentId,
          name: name,
          dosage: '$dosageAmount $_selectedType',
          type: _selectedType,
          frequency: frequency,
          startDate: startDate,
          duration: _selectedDuration,
          reminders: reminders,
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Medication updated successfully!'
                : 'Medication successfully scheduled!',
          ),
          backgroundColor: Color(0xFF00C853),
        ),
      );
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Failed to update medication.'
                : 'Failed to schedule medication.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWebDesktop = screenWidth > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              _isEditing ? "Edit Medicine" : "Add Medicine",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.residentName,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWebDesktop ? 24 : 20,
            vertical: 20,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(isWebDesktop ? 30 : 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("Medicine Name*"),
                      _buildTextField(
                        "e.g. Paracetamol",
                        controller: _medicineNameController,
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 20),

                      _buildLabel("Dosage*"),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              "Amount",
                              controller: _dosageAmountController,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedType,
                                  isExpanded: true,
                                  items: _medicineTypes
                                      .map(
                                        (String value) =>
                                            DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(value),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: (newValue) =>
                                      setState(() => _selectedType = newValue!),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _buildLabel("Frequency*"),
                      _buildFrequencySelector(),
                      const SizedBox(height: 25),
                      const Divider(color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 15),

                      _buildLabel("Reminder Times*"),

                      // --- DYNAMIC LIST OF REMINDER TIMES ---
                      ...List.generate(_reminders.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: Row(
                            children: [
                              // Time Picker
                              Expanded(
                                flex: 4,
                                child: GestureDetector(
                                  onTap: () => _selectTime(context, index),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.access_time,
                                          color: Color(0xFF9575CD),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _reminders[index]['time'].format(
                                            context,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Meal Dropdown
                              Expanded(
                                flex: 5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _reminders[index]['meal'],
                                      isExpanded: true,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                      items:
                                          [
                                            'Before meal',
                                            'After meal',
                                            'With meal',
                                            'Anytime',
                                          ].map((String value) {
                                            return DropdownMenuItem<String>(
                                              value: value,
                                              child: Text(value),
                                            );
                                          }).toList(),
                                      onChanged: (newValue) => setState(
                                        () => _reminders[index]['meal'] =
                                            newValue!,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Delete Button (only show if there is more than 1)
                              if (_reminders.length > 1) ...[
                                const SizedBox(width: 5),
                                IconButton(
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Color(0xFFE53935),
                                  ),
                                  onPressed: () => _removeReminderTime(index),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),

                      // Add Another Time Button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _addReminderTime,
                          icon: const Icon(
                            Icons.add,
                            color: Color(0xFFFFA726),
                            size: 18,
                          ),
                          label: const Text(
                            "Add Another Time",
                            style: TextStyle(
                              color: Color(0xFFFFA726),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(
                                color: Color(0xFFFFA726),
                                style: BorderStyle.solid,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),
                      const Divider(color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 20),

                      // Date and Duration
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel("Start Date"),
                                GestureDetector(
                                  onTap: () => _selectDate(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_today,
                                          color: Color(0xFF9575CD),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "${_selectedDate.month}/${_selectedDate.day}/${_selectedDate.year}",
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel("Duration"),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedDuration,
                                      isExpanded: true,
                                      items: _durations.map((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(
                                            value,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (newValue) => setState(
                                        () => _selectedDuration = newValue!,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // 3. Bottom Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: Color(0xFFFFA726)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            color: Color(0xFFFFA726),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveMedication,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          _isSaving
                              ? "Saving..."
                              : _isEditing
                              ? "Save Changes"
                              : "Save Medicine",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  Widget _buildTextField(
    String hint, {
    TextEditingController? controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: Color(0xFF00BFA5)),
        ),
      ),
    );
  }

  Widget _buildFrequencySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedFrequency,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
          items: _frequencies.map((frequency) {
            return DropdownMenuItem(
              value: frequency,
              child: Text(frequency, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: _isSaving
              ? null
              : (value) {
                  if (value != null) {
                    setState(() => _selectedFrequency = value);
                  }
                },
        ),
        const SizedBox(height: 12),
        if (_selectedFrequency == 'Weekly') ...[
          const Text(
            'Repeat on',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildWeekdayChips(),
        ] else if (_selectedFrequency == 'Custom') ...[
          _buildCustomFrequencyOptions(),
        ],
      ],
    );
  }

  Widget _buildCustomFrequencyOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Repeat interval'),
              selected: _customUseInterval,
              onSelected: _isSaving
                  ? null
                  : (_) => setState(() => _customUseInterval = true),
            ),
            ChoiceChip(
              label: const Text('Specific days'),
              selected: !_customUseInterval,
              onSelected: _isSaving
                  ? null
                  : (_) => setState(() => _customUseInterval = false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_customUseInterval)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              const Text(
                'Every',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              SizedBox(
                width: 82,
                child: TextField(
                  controller: _customIntervalController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'X',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 128,
                child: DropdownButtonFormField<String>(
                  initialValue: _customIntervalUnit,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _intervalUnits.map((unit) {
                    return DropdownMenuItem(value: unit, child: Text(unit));
                  }).toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _customIntervalUnit = value);
                          }
                        },
                ),
              ),
            ],
          )
        else ...[
          const Text(
            'Repeat on',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildWeekdayChips(),
        ],
      ],
    );
  }

  Widget _buildWeekdayChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(_weekDayLabels.length, (index) {
        return FilterChip(
          label: Text(_weekDayLabels[index]),
          selected: _selectedWeekDays[index],
          onSelected: _isSaving
              ? null
              : (selected) {
                  setState(() => _selectedWeekDays[index] = selected);
                },
        );
      }),
    );
  }
}
