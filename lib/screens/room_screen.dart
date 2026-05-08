import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/party_controller.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final party = context.watch<PartyController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Комната'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: () async {
              final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Выйти из комнаты?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Выйти'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
              if (ok && context.mounted) {
                await context.read<PartyController>().leaveRoom();
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(
                    party.iAmDj ? 'Вы — диджей' : 'Вы — слушатель',
                  ),
                  avatar: Icon(
                    party.iAmDj ? Icons.graphic_eq : Icons.headphones,
                  ),
                ),
                const SizedBox(width: 8),
                if (party.awaitingHandoverAck)
                  const Chip(
                    label: Text('Ожидание передачи…'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Уровень',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: party.meterLevel.clamp(0.0, 1.0),
              minHeight: 12,
            ),
            const SizedBox(height: 24),
            if (party.iAmDj) ...[
              if (!party.capturing)
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await party.startDjCapture();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Ошибка захвата: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('Начать захват звука'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => party.stopDjCapture(),
                  icon: const Icon(Icons.stop),
                  label: const Text('Остановить захват'),
                ),
            ] else ...[
              FilledButton.icon(
                onPressed: party.awaitingHandoverAck
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Стать диджеем?'),
                                content: const Text(
                                  'Текущий диджей перестанет транслировать. '
                                  'Вы разрешите захват экрана/звука на этом телефоне.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Отмена'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Да'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                        if (ok && context.mounted) {
                          await party.requestBecomeDj();
                        }
                      },
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Стать диджеем'),
              ),
            ],
            const Spacer(),
            Text(
              'Подсказка: включите музыку в другом приложении после старта захвата. '
              'Держите оба телефона рядом (Wi‑Fi Direct / Bluetooth через Nearby).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
