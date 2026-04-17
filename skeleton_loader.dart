import 'package:flutter/material.dart';

class SkeletonLoader extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const SkeletonLoader({
    super.key,
    this.width,
    this.height = 20,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}