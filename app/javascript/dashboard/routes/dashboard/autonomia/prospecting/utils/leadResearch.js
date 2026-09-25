// Pesquisa de empresa e decisor do lead (#679), como a tela lê o bloco research
// que a API e o evento prospecting.lead.updated trazem. Estados por capacidade
// portados do Orth (ResearchStatePresentation.tsx), sem os de cobrança
// (reconciling, insufficient_credits), que ficaram fora por decisão.

const STATE_PRESENTATION = {
  not_researched: {
    labelKey: 'NOT_RESEARCHED',
    tone: 'neutral',
    icon: 'i-lucide-circle-dashed',
    terminal: false,
  },
  queued: {
    labelKey: 'QUEUED',
    tone: 'info',
    icon: 'i-lucide-clock-3',
    terminal: false,
  },
  researching: {
    labelKey: 'RESEARCHING',
    tone: 'info',
    icon: 'i-lucide-loader-circle',
    terminal: false,
  },
  waiting_capacity: {
    labelKey: 'WAITING_CAPACITY',
    tone: 'warning',
    icon: 'i-lucide-clock-3',
    terminal: false,
  },
  confirmed: {
    labelKey: 'CONFIRMED',
    tone: 'success',
    icon: 'i-lucide-circle-check',
    terminal: true,
  },
  possible: {
    labelKey: 'POSSIBLE',
    tone: 'warning',
    icon: 'i-lucide-circle-help',
    terminal: true,
  },
  ambiguous: {
    labelKey: 'AMBIGUOUS',
    tone: 'warning',
    icon: 'i-lucide-circle-help',
    terminal: true,
  },
  no_result: {
    labelKey: 'NO_RESULT',
    tone: 'neutral',
    icon: 'i-lucide-search',
    terminal: true,
  },
  failed: {
    labelKey: 'FAILED',
    tone: 'danger',
    icon: 'i-lucide-circle-alert',
    terminal: true,
  },
  blocked: {
    labelKey: 'BLOCKED',
    tone: 'danger',
    icon: 'i-lucide-lock',
    terminal: true,
  },
};

export const RESEARCH_STATES = Object.keys(STATE_PRESENTATION);

export const researchStatePresentation = status => {
  const presentation =
    STATE_PRESENTATION[status] || STATE_PRESENTATION.not_researched;
  return {
    ...presentation,
    labelKey: `PROSPECTING.RESEARCH.STATES.${presentation.labelKey}`,
  };
};

const RUNNING_STATES = ['researching', 'waiting_capacity'];

const statusesOf = research => [
  research?.company_status || 'not_researched',
  research?.decision_status || 'not_researched',
];

// Fase do lead na pesquisa, juntando empresa e decisor: none (nunca pedida),
// queued, running, failed ou done.
export const researchPhase = research => {
  const statuses = statusesOf(research);
  if (statuses.some(status => RUNNING_STATES.includes(status))) {
    return 'running';
  }
  if (statuses.includes('queued')) return 'queued';
  if (statuses.every(status => status === 'not_researched')) return 'none';
  if (statuses.includes('failed')) return 'failed';
  return 'done';
};

export const isResearchActive = research =>
  ['queued', 'running'].includes(researchPhase(research));

const emptyProgress = () => ({
  total: 0,
  done: 0,
  running: 0,
  queued: 0,
  failed: 0,
});

// Progresso da busca aberta. Os leads chegam ao vivo pelo evento, então contam
// primeiro; o research_progress da busca vale enquanto os leads não trazem o
// bloco. Nenhum lead pesquisado: sem progresso, e a barra não aparece.
export const researchProgress = (leads, searchProgress) => {
  const researched = (leads || []).filter(lead => lead?.research);
  if (!researched.length) {
    return searchProgress?.total > 0 ? searchProgress : null;
  }

  const progress = researched.reduce((counts, lead) => {
    const phase = researchPhase(lead.research);
    if (phase === 'none') return counts;
    return { ...counts, total: counts.total + 1, [phase]: counts[phase] + 1 };
  }, emptyProgress());

  return progress.total > 0 ? progress : null;
};

const isDigit = char => char >= '0' && char <= '9';

export const cnpjDigits = value =>
  [...String(value || '')].filter(isDigit).join('');

export const formatCnpj = value => {
  const digits = cnpjDigits(value);
  if (digits.length !== 14) return value;
  return `${digits.slice(0, 2)}.${digits.slice(2, 5)}.${digits.slice(5, 8)}/${digits.slice(8, 12)}-${digits.slice(12)}`;
};

// Maiúsculas, sem acento, hífen e espaços colapsados, como o normalization.ts
// do Orth. Só compara textos da Receita; não interpreta o que alguém escreveu.
const COMBINING_MARKS_START = 0x300;
const COMBINING_MARKS_END = 0x36f;

const isCombiningMark = char => {
  const code = char.codePointAt(0);
  return code >= COMBINING_MARKS_START && code <= COMBINING_MARKS_END;
};

