class ApiConstants {
  static const baseUrl = 'https://7fr0oi55ld.execute-api.us-west-2.amazonaws.com/v1';

  // Cloud REST API (same backend as admin, for device metadata)
  static const cloudApi = 'https://8xz1g0t7oa.execute-api.us-west-2.amazonaws.com/v1';

  // Auth — Cognito
  static const cognitoRegion = 'us-west-2';
  static const cognitoUserPoolId = 'us-west-2_SekXWaB3L';
  static const cognitoClientId = '386ujj0htracaeehnfb8764b43';

  // Devices
  static String get userDevice => '$baseUrl/solar-chain/ec-user-device';
  static String get device => '$baseUrl/solar-chain/ec-device';
  static String get subDevice => '$baseUrl/solar-chain/ec-sub-device';

  // Users
  static String get user => '$baseUrl/solar-chain/usr';

  // Energy
  static String get energyConsumption => '$baseUrl/solar-chain/energy_consumption';

  // IoT
  static String get rpi => '$baseUrl/iot/rpi';
  static String iotSolar(String code) => '$baseUrl/iot/solar/$code';

  // MPPT
  static String get mppt => '$baseUrl/query/mppt';

  // Relay
  static String get relay => '$baseUrl/relay';

  // Ping
  static String get ping => '$baseUrl/solar-chain/ping';
}

class BridgeConstants {
  static const _localWs = 'ws://localhost:9090';
  static const _awsWs = 'wss://5k39j2zuye.execute-api.us-west-2.amazonaws.com/prod';
  // Dev uses AWS bridge for signaling (real Cognito auth), local bridge as fallback
  static String get wsUrl => _awsWs;
  static String get localWsUrl => _localWs;
}

class WebRTCConstants {
  static const iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
    {'urls': 'stun:stun.stunprotocol.org:3478'},
    // TURN relay fallback — required when mobile is behind carrier-grade NAT
    // Replace with your own coturn or a paid TURN service for production
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443',
        'turns:openrelay.metered.ca:443',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];
}
