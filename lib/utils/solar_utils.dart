/// Battery SOC% from voltage + system voltage (12/24/36/48V)
int batteryPercentage(double voltage, {int systemVoltage = 12}) {
  const thresholds = {
    12: [12.9, 12.6, 12.5, 12.3, 12.2, 12.1, 11.9, 11.8, 11.7, 11.6, 11.5],
    24: [26.5, 26.0, 25.8, 25.4, 25.2, 25.0, 24.8, 24.4, 24.0, 23.8, 23.0],
    36: [38.7, 37.8, 37.5, 36.9, 36.6, 36.3, 35.7, 35.4, 35.1, 34.8, 34.5],
    48: [51.6, 50.4, 50.0, 49.2, 48.8, 48.4, 47.6, 47.2, 46.8, 46.4, 46.0],
  };
  final t = thresholds[systemVoltage] ?? thresholds[12]!;
  for (var i = 0; i < t.length; i++) {
    if (voltage >= t[i]) return 100 - i * 10;
  }
  return 0;
}

/// MPPT charge state code → label
String mpptStateLabel(String code) {
  const map = {
    '0': 'Off', '2': 'Fault', '3': 'Bulk', '4': 'Absorption', '5': 'Float',
    '7': 'Equalize', '245': 'Starting', '247': 'Auto Equalize',
  };
  return map[code] ?? 'Unknown ($code)';
}

/// MPPT error code → label
String mpptErrorLabel(String code) {
  const map = {
    '0': 'No error', '2': 'Battery voltage too high', '17': 'Charger temp too high',
    '18': 'Charger over current', '19': 'Charger current reversed',
    '20': 'Bulk time limit exceeded', '21': 'Current sensor issue',
    '26': 'Terminals overheated', '33': 'Input voltage too high',
    '34': 'Input current too high', '38': 'Input shutdown (battery)',
    '116': 'Factory calibration lost', '117': 'Invalid firmware',
  };
  return map[code] ?? 'Error $code';
}