export const normalizeRegistryText = value =>
  [...String(value || '').normalize('NFD')]
    .filter(char => !isCombiningMark(char))
    .map(char => (char === '-' || char.trim() === '' ? ' ' : char))
    .join('')
    .toUpperCase()
    .split(' ')
    .filter(Boolean)
    .join(' ');

export const tradeNameToShow = company => {
  const tradeName = company?.trade_name?.trim();
  if (!tradeName) return null;
  const sameAsLegalName =
    normalizeRegistryText(tradeName) ===
    normalizeRegistryText(company?.legal_name);
  return sameAsLegalName ? null : tradeName;
};

export const isRegistryInactive = status =>
  Boolean(status?.trim()) && normalizeRegistryText(status) !== 'ATIVA';

// Qualificações da regra do dono (owner-policy.ts do Orth): tabela fechada.
// Fora dela, o texto aparece como veio do cadastro.
const QUALIFICATIONS = {
  'SOCIO ADMINISTRADOR': 'SOCIO_ADMINISTRADOR',
  SOCIO: 'SOCIO',
  TITULAR: 'TITULAR',
  'EMPRESARIO INDIVIDUAL': 'EMPRESARIO_INDIVIDUAL',
  PROPRIETARIO: 'PROPRIETARIO',
  'ACIONISTA CONTROLADOR': 'ACIONISTA_CONTROLADOR',
  ADMINISTRADOR: 'ADMINISTRADOR',
  DIRETOR: 'DIRETOR',
  PRESIDENTE: 'PRESIDENTE',
  CEO: 'CEO',
};

export const qualificationLabelKey = qualification => {
  const key = QUALIFICATIONS[normalizeRegistryText(qualification)];
  return key ? `PROSPECTING.RESEARCH.QUALIFICATIONS.${key}` : null;
};

const NO_DECISION_REASONS = [
  'no_qsa',
  'only_companies',
  'only_minors',
  'no_eligible_role',
  'public_entity',
];

export const noDecisionReasonKey = code => {
  const known = NO_DECISION_REASONS.includes(code);
  return `PROSPECTING.RESEARCH.NO_DECISION_REASON.${known ? code.toUpperCase() : 'UNKNOWN'}`;
};

export const confidencePercent = confidence =>
  confidence === null || confidence === undefined
    ? null
    : Math.round(Number(confidence) * 100);

const DATE_FORMAT = new Intl.DateTimeFormat('pt-BR', {
  timeZone: 'America/Sao_Paulo',
});

export const formatResearchDate = value => {
  const time = Date.parse(value || '');
  return Number.isFinite(time) ? DATE_FORMAT.format(new Date(time)) : null;
};

// Linha do decisor no card, por estado (ResultsTable.tsx do Orth). Devolve a
// chave do texto; com decisor, a tela mostra nome e cargo.
export const decisionLineKey = (research, { researchEnabled = true } = {}) => {
  const status = research?.decision_status || 'not_researched';
  const line = key => `PROSPECTING.RESEARCH.DECISION_LINE.${key}`;

  if (status === 'waiting_capacity') return line('WAITING_CAPACITY');
  if (['queued', 'researching'].includes(status)) return line('IN_PROGRESS');
  if (status === 'failed') return line('FAILED');
  if (research?.decision?.name) return null;
  if (status === 'possible') return line('POSSIBLE');
  if (['no_result', 'ambiguous', 'confirmed'].includes(status)) {
    return line('NOT_CONFIRMED');
  }
  if (status === 'blocked') return line('BLOCKED');
  return researchEnabled ? line('NOT_RESEARCHED') : line('DISABLED');
};

// Resposta atrasada não desfaz o que o evento ao vivo já trouxe
// (decision-research-state.ts do Orth). A ordem vem das datas do bloco.
const DECISION_FIELDS = [
  'decision_name',
  'decision_role',
  'decision_confidence',
  'decision_source_url',
  'decision_linkedin',
  'decision_instagram',
];

const researchStamp = research =>
  Math.max(
    Date.parse(research?.completed_at || '') || 0,
    Date.parse(research?.requested_at || '') || 0
  );

const isResearchSettled = research =>
  ['done', 'failed'].includes(researchPhase(research));

const keepsCurrentResearch = (current, incoming) => {
  if (!current) return false;
  if (!incoming) return true;
  const currentAt = researchStamp(current);
  const incomingAt = researchStamp(incoming);
  if (incomingAt < currentAt) return true;
  return (
    incomingAt === currentAt &&
    isResearchSettled(current) &&
    !isResearchSettled(incoming)
  );
};

export const mergeLeadResearch = (current, incoming) => {
  if (!keepsCurrentResearch(current?.research, incoming?.research)) {
    return incoming;
  }
  const kept = Object.fromEntries(
    DECISION_FIELDS.filter(field => field in current).map(field => [
      field,
      current[field],
    ])
  );
  return { ...incoming, ...kept, research: current.research };
};
