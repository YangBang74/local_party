import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/party_controller.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final TextEditingController _nickController;

  @override
  void initState() {
    super.initState();
    final party = context.read<PartyController>();
    _nickController = TextEditingController(text: party.nickname);
  }

  @override
  void dispose() {
    _nickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final party = context.watch<PartyController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Party'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Важно: захват системного звука через MediaProjection. '
                'Многие приложения (Spotify, YouTube Music и др.) запрещают захват — '
                'это ограничение Android, а не баг. Для проверки используйте локальный '
                'файл/браузер/плеер, который разрешает запись.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nickController,
            decoration: const InputDecoration(
              labelText: 'Ваше имя в комнате',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => party.nickname = v.trim().isEmpty ? 'Guest' : v.trim(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: party.advertising
                      ? null
                      : () async {
                          party.setCreatedRoomIntent(true);
                          party.nickname =
                              _nickController.text.trim().isEmpty
                                  ? 'Host'
                                  : _nickController.text.trim();
                          await party.createRoom();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  party.advertising
                                      ? 'Комната создана — ждём второго телефона'
                                      : 'Не удалось начать рекламу',
                                ),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Создать комнату'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: party.discovering
                      ? null
                      : () async {
                          party.setCreatedRoomIntent(false);
                          party.nickname =
                              _nickController.text.trim().isEmpty
                                  ? 'Guest'
                                  : _nickController.text.trim();
                          await party.startFindingRooms();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  party.discovering
                                      ? 'Ищем комнаты рядом…'
                                      : 'Поиск не запущен',
                                ),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('Найти комнату'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Обнаруженные устройства',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (party.discoveredEndpoints.isEmpty)
            Text(
              party.discovering
                  ? 'Ожидание… включите Wi‑Fi / Bluetooth.'
                  : 'Запустите поиск или создайте комнату на другом телефоне.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...party.discoveredEndpoints.entries.map((e) {
              return Card(
                child: ListTile(
                  title: Text(e.value),
                  subtitle: Text(e.key),
                  trailing: FilledButton(
                    onPressed: () async {
                      await party.connectToEndpoint(e.key);
                      if (context.mounted && party.isConnected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Подключено')),
                        );
                      }
                    },
                    child: const Text('Подключиться'),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
