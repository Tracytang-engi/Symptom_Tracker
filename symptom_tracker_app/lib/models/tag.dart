// Tag 模型：代表一个可以贴到疼痛事件上的标签（如"饭后"、"运动后"）

class Tag {                        // class = 类定义，面向对象的基本单元
  final String id;                 // final = 只赋值一次，之后不可改；String = 字符串类型
  final String name;               // 标签显示名称
  final String icon;               // 图标名（对应 Material Icons 字符串名）
  bool isFavorite;                 // 没有 final，允许修改；bool = 布尔（true/false）
  int sortOrder;                   // int = 整数；控制排列顺序

  Tag({                            // 构造函数，{} 内为命名参数
    required this.id,              // required = 调用时必须传；this.id = 自动赋值给同名字段
    required this.name,
    this.icon = 'label',           // 有默认值，不传则为 'label'
    this.isFavorite = false,
    this.sortOrder = 0,
  });

  Tag copyWith({                   // copyWith = 常见模式：返回一个字段部分修改的新对象
    String? id,                    // ? = 可空类型，允许不传（为 null）
    String? name,
    String? icon,
    bool? isFavorite,
    int? sortOrder,
  }) {
    return Tag(                    // return = 返回新实例
      id: id ?? this.id,           // ?? = 空值合并：左边为 null 就取右边；this = 当前对象
      name: name ?? this.name,
      icon: icon ?? this.icon,
      isFavorite: isFavorite ?? this.isFavorite,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {   // => 箭头函数，单行返回值；Map = 键值对
    'id': id,                          // 把字段打包成 Map，  用于存 Hive
    'name': name,
    'icon': icon,
    'isFavorite': isFavorite,
    'sortOrder': sortOrder,
  };

  factory Tag.fromJson(Map<dynamic, dynamic> json) => Tag(  // factory = 工厂构造函数，从 Map 还原对象
    id: json['id'] as String,                               // as = 类型转换，告诉编译器这是 String
    name: json['name'] as String,
    icon: json['icon'] as String? ?? 'label',               // String? = 可能是 null，配合 ?? 给默认值
    isFavorite: json['isFavorite'] as bool? ?? false,
    sortOrder: json['sortOrder'] as int? ?? 0,
  );

  // static = 静态成员，不需要创建 Tag 实例就能用；get = 只读属性（getter）
  static List<Tag> get defaults => [   // List<Tag> = Tag 对象的列表
    Tag(id: 'after_meal',        name: 'After Meal',        icon: 'restaurant',      sortOrder: 0),
    Tag(id: 'after_exercise',    name: 'After Exercise',    icon: 'directions_run',  sortOrder: 1),
    Tag(id: 'during_sleep',      name: 'During Sleep',      icon: 'bedtime',         sortOrder: 2),
    Tag(id: 'after_medication',  name: 'After Medication',  icon: 'medication',      sortOrder: 3),
    Tag(id: 'after_waking',      name: 'After Waking',      icon: 'wb_sunny',        sortOrder: 4),
    Tag(id: 'before_medication', name: 'Before Medication', icon: 'medication',      sortOrder: 5),
    Tag(id: 'during_period',     name: 'During Period',     icon: 'calendar_month',  sortOrder: 6),
    Tag(id: 'emotional_stress',  name: 'Emotional Stress',  icon: 'sentiment_stressed', sortOrder: 7),
    Tag(id: 'light_sensitivity', name: 'Light Sensitivity', icon: 'light_mode',      sortOrder: 8),
    Tag(id: 'poor_sleep',        name: 'Poor Sleep',        icon: 'bedtime',         sortOrder: 9),
  ];

  /// Accessible Mode 标签弹层固定四格（饭后 / 运动后 / 睡眠时 / 服药后）
  static List<Tag> get accessibleQuickTags => [
    Tag(id: 'after_meal',       name: 'After Meal',       icon: 'restaurant',     sortOrder: 0),
    Tag(id: 'after_exercise',   name: 'After Exercise',   icon: 'directions_run', sortOrder: 1),
    Tag(id: 'during_sleep',     name: 'During Sleep',     icon: 'bedtime',        sortOrder: 2),
    Tag(id: 'after_medication', name: 'After Medication', icon: 'medication',     sortOrder: 3),
  ];
}
