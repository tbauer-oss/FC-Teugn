class OperationsPerson {
  const OperationsPerson({required this.id, required this.name});

  final String id;
  final String name;

  factory OperationsPerson.fromJson(Map<String, dynamic> json) {
    final preferredName = json['preferredName'] as String?;
    final firstName = json['firstName'] as String?;
    final lastName = json['lastName'] as String?;
    return OperationsPerson(
      id: json['id'] as String,
      name: json['name'] as String? ??
          [
            if (preferredName?.isNotEmpty == true) preferredName else firstName,
            lastName,
          ].whereType<String>().join(' '),
    );
  }
}

class TeamTaskModel {
  const TeamTaskModel({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    this.description,
    this.assignee,
    this.dueAt,
  });

  final String id;
  final String title;
  final String category;
  final String status;
  final String? description;
  final OperationsPerson? assignee;
  final DateTime? dueAt;

  bool get isDone => status == 'DONE' || status == 'CANCELLED';
  bool get isOverdue =>
      !isDone && dueAt != null && dueAt!.isBefore(DateTime.now());

  factory TeamTaskModel.fromJson(Map<String, dynamic> json) => TeamTaskModel(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? 'SONSTIGES',
        status: json['status'] as String? ?? 'OPEN',
        description: json['description'] as String?,
        assignee: json['assignee'] == null
            ? null
            : OperationsPerson.fromJson(
                json['assignee'] as Map<String, dynamic>,
              ),
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String).toLocal(),
      );
}

class EquipmentAssignmentModel {
  const EquipmentAssignmentModel({
    required this.id,
    required this.quantity,
    required this.recipient,
    required this.assignedAt,
    this.dueAt,
  });

  final String id;
  final int quantity;
  final OperationsPerson recipient;
  final DateTime assignedAt;
  final DateTime? dueAt;

  bool get isOverdue => dueAt != null && dueAt!.isBefore(DateTime.now());

  factory EquipmentAssignmentModel.fromJson(Map<String, dynamic> json) =>
      EquipmentAssignmentModel(
        id: json['id'] as String,
        quantity: json['quantity'] as int? ?? 1,
        recipient: OperationsPerson.fromJson(
          (json['assignedToUser'] ?? json['assignedToPlayer'])
              as Map<String, dynamic>,
        ),
        assignedAt: DateTime.parse(json['assignedAt'] as String).toLocal(),
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String).toLocal(),
      );
}

class EquipmentItemModel {
  const EquipmentItemModel({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.status,
    required this.assignments,
    this.notes,
  });

  final String id;
  final String name;
  final String category;
  final int quantity;
  final String status;
  final String? notes;
  final List<EquipmentAssignmentModel> assignments;

  int get assignedQuantity =>
      assignments.fold(0, (sum, item) => sum + item.quantity);
  int get availableQuantity => quantity - assignedQuantity;

