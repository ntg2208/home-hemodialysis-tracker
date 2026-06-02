// Panel grouping + display names. Port of frontend/src/routes/BloodTests/markers.ts.

const panels = ['Renal', 'Liver', 'Bone', 'Haematology', 'Other'];

const _panelMap = <String, String>{
  'creatinine': 'Renal', 'urea': 'Renal', 'egfr': 'Renal', 'sodium': 'Renal',
  'potassium': 'Renal', 'chloride': 'Renal', 'bicarbonate': 'Renal',
  'alt': 'Liver', 'ast': 'Liver', 'ggt': 'Liver',
  'alkaline_phosphatase': 'Liver', 'bilirubin': 'Liver', 'albumin': 'Liver',
  'total_protein': 'Liver',
  'adjusted_calcium': 'Bone', 'calcium': 'Bone', 'phosphate': 'Bone',
  'pth': 'Bone', 'vitamin_d': 'Bone', 'magnesium': 'Bone',
  'haemoglobin': 'Haematology', 'haematocrit': 'Haematology',
  'wbc': 'Haematology', 'rbc': 'Haematology', 'platelets': 'Haematology',
  'mcv': 'Haematology', 'mch': 'Haematology', 'mchc': 'Haematology',
  'ferritin': 'Haematology', 'rdw': 'Haematology',
  'neutrophils': 'Haematology', 'lymphocytes': 'Haematology',
};

const _displayOverrides = <String, String>{
  'egfr': 'eGFR', 'pth': 'PTH', 'alt': 'ALT', 'ast': 'AST', 'ggt': 'GGT',
  'wbc': 'WBC', 'rbc': 'RBC', 'mcv': 'MCV', 'mch': 'MCH', 'mchc': 'MCHC',
  'rdw': 'RDW', 'hba1c': 'HbA1c', 'crp': 'CRP',
};

String panelFor(String marker) => _panelMap[marker] ?? 'Other';

String displayName(String marker) {
  final override = _displayOverrides[marker];
  if (override != null) return override;
  return marker
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
