// Regras da tela para a pesquisa de empresa e decisor (#679). Portado de
// ResearchStatePresentation.test.tsx, decision-research-state.test.ts e dos
// casos do bloco Empresa de DecisionResearchPanel.test.tsx, no Orth.
import {
  RESEARCH_STATES,
  confidencePercent,
  formatCnpj,
  cnpjDigits,
  formatResearchDate,
  isRegistryInactive,
  mergeLeadResearch,
  noDecisionReasonKey,
  qualificationLabelKey,
  researchPhase,
  researchProgress,
  researchStatePresentation,
  tradeNameToShow,
} from '../../utils/leadResearch';
import {
  notResearched,
  queuedResearch,
  researchBlock,
} from '../support/researchFixtures';

describe('leadResearch · estados', () => {
  it('cobre os 10 estados com texto próprio e terminalidade honesta', () => {
    const keys = RESEARCH_STATES.map(status => {
      const presentation = researchStatePresentation(status);
      expect(presentation.labelKey).toBeTruthy();
      expect(typeof presentation.terminal).toBe('boolean');
      return presentation.labelKey;
    });

    expect(RESEARCH_STATES).toHaveLength(10);
    expect(new Set(keys).size).toBe(10);
    expect(researchStatePresentation('no_result').labelKey).not.toBe(
      researchStatePresentation('not_researched').labelKey
    );
    expect(researchStatePresentation('waiting_capacity').terminal).toBe(false);
    expect(researchStatePresentation('failed').terminal).toBe(true);
  });

  it('não tem estado de cobrança (fora do escopo por decisão)', () => {
    expect(RESEARCH_STATES).not.toContain('reconciling');
    expect(RESEARCH_STATES).not.toContain('insufficient_credits');
  });

  it('estado desconhecido cai em Não pesquisado, sem quebrar a tela', () => {
    expect(researchStatePresentation('outro').labelKey).toBe(
      researchStatePresentation('not_researched').labelKey
    );
  });
});

describe('leadResearch · fase do lead e progresso', () => {
  const withResearch = research => ({ id: 1, research });

  it.each([
    [notResearched(), 'none'],
    [queuedResearch(), 'queued'],
    [queuedResearch({ company_status: 'researching' }), 'running'],
    [queuedResearch({ decision_status: 'waiting_capacity' }), 'running'],
    [researchBlock(), 'done'],
    [researchBlock({ decision_status: 'no_result', decision: null }), 'done'],
    [researchBlock({ company_status: 'failed' }), 'failed'],
    [null, 'none'],
  ])('fase de %o é %s', (research, phase) => {
    expect(researchPhase(research)).toBe(phase);
  });

  it('conta pelos leads, que chegam ao vivo pelo evento', () => {
    const leads = [
      withResearch(researchBlock()),
      withResearch(researchBlock({ company_status: 'failed' })),
      withResearch(queuedResearch({ company_status: 'researching' })),
      withResearch(queuedResearch()),
      withResearch(notResearched()),
    ];

    expect(researchProgress(leads, null)).toEqual({
      total: 4,
      done: 1,
      running: 1,
      queued: 1,
      failed: 1,
    });
  });

  it('sem pesquisa em nenhum lead, não há progresso', () => {
    expect(researchProgress([withResearch(notResearched())], null)).toBeNull();
    expect(
      researchProgress([], { total: 0, done: 0, running: 0, queued: 0 })
    ).toBeNull();
  });

  it('lead sem bloco research usa o progresso que a busca trouxe', () => {
    const server = { total: 20, done: 5, running: 2, queued: 13, failed: 0 };

    expect(researchProgress([{ id: 1 }], server)).toEqual(server);
  });
});

describe('leadResearch · bloco Empresa', () => {
  it('formata o CNPJ e copia só os dígitos', () => {
    expect(formatCnpj('12345678000195')).toBe('12.345.678/0001-95');
    expect(formatCnpj('12.345.678/0001-95')).toBe('12.345.678/0001-95');
    expect(cnpjDigits('12.345.678/0001-95')).toBe('12345678000195');
    expect(formatCnpj('123')).toBe('123');
  });

  it('omite nome fantasia igual à razão social, com espaço, caixa ou acento', () => {
    expect(
      tradeNameToShow({
        legal_name: 'Empresa Repetida Ltda.',
        trade_name: '  Empresa Repetida Ltda.  ',
      })
    ).toBeNull();
    expect(
      tradeNameToShow({
        legal_name: 'CAFÉ DA ESQUINA',
        trade_name: 'Cafe da  esquina',
      })
    ).toBeNull();
    expect(
      tradeNameToShow({
        legal_name: 'Clínica Exemplo Serviços Ltda.',
        trade_name: 'Clínica Exemplo',
      })
    ).toBe('Clínica Exemplo');
    expect(tradeNameToShow({ legal_name: 'X', trade_name: null })).toBeNull();
  });

  it('só alerta situação diferente de ATIVA', () => {
    expect(isRegistryInactive('ATIVA')).toBe(false);
    expect(isRegistryInactive(' ativa ')).toBe(false);
    expect(isRegistryInactive('BAIXADA')).toBe(true);
    expect(isRegistryInactive('INAPTA')).toBe(true);
    expect(isRegistryInactive(null)).toBe(false);
  });

  it('dá texto à qualificação conhecida e mantém a desconhecida', () => {
    expect(qualificationLabelKey('SOCIO ADMINISTRADOR')).toBe(
      'PROSPECTING.RESEARCH.QUALIFICATIONS.SOCIO_ADMINISTRADOR'
    );
    expect(qualificationLabelKey('Sócio-Administrador')).toBe(
      'PROSPECTING.RESEARCH.QUALIFICATIONS.SOCIO_ADMINISTRADOR'
    );
    expect(qualificationLabelKey('PROCURADOR')).toBeNull();
  });
});