  factory EquipmentItemModel.fromJson(Map<String, dynamic> json) =>
      EquipmentItemModel(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String? ?? 'SONSTIGES',
        quantity: json['quantity'] as int? ?? 1,
        status: json['status'] as String? ?? 'ACTIVE',
        notes: json['notes'] as String?,
        assignments: (json['assignments'] as List<dynamic>? ?? [])
            .map(
              (item) => EquipmentAssignmentModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class ChecklistTemplateItemModel {
  const ChecklistTemplateItemModel({
    required this.id,
    required this.title,
    required this.isRequired,
  });

  final String id;
  final String title;
  final bool isRequired;

  factory ChecklistTemplateItemModel.fromJson(Map<String, dynamic> json) =>
      ChecklistTemplateItemModel(
        id: json['id'] as String,
        title: json['title'] as String,
        isRequired: json['isRequired'] as bool? ?? true,
      );
}

class ChecklistTemplateModel {
  const ChecklistTemplateModel({
    required this.id,
    required this.title,
    required this.category,
    required this.items,
    this.description,
  });

  final String id;
  final String title;
  final String category;
  final String? description;
  final List<ChecklistTemplateItemModel> items;

  factory ChecklistTemplateModel.fromJson(Map<String, dynamic> json) =>
      ChecklistTemplateModel(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? 'SONSTIGES',
        description: json['description'] as String?,
        items: (json['items'] as List<dynamic>? ?? [])
            .map(
              (item) => ChecklistTemplateItemModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}

class ChecklistRunItemModel {
  const ChecklistRunItemModel({
    required this.id,
    required this.title,
    required this.isRequired,
    required this.isCompleted,
    this.completedBy,
  });

  final String id;
  final String title;
  final bool isRequired;
  final bool isCompleted;
  final OperationsPerson? completedBy;

  factory ChecklistRunItemModel.fromJson(Map<String, dynamic> json) =>
      ChecklistRunItemModel(
        id: json['id'] as String,
        title: json['title'] as String,
        isRequired: json['isRequired'] as bool? ?? true,
        isCompleted: json['isCompleted'] as bool? ?? false,
        completedBy: json['completedBy'] == null
            ? null
            : OperationsPerson.fromJson(
                json['completedBy'] as Map<String, dynamic>,
              ),
      );
}

class ChecklistRunModel {
  const ChecklistRunModel({
    required this.id,
    required this.title,
    required this.category,
    required this.status,
    required this.items,
    this.dueAt,
  });

  final String id;
  final String title;
  final String category;
  final String status;
  final List<ChecklistRunItemModel> items;
  final DateTime? dueAt;

  int get completedCount => items.where((item) => item.isCompleted).length;
  double get progress => items.isEmpty ? 0 : completedCount / items.length;

  factory ChecklistRunModel.fromJson(Map<String, dynamic> json) =>
      ChecklistRunModel(
        id: json['id'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? 'SONSTIGES',
        status: json['status'] as String? ?? 'ACTIVE',
        items: (json['items'] as List<dynamic>? ?? [])
            .map(
              (item) => ChecklistRunItemModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList(),
        dueAt: json['dueAt'] == null
            ? null
            : DateTime.parse(json['dueAt'] as String).toLocal(),
      );
}

class TeamOperationsOverview {
  const TeamOperationsOverview({
    required this.teamId,
    required this.canManage,
    required this.tasks,
    required this.equipment,
    required this.checklistTemplates,
    required this.checklistRuns,
    required this.members,
    required this.players,
  });

  final String teamId;
  final bool canManage;
  final List<TeamTaskModel> tasks;
  final List<EquipmentItemModel> equipment;
  final List<ChecklistTemplateModel> checklistTemplates;
  final List<ChecklistRunModel> checklistRuns;
  final List<OperationsPerson> members;
  final List<OperationsPerson> players;

  factory TeamOperationsOverview.fromJson(Map<String, dynamic> json) =>
      TeamOperationsOverview(
        teamId: json['teamId'] as String,
        canManage: json['canManage'] as bool? ?? false,
        tasks: (json['tasks'] as List<dynamic>? ?? [])
            .map((item) =>
                TeamTaskModel.fromJson(item as Map<String, dynamic>))
            .toList(),
        equipment: (json['equipment'] as List<dynamic>? ?? [])
            .map((item) =>
                EquipmentItemModel.fromJson(item as Map<String, dynamic>))
            .toList(),
        checklistTemplates:
            (json['checklistTemplates'] as List<dynamic>? ?? [])
                .map(
                  (item) => ChecklistTemplateModel.fromJson(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList(),
        checklistRuns: (json['checklistRuns'] as List<dynamic>? ?? [])
            .map((item) =>
                ChecklistRunModel.fromJson(item as Map<String, dynamic>))
            .toList(),
        members: (json['members'] as List<dynamic>? ?? [])
            .map((item) =>
                OperationsPerson.fromJson(item as Map<String, dynamic>))
            .toList(),
        players: (json['players'] as List<dynamic>? ?? [])
            .map((item) =>
                OperationsPerson.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}
