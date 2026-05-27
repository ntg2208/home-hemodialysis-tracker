export const PANELS = ['Renal', 'Liver', 'Bone', 'Haematology', 'Other'] as const;
export type Panel = (typeof PANELS)[number];

const PANEL_MAP: Record<string, Panel> = {
  creatinine: 'Renal', urea: 'Renal', egfr: 'Renal', sodium: 'Renal',
  potassium: 'Renal', chloride: 'Renal', bicarbonate: 'Renal',
  alt: 'Liver', ast: 'Liver', ggt: 'Liver', alkaline_phosphatase: 'Liver',
  bilirubin: 'Liver', albumin: 'Liver', total_protein: 'Liver',
  adjusted_calcium: 'Bone', calcium: 'Bone', phosphate: 'Bone',
  pth: 'Bone', vitamin_d: 'Bone', magnesium: 'Bone',
  haemoglobin: 'Haematology', haematocrit: 'Haematology', wbc: 'Haematology',
  rbc: 'Haematology', platelets: 'Haematology', mcv: 'Haematology',
  mch: 'Haematology', mchc: 'Haematology', ferritin: 'Haematology',
  rdw: 'Haematology', neutrophils: 'Haematology', lymphocytes: 'Haematology',
};

const DISPLAY_OVERRIDES: Record<string, string> = {
  egfr: 'eGFR', pth: 'PTH', alt: 'ALT', ast: 'AST', ggt: 'GGT',
  wbc: 'WBC', rbc: 'RBC', mcv: 'MCV', mch: 'MCH', mchc: 'MCHC',
  rdw: 'RDW', hba1c: 'HbA1c', crp: 'CRP',
};

export function panelFor(marker: string): Panel {
  return PANEL_MAP[marker] ?? 'Other';
}

export function displayName(marker: string): string {
  return (
    DISPLAY_OVERRIDES[marker] ??
    marker.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
  );
}
