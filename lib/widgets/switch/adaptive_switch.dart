import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';

class AdaptiveSwitch extends StatelessWidget {
  final bool value;
  final Color? activeColor;
  final void Function(bool)? onChanged;
  const AdaptiveSwitch({
    super.key,
    required this.value,
    this.activeColor,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      activeTrackColor: activeColor ?? AppTheme.primaryGreen,
      activeThumbColor: activeColor ?? AppTheme.primaryGreen,
      onChanged: onChanged,
    );
  }
}
