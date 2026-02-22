import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'network_utils.dart';

class IpIntelScreen extends StatefulWidget {
  const IpIntelScreen({super.key});

  @override
  State<IpIntelScreen> createState() => _IpIntelScreenState();
}

class _IpIntelScreenState extends State<IpIntelScreen> {
  final TextEditingController _cidrController = TextEditingController(text: "192.168.1.0/24");
  Map<String, String>? _results;

  void _calculate() {
    setState(() {
      _results = NetworkUtils.calculateSubnet(_cidrController.text);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("IP Intel: CIDR Calculator")),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Enter CIDR Notation", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _cidrController,
            style: const TextStyle(fontSize: 22, fontFamily: 'monospace', color: Colors.cyanAccent),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: const Icon(Icons.calculate, color: Colors.greenAccent),
                onPressed: _calculate,
              ),
              border: const OutlineInputBorder(),
              hintText: "10.0.0.0/22",
            ),
            keyboardType: TextInputType.text,
            onSubmitted: (_) => _calculate(),
          ),
          const SizedBox(height: 30),
          if (_results != null) _buildResultsView(),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    if (_results!.containsKey('error')) {
      return Text(_results!['error']!, style: const TextStyle(color: Colors.redAccent));
    }

    return Column(
      children: [
        _resultTile("Network ID", _results!['network_id']!),
        _resultTile("Subnet Mask", _results!['netmask']!),
        _resultTile("Wildcard Mask", _results!['wildcard'] ?? "0.0.0.0"),
        _resultTile("Broadcast Address", _results!['broadcast']!),
        const Divider(height: 40),
        _resultTile("First Usable Address", _results!['first_ip']!),
        _resultTile("Last Usable Address", _results!['last_ip']!),
        _resultTile("Total Hosts", _results!['total_hosts']!),
      ],
    );
  }

  Widget _resultTile(String label, String value) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label copied")));
        },
      ),
    );
  }
}