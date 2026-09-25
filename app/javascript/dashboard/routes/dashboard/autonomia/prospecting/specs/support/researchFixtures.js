// Bloco research do lead no contrato da E3 (#679): o que a API e o evento
// prospecting.lead.updated trazem. A frente D trabalha contra estas fixtures.
export const researchCompany = (extra = {}) => ({
  cnpj: '12345678000195',
  legal_name: 'Padaria Sol Alimentos Ltda.',
  trade_name: 'Padaria Sol',
  registration_status: 'ATIVA',
  registration_state: 'PR',
  legal_nature_text: 'Sociedade Empresária Limitada',
  ...extra,
});

export const researchDecision = (extra = {}) => ({
  name: 'JOAO DA SILVA',
  role: 'SOCIO ADMINISTRADOR',
  confidence: 0.94,
  source: 'OpenCNPJ',
  verified_at: '2026-09-20T15:00:00Z',
  ...extra,
});

// Pesquisa concluída: empresa e decisor confirmados.
export const researchBlock = (extra = {}) => ({
  company_status: 'confirmed',
  decision_status: 'confirmed',
  reused: false,
  verified_at: '2026-09-20T15:00:00Z',
  requested_at: '2026-09-20T14:59:00Z',
  completed_at: '2026-09-20T15:00:00Z',
  error_code: null,
  no_decision_reason: null,
  company: researchCompany(),
  owners: [
    { name: 'JOAO DA SILVA', qualification: 'SOCIO ADMINISTRADOR' },
    { name: 'MARIA DA SILVA', qualification: 'SOCIO' },
  ],
  decision: researchDecision(),
  ...extra,
});

// Lead que nunca foi pesquisado.
export const notResearched = (extra = {}) => ({
  company_status: 'not_researched',
  decision_status: 'not_researched',
  reused: false,
  verified_at: null,
  requested_at: null,
  completed_at: null,
  error_code: null,
  no_decision_reason: null,
  company: null,
  owners: [],
  decision: null,
  ...extra,
});

// Pesquisa pedida, ainda sem resultado.
export const queuedResearch = (extra = {}) =>
  notResearched({
    company_status: 'queued',
    decision_status: 'queued',
    requested_at: '2026-09-25T12:00:00Z',
    ...extra,
  });
