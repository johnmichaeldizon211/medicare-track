import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class AdminCareTasksScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String assignedCaregiver;

  const AdminCareTasksScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.assignedCaregiver,
  });

  @override
  State<AdminCareTasksScreen> createState() => _AdminCareTasksScreenState();
}

class _AdminCareTasksScreenState extends State<AdminCareTasksScreen> {
  final ResidentService _residentService = ResidentService.instance;
  static const List<String> _taskTypes = [
    'General Care',
    'Meal',
    'Hygiene',
    'Mobility',
    'Vitals',
    'Medication Support',
  ];
  static const List<String> _frequencies = ['Daily', 'Weekly', 'Custom'];
  static const String _customTaskPresetLabel = 'Custom Task';
  static const String _routinePresetLabel = 'Load Standard Daily Care Routine';
  static const List<_RoutineTaskTemplate> _standardDailyRoutine = [
    _RoutineTaskTemplate(
      title: 'Breakfast',
      type: 'General Care',
      scheduledTime: '8:00 AM',
      frequency: 'Daily',
    ),
    _RoutineTaskTemplate(
      title: 'Lunch',
      type: 'General Care',
      scheduledTime: '12:00 PM',
      frequency: 'Daily',
    ),
    _RoutineTaskTemplate(
      title: 'Dinner',
      type: 'General Care',
      scheduledTime: '6:00 PM',
      frequency: 'Daily',
    ),
    _RoutineTaskTemplate(
      title: 'Bathing / Hygiene',
      type: 'General Care',
      scheduledTime: '9:00 AM',
      frequency: 'Daily',
    ),
  ];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _changed = false;
  String? _errorMessage;
  List<_AdminCareTaskItem> _tasks = const [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_isSaving) {
        _loadTasks(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final rawTasks = await _residentService.getResidentCareTasks(
        widget.residentId,
      );
      final tasks = mapListFrom(rawTasks).map((task) {
        final event = asStringMap(task['event']);
        return _AdminCareTaskItem(
          id: (task['id'] ?? '').toString(),
          title: (task['title'] ?? 'Care task').toString(),
          type: (task['type'] ?? 'General').toString(),
          scheduledTime: (task['scheduledTime'] ?? '').toString(),
          frequency: (task['frequency'] ?? 'Daily').toString(),
          status: (event?['status'] ?? 'PENDING').toString(),
          remark: event?['remark']?.toString(),
          updatedAt: DateTime.tryParse(
            (event?['updatedAt'] ?? '').toString(),
          )?.toLocal(),
          timeCompleted: DateTime.tryParse(
            (event?['timeCompleted'] ?? '').toString(),
          )?.toLocal(),
        );
      }).toList();

      tasks.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load care tasks right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _showTaskSheet({_AdminCareTaskItem? task}) async {
    final isEditing = task != null;
    if (task?.isCompleted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completed care tasks cannot be edited.')),
      );
      return;
    }

    final parentMessenger = ScaffoldMessenger.of(context);
    final titleController = TextEditingController(text: task?.title ?? '');
    String selectedType = _dropdownValue(
      task?.type ?? 'General Care',
      _taskTypes,
      'General Care',
    );
    TimeOfDay selectedTime =
        _parseTimeOfDay(task?.scheduledTime ?? '') ?? TimeOfDay.now();
    bool sheetSaving = false;
    bool savedRoutineBundle = false;
    String? selectedPreset;
    List<_RoutineTaskDraft> routineDrafts = [];
    String selectedFrequency = _dropdownValue(
      task?.frequency ?? 'Daily',
      _frequencies,
      'Daily',
    );
    final customIntervalController = TextEditingController(text: '1');
    bool useEveryX = true;
    final selectedWeekDays = List<bool>.filled(7, false);

    void disposeRoutineDrafts() {
      for (final draft in routineDrafts) {
        draft.dispose();
      }
    }

    // Pause the periodic refresh while the sheet is open to avoid
    // concurrent setState calls that can interfere with the sheet UI.
    _refreshTimer?.cancel();

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      // allow tap on the barrier to dismiss, but disable the drag-to-dismiss
      // gesture which was causing the sheet to hang on some devices.
      isDismissible: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final sheetNavigator = Navigator.of(sheetContext);
        final sheetMessenger =
            ScaffoldMessenger.maybeOf(sheetContext) ?? parentMessenger;

        return StatefulBuilder(
          builder: (builderContext, setSheetState) {
            Future<void> pickTime() async {
              final picked = await showTimePicker(
                context: builderContext,
                initialTime: selectedTime,
              );
              if (picked != null) {
                setSheetState(() => selectedTime = picked);
              }
            }

            Future<void> submitTask() async {
              if (!isEditing && routineDrafts.isNotEmpty) {
                final invalidDraft = routineDrafts.any(
                  (draft) => draft.titleController.text.trim().isEmpty,
                );
                if (invalidDraft) {
                  sheetMessenger.showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a title for each task.'),
                    ),
                  );
                  return;
                }

                setSheetState(() => sheetSaving = true);
                if (mounted) {
                  setState(() => _isSaving = true);
                }

                var saved = false;
                try {
                  await _residentService.createCareTasksBatch(
                    residentId: widget.residentId,
                    tasks: routineDrafts
                        .map(
                          (draft) => {
                            'title': draft.titleController.text.trim(),
                            'type': draft.type,
                            'scheduledTime': _formatTimeOfDay(
                              draft.scheduledTime,
                            ),
                            'frequency': draft.frequency,
                          },
                        )
                        .toList(),
                  );
                  saved = true;
                  savedRoutineBundle = true;
                } on ApiException catch (e) {
                  if (sheetMessenger.mounted) {
                    sheetMessenger.showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  }
                } catch (_) {
                  if (sheetMessenger.mounted) {
                    sheetMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Failed to add routine care tasks.'),
                      ),
                    );
                  }
                } finally {
                  if (!saved && builderContext.mounted) {
                    setSheetState(() => sheetSaving = false);
                  }
                  if (mounted) {
                    setState(() => _isSaving = false);
                  }
                  if (saved && sheetNavigator.mounted) {
                    sheetNavigator.pop(true);
                  }
                }
                return;
              }

              final title = titleController.text.trim();
              if (title.isEmpty) {
                sheetMessenger.showSnackBar(
                  const SnackBar(content: Text('Please enter a task title.')),
                );
                return;
              }

              setSheetState(() => sheetSaving = true);
              if (mounted) {
                setState(() => _isSaving = true);
              }

              var saved = false;
              try {
                if (isEditing) {
                  await _residentService.updateCareTask(
                    careTaskId: task.id,
                    title: title,
                    type: selectedType,
                    scheduledTime: _formatTimeOfDay(selectedTime),
                    frequency: selectedFrequency,
                  );
                } else {
                  await _residentService.createCareTask(
                    residentId: widget.residentId,
                    title: title,
                    type: selectedType,
                    scheduledTime: _formatTimeOfDay(selectedTime),
                    frequency: selectedFrequency,
                  );
                }
                saved = true;
                savedRoutineBundle = false;
              } on ApiException catch (e) {
                if (sheetMessenger.mounted) {
                  sheetMessenger.showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                }
              } catch (_) {
                if (sheetMessenger.mounted) {
                  sheetMessenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        isEditing
                            ? 'Failed to update care task.'
                            : 'Failed to add care task.',
                      ),
                    ),
                  );
                }
              } finally {
                if (!saved && builderContext.mounted) {
                  setSheetState(() => sheetSaving = false);
                }
                if (mounted) {
                  setState(() => _isSaving = false);
                }
                if (saved && sheetNavigator.mounted) {
                  sheetNavigator.pop(true);
                }
              }
            }

            void applyPreset(String? presetLabel) {
              if (presetLabel == _customTaskPresetLabel) {
                setSheetState(() {
                  disposeRoutineDrafts();
                  selectedPreset = presetLabel;
                  routineDrafts = [];
                });
                return;
              }

              if (presetLabel != _routinePresetLabel) {
                return;
              }

              setSheetState(() {
                disposeRoutineDrafts();
                selectedPreset = presetLabel;
                routineDrafts = _standardDailyRoutine
                    .map(
                      (template) => _RoutineTaskDraft.fromTemplate(
                        template,
                        parseTime: _parseTimeOfDay,
                      ),
                    )
                    .toList();
              });
            }

            Future<void> pickRoutineTime(int index) async {
              final picked = await showTimePicker(
                context: builderContext,
                initialTime: routineDrafts[index].scheduledTime,
              );
              if (picked != null) {
                setSheetState(
                  () => routineDrafts[index].scheduledTime = picked,
                );
              }
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final mediaQuery = MediaQuery.of(context);
                final viewInsets = mediaQuery.viewInsets;
                final screenWidth = mediaQuery.size.width;
                final isMobile = screenWidth < 600;
                final isDesktop = screenWidth >= 1024;
                final panelWidth = isMobile
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 64)
                          .clamp(480.0, isDesktop ? 620.0 : 560.0)
                          .toDouble();
                final availableHeight =
                    constraints.maxHeight -
                    viewInsets.bottom -
                    (isMobile ? 64 : 72);
                final panelMaxHeight = availableHeight > 280
                    ? availableHeight
                    : constraints.maxHeight * 0.9;
                final panelRadius = isMobile ? 26.0 : 24.0;

                return SizedBox(
                  height: constraints.maxHeight,
                  width: constraints.maxWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: sheetSaving
                        ? null
                        : () => sheetNavigator.maybePop(false),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: isMobile ? 0 : 24,
                        right: isMobile ? 0 : 24,
                        top: isMobile ? 56 : 24,
                        bottom: viewInsets.bottom + (isMobile ? 0 : 24),
                      ),
                      child: Align(
                        alignment: isMobile
                            ? Alignment.bottomCenter
                            : Alignment.center,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: panelWidth,
                              maxHeight: panelMaxHeight,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(panelRadius),
                                bottom: Radius.circular(
                                  isMobile ? 0 : panelRadius,
                                ),
                              ),
                              child: Material(
                                color: Colors.white,
                                child: SingleChildScrollView(
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.fromLTRB(
                                    isMobile ? 20 : 24,
                                    12,
                                    isMobile ? 20 : 24,
                                    20 + mediaQuery.padding.bottom,
                                  ),
                                  child: _buildAddTaskForm(
                                    isEditing: isEditing,
                                    titleController: titleController,
                                    selectedType: selectedType,
                                    selectedPreset: selectedPreset,
                                    selectedTime: selectedTime,
                                    selectedFrequency: selectedFrequency,
                                    routineDrafts: routineDrafts,
                                    customIntervalController:
                                        customIntervalController,
                                    selectedWeekDays: selectedWeekDays,
                                    useEveryX: useEveryX,
                                    isSaving: sheetSaving,
                                    useTwoColumnFields: !isMobile,
                                    onClose: () =>
                                        sheetNavigator.maybePop(false),
                                    onPickTime: pickTime,
                                    onSubmit: submitTask,
                                    onPresetChanged: applyPreset,
                                    onPickRoutineTime: pickRoutineTime,
                                    onRoutineTitleChanged: (index) =>
                                        setSheetState(() {}),
                                    onRoutineTypeChanged: (index, value) {
                                      if (value != null) {
                                        setSheetState(
                                          () =>
                                              routineDrafts[index].type = value,
                                        );
                                      }
                                    },
                                    onRoutineFrequencyChanged: (index, value) {
                                      if (value != null) {
                                        setSheetState(
                                          () => routineDrafts[index].frequency =
                                              value,
                                        );
                                      }
                                    },
                                    onTypeChanged: (value) {
                                      if (value != null) {
                                        setSheetState(
                                          () => selectedType = value,
                                        );
                                      }
                                    },
                                    onFrequencyChanged: (value) {
                                      if (value != null) {
                                        setSheetState(
                                          () => selectedFrequency = value,
                                        );
                                      }
                                    },
                                    onToggleEveryX: (value) =>
                                        setSheetState(() => useEveryX = value),
                                    onToggleWeekDay: (index, value) =>
                                        setSheetState(
                                          () => selectedWeekDays[index] = value,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    // Safely dispose controllers
    titleController.dispose();
    customIntervalController.dispose();
    disposeRoutineDrafts();

    // Restart the periodic refresh after the sheet closes.
    if (mounted) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted && !_isSaving) {
          _loadTasks(showLoading: false);
        }
      });
    }

    // Check if the parent screen is still mounted before executing post-pop code
    if (!mounted) return;

    if (created == true) {
      _changed = true;

      // Schedule the SnackBar and Task Reload AFTER the current frame finish popping
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        parentMessenger.showSnackBar(
          SnackBar(
            content: Text(
              isEditing
                  ? 'Care task updated.'
                  : savedRoutineBundle
                  ? 'Routine care tasks added.'
                  : 'Care task added.',
            ),
          ),
        );
        await _loadTasks();
      });
    }
  }

  Future<void> _confirmDeleteTask(_AdminCareTaskItem task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete care task?'),
        content: Text(
          'Are you sure you want to delete "${task.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSaving = true);
    try {
      await _residentService.deleteCareTask(task.id);
      if (!mounted) {
        return;
      }
      _changed = true;
      messenger.showSnackBar(
        const SnackBar(content: Text('Care task deleted.')),
      );
      await _loadTasks(showLoading: false);
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to delete care task.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildAddTaskForm({
    required bool isEditing,
    required TextEditingController titleController,
    required String selectedType,
    required String? selectedPreset,
    required TimeOfDay selectedTime,
    required String selectedFrequency,
    required List<_RoutineTaskDraft> routineDrafts,
    required TextEditingController customIntervalController,
    required List<bool> selectedWeekDays,
    required bool useEveryX,
    required bool isSaving,
    required bool useTwoColumnFields,
    required VoidCallback onClose,
    required VoidCallback onPickTime,
    required Future<void> Function() onSubmit,
    required ValueChanged<String?> onPresetChanged,
    required ValueChanged<int> onPickRoutineTime,
    required ValueChanged<int> onRoutineTitleChanged,
    required void Function(int index, String? value) onRoutineTypeChanged,
    required void Function(int index, String? value) onRoutineFrequencyChanged,
    required ValueChanged<String?> onTypeChanged,
    required ValueChanged<String?> onFrequencyChanged,
    required ValueChanged<bool> onToggleEveryX,
    required void Function(int index, bool value) onToggleWeekDay,
  }) {
    final isRoutineBundle = !isEditing && routineDrafts.isNotEmpty;
    final presetField = DropdownButtonFormField<String>(
      key: ValueKey('task-preset-$selectedPreset'),
      initialValue: selectedPreset,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Quick Preset / Template',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      hint: const Text('Select a preset'),
      items: const [
        DropdownMenuItem(
          value: _customTaskPresetLabel,
          child: Text(_customTaskPresetLabel, overflow: TextOverflow.ellipsis),
        ),
        DropdownMenuItem(
          value: _routinePresetLabel,
          child: Text(_routinePresetLabel, overflow: TextOverflow.ellipsis),
        ),
      ],
      onChanged: isSaving ? null : onPresetChanged,
    );

    final taskTypeField = DropdownButtonFormField<String>(
      key: ValueKey('task-type-$selectedType'),
      initialValue: selectedType,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Task type',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: _taskTypes
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text(type, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: isSaving ? null : onTypeChanged,
    );

    final scheduledButton = OutlinedButton.icon(
      onPressed: isSaving ? null : onPickTime,
      icon: const Icon(Icons.access_time),
      label: Text(
        'Scheduled: ${_formatTimeOfDay(selectedTime)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final frequencyField = DropdownButtonFormField<String>(
      key: ValueKey('task-frequency-$selectedFrequency'),
      initialValue: selectedFrequency,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Frequency',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: _frequencies
          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
          .toList(),
      onChanged: isSaving ? null : onFrequencyChanged,
    );

    Widget buildWeekdayChips() {
      const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      return Wrap(
        spacing: 6,
        children: List.generate(days.length, (i) {
          return FilterChip(
            label: Text(days[i]),
            selected: selectedWeekDays[i],
            onSelected: isSaving ? null : (v) => onToggleWeekDay(i, v),
          );
        }),
      );
    }

    Widget buildRoutineDraftCard(int index, _RoutineTaskDraft draft) {
      final typeField = DropdownButtonFormField<String>(
        key: ValueKey('routine-type-$index-${draft.type}'),
        initialValue: draft.type,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Task type',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _taskTypes
            .map(
              (type) => DropdownMenuItem(
                value: type,
                child: Text(type, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: isSaving
            ? null
            : (value) => onRoutineTypeChanged(index, value),
      );

      final timeButton = OutlinedButton.icon(
        onPressed: isSaving ? null : () => onPickRoutineTime(index),
        icon: const Icon(Icons.access_time),
        label: Text(
          _formatTimeOfDay(draft.scheduledTime),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      final frequencyField = DropdownButtonFormField<String>(
        key: ValueKey('routine-frequency-$index-${draft.frequency}'),
        initialValue: draft.frequency,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Frequency',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _frequencies
            .map((f) => DropdownMenuItem(value: f, child: Text(f)))
            .toList(),
        onChanged: isSaving
            ? null
            : (value) => onRoutineFrequencyChanged(index, value),
      );

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF00796B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: draft.titleController,
                    enabled: !isSaving,
                    onChanged: (_) => onRoutineTitleChanged(index),
                    decoration: InputDecoration(
                      labelText: 'Task title',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (useTwoColumnFields) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: typeField),
                  const SizedBox(width: 12),
                  Expanded(child: timeButton),
                ],
              ),
              const SizedBox(height: 12),
              frequencyField,
            ] else ...[
              typeField,
              const SizedBox(height: 12),
              timeButton,
              const SizedBox(height: 12),
              frequencyField,
            ],
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                isEditing ? 'Edit Care Task' : 'Add Care Task',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: isSaving ? null : onClose,
              icon: const Icon(Icons.close),
              tooltip: 'Close',
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (!isEditing) ...[presetField, const SizedBox(height: 14)],
        if (isRoutineBundle) ...[
          ...List.generate(
            routineDrafts.length,
            (index) => Padding(
              padding: EdgeInsets.only(
                bottom: index == routineDrafts.length - 1 ? 0 : 12,
              ),
              child: buildRoutineDraftCard(index, routineDrafts[index]),
            ),
          ),
        ] else ...[
          TextField(
            controller: titleController,
            enabled: !isSaving,
            decoration: InputDecoration(
              labelText: 'Task title',
              hintText: 'Example: Morning bathing',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (useTwoColumnFields)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: taskTypeField),
                const SizedBox(width: 12),
                Expanded(child: scheduledButton),
              ],
            )
          else ...[
            taskTypeField,
            const SizedBox(height: 14),
            scheduledButton,
          ],
          const SizedBox(height: 14),
          frequencyField,
          const SizedBox(height: 12),
          if (selectedFrequency == 'Weekly') ...[
            const Text(
              'Repeat on',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            buildWeekdayChips(),
          ] else if (selectedFrequency == 'Custom') ...[
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Every X days'),
                        selected: useEveryX,
                        onSelected: isSaving
                            ? null
                            : (selected) => onToggleEveryX(selected),
                      ),
                      ChoiceChip(
                        label: const Text('Specific days'),
                        selected: !useEveryX,
                        onSelected: isSaving
                            ? null
                            : (selected) => onToggleEveryX(!selected),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (useEveryX) ...[
              Row(
                children: [
                  const Text(
                    'Every',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: customIntervalController,
                      enabled: !isSaving,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'X',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('days'),
                ],
              ),
            ] else ...[
              const Text(
                'Repeat on',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              buildWeekdayChips(),
            ],
          ],
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isSaving ? null : onSubmit,
            icon: Icon(
              isEditing
                  ? Icons.edit_outlined
                  : isRoutineBundle
                  ? Icons.playlist_add
                  : Icons.add,
            ),
            label: Text(
              isSaving
                  ? 'Saving...'
                  : isEditing
                  ? 'Save Changes'
                  : isRoutineBundle
                  ? 'Save ${routineDrafts.length} Tasks'
                  : 'Add Task',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  static TimeOfDay? _parseTimeOfDay(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?:\s*(AM|PM))?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
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

  static String _dropdownValue(
    String value,
    List<String> options,
    String fallback,
  ) {
    return options.contains(value) ? value : fallback;
  }

  static String _initial(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == 'Unassigned'
        ? '?'
        : trimmed.substring(0, 1).toUpperCase();
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '';
    }
    final hour = value.hour > 12
        ? value.hour - 12
        : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':
        return 'Completed';
      case 'SKIPPED':
        return 'Skipped';
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':
        return const Color(0xFF00C853);
      case 'SKIPPED':
        return const Color(0xFFE53935);
      default:
        return const Color(0xFFFFA726);
    }
  }

  IconData _taskIcon(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('meal')) {
      return Icons.restaurant;
    }
    if (normalized.contains('hygiene')) {
      return Icons.clean_hands;
    }
    if (normalized.contains('mobility')) {
      return Icons.directions_walk;
    }
    if (normalized.contains('vitals')) {
      return Icons.monitor_heart_outlined;
    }
    if (normalized.contains('medication')) {
      return Icons.medication_outlined;
    }
    return Icons.assignment_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final done = _tasks.where((task) => task.status.toUpperCase() == 'DONE');
    final completedCount = done.length;
    final totalCount = _tasks.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () =>
              Navigator.pop(context, _changed ? _tasks.length : null),
        ),
        title: Column(
          children: [
            const Text(
              "Care Tasks",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.residentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _showTaskSheet(),
            icon: const Icon(Icons.add_circle_outline),
            color: const Color(0xFF00BFA5),
            tooltip: 'Add care task',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontalPadding = width < 360
                ? 14.0
                : width < 700
                ? 20.0
                : 32.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: width < 700 ? 20 : 24,
                  ),
                  children: [
                    _buildStatusHeader(completedCount, totalCount),
                    const SizedBox(height: 30),
                    const Text(
                      "Today's Timeline",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D0C57),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (_isLoading)
                      const InlineLoading(message: 'Loading care tasks...')
                    else if (_errorMessage != null)
                      StatusView.error(
                        title: 'Could not load care tasks',
                        message: _errorMessage!,
                        onAction: _loadTasks,
                      )
                    else if (_tasks.isEmpty)
                      const StatusView.empty(
                        icon: Icons.assignment_outlined,
                        title: 'No care tasks yet',
                        message:
                            'Tap the plus button to add a task for caregiver.',
                      )
                    else
                      _buildTaskTimeline(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTaskTimeline() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        const spacing = 14.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: _tasks
              .map(
                (task) => SizedBox(
                  width: itemWidth.isFinite && itemWidth > 0
                      ? itemWidth
                      : constraints.maxWidth,
                  child: _buildAuditTask(task),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildStatusHeader(int completedCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Daily Progress",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        "$completedCount/$totalCount",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          color: Color(0xFF00BFA5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        "Completed",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundColor: const Color(0xFFE0F2F1),
            child: Text(
              _initial(widget.assignedCaregiver),
              style: const TextStyle(
                color: Color(0xFF00BFA5),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditTask(_AdminCareTaskItem task) {
    final status = _statusLabel(task.status);
    final statusColor = _statusColor(task.status);
    final isCompleted = task.isCompleted;
    final completedTime = task.timeCompleted ?? task.updatedAt;
    final subtitle = task.status.toUpperCase() == 'PENDING'
        ? 'Assigned to ${widget.assignedCaregiver}'
        : '$status by ${widget.assignedCaregiver}${_formatDateTime(completedTime).isEmpty ? '' : ' at ${_formatDateTime(completedTime)}'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: task.status.toUpperCase() == 'SKIPPED'
            ? const Color(0xFFFFEBEE)
            : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final icon = Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_taskIcon(task.type), color: statusColor, size: 24),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${task.type} - ${task.frequency}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: task.status.toUpperCase() == 'PENDING'
                      ? statusColor
                      : Colors.grey,
                  fontSize: 12,
                  fontWeight: task.status.toUpperCase() == 'PENDING'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              if (task.remark != null && task.remark!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  task.remark!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          );
          final time = Text(
            task.scheduledTime,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 12,
            ),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: _isSaving || isCompleted
                    ? null
                    : () => _showTaskSheet(task: task),
                icon: const Icon(Icons.edit_outlined),
                color: isCompleted ? Colors.grey : const Color(0xFF00BFA5),
                tooltip: isCompleted
                    ? 'Completed tasks cannot be edited'
                    : 'Edit task',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: _isSaving ? null : () => _confirmDeleteTask(task),
                icon: const Icon(Icons.delete_outline),
                color: const Color(0xFFE53935),
                tooltip: 'Delete task',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          );
          final trailing = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [time, const SizedBox(height: 4), actions],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [icon, const Spacer(), actions]),
                const SizedBox(height: 12),
                time,
                const SizedBox(height: 8),
                details,
              ],
            );
          }

          return Row(
            children: [
              icon,
              const SizedBox(width: 15),
              Expanded(child: details),
              const SizedBox(width: 12),
              trailing,
            ],
          );
        },
      ),
    );
  }
}

class _RoutineTaskTemplate {
  final String title;
  final String type;
  final String scheduledTime;
  final String frequency;

  const _RoutineTaskTemplate({
    required this.title,
    required this.type,
    required this.scheduledTime,
    required this.frequency,
  });
}

class _RoutineTaskDraft {
  final TextEditingController titleController;
  String type;
  TimeOfDay scheduledTime;
  String frequency;

  _RoutineTaskDraft({
    required String title,
    required this.type,
    required this.scheduledTime,
    required this.frequency,
  }) : titleController = TextEditingController(text: title);

  factory _RoutineTaskDraft.fromTemplate(
    _RoutineTaskTemplate template, {
    required TimeOfDay? Function(String value) parseTime,
  }) {
    return _RoutineTaskDraft(
      title: template.title,
      type: template.type,
      scheduledTime:
          parseTime(template.scheduledTime) ??
          const TimeOfDay(hour: 8, minute: 0),
      frequency: template.frequency,
    );
  }

  void dispose() {
    titleController.dispose();
  }
}

class _AdminCareTaskItem {
  final String id;
  final String title;
  final String type;
  final String scheduledTime;
  final String frequency;
  final String status;
  final String? remark;
  final DateTime? updatedAt;
  final DateTime? timeCompleted;

  const _AdminCareTaskItem({
    required this.id,
    required this.title,
    required this.type,
    required this.scheduledTime,
    required this.frequency,
    required this.status,
    this.remark,
    this.updatedAt,
    this.timeCompleted,
  });

  bool get isCompleted => status.toUpperCase() == 'DONE';
}