describe('leadResearch · motivo sem decisor, confiança e data', () => {
  it.each([
    'no_qsa',
    'only_companies',
    'only_minors',
    'no_eligible_role',
    'public_entity',
  ])('motivo %s tem texto próprio', code => {
    expect(noDecisionReasonKey(code)).toBe(
      `PROSPECTING.RESEARCH.NO_DECISION_REASON.${code.toUpperCase()}`
    );
  });

  it('motivo desconhecido ou ausente usa o texto geral', () => {
    expect(noDecisionReasonKey('outro_codigo')).toBe(
      'PROSPECTING.RESEARCH.NO_DECISION_REASON.UNKNOWN'
    );
    expect(noDecisionReasonKey(null)).toBe(
      'PROSPECTING.RESEARCH.NO_DECISION_REASON.UNKNOWN'
    );
  });

  it('confiança em porcentagem, nunca inventada', () => {
    expect(confidencePercent(0.94)).toBe(94);
    expect(confidencePercent(0.555)).toBe(56);
    expect(confidencePercent(null)).toBeNull();
    expect(confidencePercent(undefined)).toBeNull();
  });

  it('data no fuso de Brasília; data inválida não aparece', () => {
    expect(formatResearchDate('2026-09-20T15:00:00Z')).toBe('20/09/2026');
    expect(formatResearchDate('2026-09-21T01:00:00Z')).toBe('20/09/2026');
    expect(formatResearchDate('não é data')).toBeNull();
    expect(formatResearchDate(null)).toBeNull();
  });
});

// decision-research-state.test.ts: resposta atrasada não desfaz o que o
// evento ao vivo já trouxe.
describe('leadResearch · troca do lead sem regredir a pesquisa', () => {
  const lead = (research, extra = {}) => ({
    id: 1,
    name: 'Empresa',
    decision_name: research?.decision?.name || null,
    research,
    ...extra,
  });

  it('mantém o resultado final quando uma resposta mais antiga chega depois', () => {
    const current = lead(
      researchBlock({
        requested_at: '2026-07-22T12:00:00Z',
        completed_at: '2026-07-22T12:00:02Z',
      }),
      { enriched_email: 'a@b.com' }
    );
    const delayed = lead(
      queuedResearch({ requested_at: '2026-07-22T12:00:01Z' }),
      { decision_name: null, website: 'https://novo.com.br' }
    );

    const merged = mergeLeadResearch(current, delayed);

    expect(merged.research.decision_status).toBe('confirmed');
    expect(merged.decision_name).toBe('JOAO DA SILVA');
    expect(merged.website).toBe('https://novo.com.br');
  });

  it('aceita a projeção mais nova de outra pesquisa', () => {
    const current = lead(
      queuedResearch({ requested_at: '2026-07-22T12:00:01Z' })
    );
    const fresh = lead(
      researchBlock({
        requested_at: '2026-07-22T12:00:01Z',
        completed_at: '2026-07-22T12:00:02Z',
      })
    );

    expect(mergeLeadResearch(current, fresh).decision_name).toBe(
      'JOAO DA SILVA'
    );
  });

  it('não regride estado final quando as datas são iguais', () => {
    const at = '2026-07-22T12:00:01Z';
    const current = lead(researchBlock({ requested_at: at, completed_at: at }));
    const delayed = lead(
      queuedResearch({ requested_at: at, company_status: 'researching' }),
      { decision_name: null }
    );

    const merged = mergeLeadResearch(current, delayed);

    expect(merged.research.company_status).toBe('confirmed');
    expect(merged.decision_name).toBe('JOAO DA SILVA');
  });

  it('verificar novamente (pedido mais novo) troca o resultado antigo pela fila', () => {
    const current = lead(
      researchBlock({ completed_at: '2026-09-20T15:00:00Z' })
    );
    const retry = lead(
      researchBlock({
        company_status: 'queued',
        decision_status: 'queued',
        requested_at: '2026-09-25T12:00:00Z',
      })
    );

    expect(mergeLeadResearch(current, retry).research.company_status).toBe(
      'queued'
    );
  });

  it('resposta sem bloco research não apaga a pesquisa da tela', () => {
    const current = lead(researchBlock());
    const merged = mergeLeadResearch(current, {
      id: 1,
      name: 'Empresa',
      crm_card_id: 7,
    });

    expect(merged.research.decision_status).toBe('confirmed');
    expect(merged.crm_card_id).toBe(7);
  });
});
