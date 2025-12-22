import 'package:flutter/material.dart';
import '../models/irrigation_models.dart';

class TankWidget extends StatelessWidget {
  final Tank tank;

  const TankWidget({super.key, required this.tank});

  Color get _tankColor {
    switch (tank.type) {
      case TankType.acid:
        return Colors.redAccent;
      case TankType.base:
        return Colors.blueAccent;
      case TankType.fertilizerA:
        return Colors.green;
      case TankType.fertilizerB:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Container
            Container(
              height: 100,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
            ),
            // Fluid
            Container(
              height: 100 * tank.fillPercentage,
              width: 40,
              decoration: BoxDecoration(
                color: _tankColor.withOpacity(0.8),
                borderRadius: BorderRadius.vertical(
                  bottom: const Radius.circular(8),
                  top: Radius.circular(tank.fillPercentage == 1 ? 8 : 0),
                ),
              ),
            ),
            // Reserve Indicator
            if (tank.isReserve)
              Positioned(
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'R',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tank.name,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${(tank.fillPercentage * 100).toInt()}%',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
