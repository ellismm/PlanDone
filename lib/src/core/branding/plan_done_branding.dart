import 'package:flutter/material.dart';

abstract final class PlanDoneBranding {
  static const logoAsset = 'assets/branding/plandone_logo.png';
  static const markAsset = 'assets/branding/plandone_mark.png';
}

class PlanDoneBrandMark extends StatelessWidget {
  const PlanDoneBrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      PlanDoneBranding.markAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

class PlanDoneLogo extends StatelessWidget {
  const PlanDoneLogo({super.key, this.height = 88});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      PlanDoneBranding.logoAsset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
