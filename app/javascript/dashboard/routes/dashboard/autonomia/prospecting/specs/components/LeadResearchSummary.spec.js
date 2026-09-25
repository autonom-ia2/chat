// Selos Empresa e Decisor no card do lead (#679), com o texto real. Portado de
// ResultsTable.tsx (linha do decisor por estado, confiança, data e
// "resultado reutilizado") e ResearchStatePresentation.tsx, no Orth.
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import LeadResearchSummary from '../../components/search/LeadResearchSummary.vue';
import { RESEARCH_STATES } from '../../utils/leadResearch';
import {
  notResearched,
  queuedResearch,
  researchBlock,
  researchDecision,
} from '../support/researchFixtures';

withFullI18n();

const STATE_TEXT = {
  not_researched: 'Não pesquisado',
  queued: 'Na fila',
  researching: 'Em pesquisa',
  waiting_capacity: 'Aguardando capacidade',
  confirmed: 'Confirmado',
  possible: 'Possível',
  ambiguous: 'Ambíguo',
  no_result: 'Nenhum resultado',
  failed: 'Falha técnica',
  blocked: 'Bloqueado',
};

const mountSummary = (research, props = {}) =>
  mount(LeadResearchSummary, {
    props: { research, researchEnabled: true, ...props },
  });

const badge = (wrapper, kind) =>
  wrapper.find(`[data-research-badge="${kind}"]`);
const decisionLine = wrapper =>
  wrapper.find('[data-test="lead-research-decision"]').text();
const metaLine = wrapper => wrapper.find('[data-test="lead-research-meta"]');

describe('LeadResearchSummary · selos', () => {
  it.each(RESEARCH_STATES)('selo Empresa e Decisor no estado %s', status => {
    const wrapper = mountSummary(
      researchBlock({
        company_status: status,
        decision_status: status,
        decision: null,
      })
    );

    expect(badge(wrapper, 'company').text()).toBe(
      `Empresa: ${STATE_TEXT[status]}`
    );
    expect(badge(wrapper, 'decision').text()).toBe(
      `Decisor: ${STATE_TEXT[status]}`
    );
    expect(badge(wrapper, 'company').attributes('data-state')).toBe(status);
  });

  it('empresa e decisor podem estar em estados diferentes', () => {
    const wrapper = mountSummary(
      researchBlock({
        company_status: 'confirmed',
        decision_status: 'no_result',
      })
    );

    expect(badge(wrapper, 'company').text()).toBe('Empresa: Confirmado');
    expect(badge(wrapper, 'decision').text()).toBe('Decisor: Nenhum resultado');
  });

  it('em pesquisa o ícone gira; parado não', () => {
    const running = mountSummary(
      queuedResearch({ company_status: 'researching' })
    );
    const done = mountSummary(researchBlock());

    expect(badge(running, 'company').find('.animate-spin').exists()).toBe(true);
    expect(badge(done, 'company').find('.animate-spin').exists()).toBe(false);
  });

  it('avisa leitor de tela quando o estado muda', () => {
    const wrapper = mountSummary(researchBlock());
    expect(
      wrapper.find('[data-test="lead-research"]').attributes('aria-live')
    ).toBe('polite');
  });
});

describe('LeadResearchSummary · linha do decisor', () => {
  it('decisor confirmado: nome · cargo, confiança, data de verificação', () => {
    const wrapper = mountSummary(researchBlock());

    expect(decisionLine(wrapper)).toBe(
      'Decisor: JOAO DA SILVA · Sócio-administrador'
    );
    expect(metaLine(wrapper).text()).toBe(
      '94% de confiança · verificado em 20/09/2026'
    );
  });

  it('resultado reutilizado aparece junto da data', () => {
    const wrapper = mountSummary(researchBlock({ reused: true }));

    expect(metaLine(wrapper).text()).toBe(
      '94% de confiança · verificado em 20/09/2026 · resultado reutilizado'
    );
  });

  it('cargo fora da tabela aparece como veio do cadastro', () => {
    const wrapper = mountSummary(
      researchBlock({ decision: researchDecision({ role: 'PROCURADOR' }) })
    );

    expect(decisionLine(wrapper)).toBe('Decisor: JOAO DA SILVA · PROCURADOR');
  });

  it('sem confiança não inventa porcentagem', () => {
    const wrapper = mountSummary(
      researchBlock({ decision: researchDecision({ confidence: null }) })
    );

    expect(metaLine(wrapper).text()).toBe('verificado em 20/09/2026');
  });

  it.each([
    [queuedResearch(), 'Pesquisa em andamento'],
    [
      queuedResearch({ decision_status: 'researching' }),
      'Pesquisa em andamento',
    ],
    [
      queuedResearch({ decision_status: 'waiting_capacity' }),
      'Aguardando capacidade · retomada automática',
    ],
    [
      researchBlock({ decision_status: 'failed', decision: null }),
      'Pesquisa não concluída',
    ],
    [
      researchBlock({ decision_status: 'possible', decision: null }),
      'Possível decisor',
    ],
    [
      researchBlock({ decision_status: 'no_result', decision: null }),
      'Não confirmado',
    ],
    [
      researchBlock({ decision_status: 'ambiguous', decision: null }),
      'Não confirmado',
    ],
    [
      researchBlock({ decision_status: 'blocked', decision: null }),
      'Pesquisa bloqueada',
    ],
    [notResearched(), 'Não pesquisado'],
  ])('estado %# mostra "%s"', (research, text) => {
    const wrapper = mountSummary(research);

    expect(decisionLine(wrapper)).toBe(`Decisor: ${text}`);
  });

  it('pesquisa desligada e lead nunca pesquisado: Pesquisa desligada', () => {
    const wrapper = mountSummary(notResearched(), { researchEnabled: false });

    expect(decisionLine(wrapper)).toBe('Decisor: Pesquisa desligada');
  });

  it('em andamento não mostra confiança nem data antigas', () => {
    const wrapper = mountSummary(
      researchBlock({ company_status: 'queued', decision_status: 'queued' })
    );

    expect(decisionLine(wrapper)).toBe('Decisor: Pesquisa em andamento');
    expect(metaLine(wrapper).exists()).toBe(false);
  });

  it('nenhum texto de crédito ou cobrança', () => {
    const wrapper = mountSummary(researchBlock({ reused: true }));

    expect(wrapper.text().toLowerCase()).not.toContain('crédito');
    expect(wrapper.text().toLowerCase()).not.toContain('cobr');
  });
});
