// Inventory item catalogue. Port of frontend/src/routes/Inventory/constants.ts.

class ItemDef {
  const ItemDef({
    required this.code,
    required this.label,
    required this.unit,
    required this.boxSize,
    required this.boxLabel,
    required this.perSession,
    required this.targetQty,
    required this.section, // 'nxstage' | 'hospital'
    required this.priority,
  });
  final String code;
  final String label;
  final String unit;
  final int boxSize;
  final String boxLabel;
  final int? perSession;
  final int targetQty;
  final String section;
  final int priority;
}

const items = <ItemDef>[
  // NxStage supplies
  ItemDef(code: 'SAK-303', label: 'SAK Dialysate', unit: 'bag', boxSize: 2, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 1),
  ItemDef(code: 'CAR-172-C', label: 'Cartridges', unit: 'cartridge', boxSize: 6, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 2),
  ItemDef(code: 'UK00000880', label: 'Saline 1L', unit: 'bag', boxSize: 10, boxLabel: 'box', perSession: 1, targetQty: 24, section: 'nxstage', priority: 3),
  ItemDef(code: 'PAK-001', label: 'PAK', unit: 'unit', boxSize: 1, boxLabel: 'piece', perSession: null, targetQty: 3, section: 'nxstage', priority: 4),
  ItemDef(code: 'P00012326', label: 'Buttonhole Needles', unit: 'needle', boxSize: 50, boxLabel: 'box', perSession: null, targetQty: 48, section: 'nxstage', priority: 5),
  ItemDef(code: 'UK00000774', label: 'On/Off Pack', unit: 'pack', boxSize: 60, boxLabel: 'box', perSession: null, targetQty: 24, section: 'nxstage', priority: 6),
  ItemDef(code: 'F00010983', label: 'Chlorine Strips', unit: 'strip', boxSize: 100, boxLabel: 'pack', perSession: 1, targetQty: 24, section: 'nxstage', priority: 7),
  ItemDef(code: 'UK00000830', label: 'Sani-Cloth AF', unit: 'box', boxSize: 1, boxLabel: 'box', perSession: null, targetQty: 1, section: 'nxstage', priority: 8),
  ItemDef(code: '1990134', label: 'Spirigel Hand Gel', unit: 'unit', boxSize: 1, boxLabel: 'piece', perSession: null, targetQty: 1, section: 'nxstage', priority: 9),
  ItemDef(code: 'UK00000832', label: 'Sharps Bin', unit: 'unit', boxSize: 1, boxLabel: 'piece', perSession: null, targetQty: 1, section: 'nxstage', priority: 10),
  ItemDef(code: 'UK00000172', label: 'Micropore Tape', unit: 'roll', boxSize: 12, boxLabel: 'box', perSession: null, targetQty: 4, section: 'nxstage', priority: 11),
  // Hospital prescriptions
  ItemDef(code: 'heparin', label: 'Heparin', unit: 'unit', boxSize: 1, boxLabel: 'unit', perSession: null, targetQty: 8, section: 'hospital', priority: 1),
  ItemDef(code: 'epo', label: 'EPO', unit: 'unit', boxSize: 1, boxLabel: 'unit', perSession: null, targetQty: 4, section: 'hospital', priority: 2),
];

ItemDef? getItem(String code) {
  for (final i in items) {
    if (i.code == code) return i;
  }
  return null;
}
