import 'package:ipaddr/ipaddr.dart';

/// PHASE 3: Network Intelligence Tools
/// This utility provides the logic for the Dart-based CIDR Calculator.
class NetworkUtils {
  
  /// Calculates critical network boundaries from an IP/Mask input.
  static Map<String, String> calculateSubnet(String cidrInput) {
    try {
      final network = IPv4Network(cidrInput);
      final usableHosts = network.hosts;

      // Handle edge case: /32 or /31 might have empty or restricted host lists
      String firstIp = "N/A";
      String lastIp = "N/A";
      
      if (usableHosts.isNotEmpty) {
        firstIp = usableHosts.first.toString();
        lastIp = usableHosts.last.toString();
      } else if (network.prefixlen == 32) {
        // A /32 is a single host
        firstIp = network.networkAddress.toString();
        lastIp = network.networkAddress.toString();
      }

      return {
        'network_id': network.networkAddress.toString(),
        'netmask': network.netmask.toString(),
        'broadcast': network.broadcastAddress.toString(),
        'wildcard': _calculateWildcard(network.netmask.toString()),
        'first_ip': firstIp,
        'last_ip': lastIp,
        'total_hosts': network.numAddresses.toString(),
      };
    } catch (e) {
      return {'error': 'Invalid CIDR format. Use: x.x.x.x/24'};
    }
  }

  /// NEW: Calculates the Wildcard Mask (Inverted Subnet Mask)
  /// Subtracts each octet of the mask from 255.
  static String _calculateWildcard(String mask) {
    try {
      return mask.split('.').map((octet) {
        int val = int.parse(octet);
        return (255 - val).toString();
      }).join('.');
    } catch (e) {
      return "0.0.0.0";
    }
  }

  /// HEURISTIC TROUBLESHOOTING ENGINE
  static double calculateRelevancy(int frequency, int complexity) {
    return (frequency * 0.4) + (complexity * 0.6);
  }
}