import 'package:flutter/material.dart';

/// The official NineSoft brand supplied by the product owner.
///
/// Keep the source image unchanged so all platforms render the same approved
/// identity. Branch logos remain separate and continue to be configured from
/// business identity settings for invoices and documents.
class NineSoftBrandLogo extends StatelessWidget {
  const NineSoftBrandLogo({
    super.key,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius = 14,
  });

  static const assetPath = 'assets/branding/ninesoft-official-logo.png';

  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'NineSoft - ناين سوفت للأنظمة والحلول المالية',
    child: Container(
      width: width,
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    ),
  );
}
