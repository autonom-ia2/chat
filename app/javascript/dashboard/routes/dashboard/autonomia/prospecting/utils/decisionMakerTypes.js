// Tipo de decisor que a busca procura (#677). Perfis do Orth
// (lib/research/decisor-role-options.ts): só o Proprietário tem pesquisa
// pronta; os outros aparecem desabilitados, "em breve", para quem já conhece
// o catálogo não achar que sumiram. Os valores são os do backend
// (Autonomia::Prospecting::DecisionMakerType).
export const DEFAULT_DECISION_MAKER_TYPE = 'owner';

const DECISION_MAKER_TYPES = [
  { value: 'owner', key: 'OWNER', available: true },
  { value: 'ceo', key: 'CEO', available: false },
  { value: 'commercial', key: 'COMMERCIAL', available: false },
  { value: 'financial', key: 'FINANCIAL', available: false },
  { value: 'marketing', key: 'MARKETING', available: false },
  { value: 'hr', key: 'HR', available: false },
  { value: 'operations', key: 'OPERATIONS', available: false },
  { value: 'technology', key: 'TECHNOLOGY', available: false },
  { value: 'legal', key: 'LEGAL', available: false },
  { value: 'compliance', key: 'COMPLIANCE', available: false },
  { value: 'risk', key: 'RISK', available: false },
];

export const decisionMakerChoices = t =>
  DECISION_MAKER_TYPES.map(({ value, key, available }) => {
    const label = t(`PROSPECTING.DECISION_MAKER.TYPES.${key}`);
    return {
      value,
      label: available
        ? label
        : t('PROSPECTING.DECISION_MAKER.COMING_SOON', { label }),
      disabled: !available,
    };
  });
