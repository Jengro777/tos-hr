class WeComMember {
  const WeComMember({required this.userId, required this.departmentIds});

  final String userId;
  final List<int> departmentIds;
}

enum WeComEmailType {
  enterprise(1, '企业邮箱'),
  personal(2, '个人邮箱');

  const WeComEmailType(this.apiValue, this.label);

  final int apiValue;
  final String label;
}
