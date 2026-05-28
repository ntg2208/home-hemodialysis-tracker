export interface ItemDef {
  code: string;
  label: string;
  unit: string;
  boxSize: number;
  boxLabel: string;
  perSession: number | null;
  targetQty: number;
  section: 'nxstage' | 'hospital';
  priority: number;
}

export const ITEMS: ItemDef[] = [
  // NxStage supplies
  { code: 'SAK-303',    label: 'SAK Dialysate',      unit: 'bag',       boxSize: 2,   boxLabel: 'box',   perSession: 1,    targetQty: 24, section: 'nxstage',  priority: 1 },
  { code: 'CAR-172-C',  label: 'Cartridges',         unit: 'cartridge', boxSize: 6,   boxLabel: 'box',   perSession: 1,    targetQty: 24, section: 'nxstage',  priority: 2 },
  { code: 'UK00000880', label: 'Saline 1L',          unit: 'bag',       boxSize: 10,  boxLabel: 'box',   perSession: 1,    targetQty: 24, section: 'nxstage',  priority: 3 },
  { code: 'PAK-001',    label: 'PAK',                unit: 'unit',      boxSize: 1,   boxLabel: 'piece', perSession: null, targetQty: 3,  section: 'nxstage',  priority: 4 },
  { code: 'P00012326',  label: 'Buttonhole Needles', unit: 'needle',    boxSize: 50,  boxLabel: 'box',   perSession: null, targetQty: 48, section: 'nxstage',  priority: 5 },
  { code: 'UK00000774', label: 'On/Off Pack',        unit: 'pack',      boxSize: 60,  boxLabel: 'box',   perSession: null, targetQty: 24, section: 'nxstage',  priority: 6 },
  { code: 'F00010983',  label: 'Chlorine Strips',    unit: 'strip',     boxSize: 100, boxLabel: 'pack',  perSession: 1,    targetQty: 24, section: 'nxstage',  priority: 7 },
  { code: 'UK00000830', label: 'Sani-Cloth AF',      unit: 'box',       boxSize: 1,   boxLabel: 'box',   perSession: null, targetQty: 1,  section: 'nxstage',  priority: 8 },
  { code: '1990134',    label: 'Spirigel Hand Gel',  unit: 'unit',      boxSize: 1,   boxLabel: 'piece', perSession: null, targetQty: 1,  section: 'nxstage',  priority: 9 },
  { code: 'UK00000832', label: 'Sharps Bin',         unit: 'unit',      boxSize: 1,   boxLabel: 'piece', perSession: null, targetQty: 1,  section: 'nxstage',  priority: 10 },
  { code: 'UK00000172', label: 'Micropore Tape',     unit: 'roll',      boxSize: 12,  boxLabel: 'box',   perSession: null, targetQty: 4,  section: 'nxstage',  priority: 11 },
  // Hospital prescriptions
  { code: 'heparin',    label: 'Heparin',            unit: 'unit',      boxSize: 1,   boxLabel: 'unit',  perSession: null, targetQty: 8,  section: 'hospital', priority: 1 },
  { code: 'epo',        label: 'EPO',                unit: 'unit',      boxSize: 1,   boxLabel: 'unit',  perSession: null, targetQty: 4,  section: 'hospital', priority: 2 },
];

export function getItem(code: string): ItemDef | undefined {
  return ITEMS.find(i => i.code === code);
}

// Fixed per-session deductions (variable items are passed explicitly by the caller)
export const SESSION_FIXED_DELTAS: Record<string, number> = {
  'SAK-303': -1,
  'CAR-172-C': -1,
  'UK00000880': -1,
  'F00010983': -1,
};
