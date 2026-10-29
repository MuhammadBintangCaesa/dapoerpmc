import 'package:flutter/material.dart';

import 'backend_api.dart';

class DapoerHeader extends StatelessWidget {
  const DapoerHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final account = BackendApi.instance.account;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffe8e5df))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showName = constraints.maxWidth > 540 && account != null;
          final showBrand = constraints.maxWidth > 360;
          return Row(
            children: [
              Image.asset(
                'assets/images/logodapoerpmcsu.png',
                height: 42,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.restaurant,
                  color: Color(0xffcda64d),
                  size: 34,
                ),
              ),
              if (showBrand) ...[
                const SizedBox(width: 10),
                const Text(
                  'Dapoer PMCSU',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
              const Spacer(),
              if (showName) ...[
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      account['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      account['role']?.toString() ?? '',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xffe0f5ef),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(0xff21856c), size: 8),
                    SizedBox(width: 6),
                    Text(
                      'Online',
                      style: TextStyle(
                        color: Color(0xff21856c),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xfff2ead7),
                child: Text(
                  (account?['name']?.toString().isNotEmpty ?? false)
                      ? account!['name'].toString()[0].toUpperCase()
                      : 'D',
                  style: const TextStyle(
                    color: Color(0xff9a782f),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
