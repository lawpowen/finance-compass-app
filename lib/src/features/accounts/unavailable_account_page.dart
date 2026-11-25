import 'package:flutter/material.dart';

import '../shared/empty_state.dart';

class UnavailableAccountPage extends StatelessWidget {
  const UnavailableAccountPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('账户详情')),
        body: const EmptyState(title: '账户已移除或类型已改变，请返回账户列表。'),
      );
}
