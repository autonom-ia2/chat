// Bloco de empresa e decisor no painel lateral do lead (#679), com o texto
// real. Portado de DecisionResearchPanel.test.tsx (Orth): Quem atende, bloco
// Empresa, copiar CNPJ, situação não ativa, refazer pesquisa, mensagens de
// bloqueio e ausência de pesquisa.
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import LeadDetailResearch from '../../components/search/LeadDetailResearch.vue';
import {
  notResearched,
  queuedResearch,
  researchBlock,
  researchCompany,
} from '../support/researchFixtures';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();

const confirmation = { answer: true, calls: 0, props: null };

const ConfirmModalStub = {
  name: 'ConfirmModal',
  props: ['title', 'description', 'confirmLabel', 'cancelLabel'],
  methods: {
    showConfirmation() {
      confirmation.calls += 1;
      confirmation.props = { ...this.$props };
      return Promise.resolve(confirmation.answer);
    },
  },
  template: '<div class="confirm-modal-stub" />',
};

const mountPanel = (research, props = {}, lead = {}) =>
  mount(LeadDetailResearch, {
    props: {
      lead: { id: 101, name: 'Padaria Sol', research, ...lead },
      researchEnabled: true,
      canManage: true,
      requesting: false,
      ...props,
    },
    global: { stubs: { ConfirmModal: ConfirmModalStub } },
  });

const section = (wrapper, name) =>
  wrapper.find(`[data-test="research-${name}"]`);
const actionButton = wrapper => wrapper.find('[data-test="research-action"]');

describe('LeadDetailResearch · Quem atende', () => {
  it('lista os sócios com o vínculo de cada um, na ordem da regra do dono', () => {
    const owners = section(mountPanel(researchBlock()), 'owners');

    expect(owners.find('h4').text()).toBe('Quem atende');
    expect(
      owners
        .findAll('[data-test="research-owner-line"]')
        .map(item => item.text())
    ).toEqual([
      'JOAO DA SILVA · Sócio-administrador',
      'MARIA DA SILVA · Sócio',
    ]);
  });

  // Usar como contato (#680): um sócio vira o decisor e o contato do lead.
  it('cada sócio que não é o decisor tem Usar como contato; o decisor que é o contato aparece como contato atual', () => {
    const owners = section(
      mountPanel(researchBlock(), {}, { contact_name: 'JOAO DA SILVA' }),
      'owners'
    );
    const [joao, maria] = owners.findAll('li');

    expect(joao.text()).toContain('Contato atual');
    expect(joao.find('button').exists()).toBe(false);
    const adopt = maria.find('button');
    expect(adopt.text()).toBe('Usar como contato');
    expect(adopt.attributes('aria-label')).toBe(
      'Usar MARIA DA SILVA como contato'
    );
    expect(adopt.element.disabled).toBe(false);
  });

  it('o contato é reconhecido sem diferença de caixa nem espaço', () => {
    const owners = section(
      mountPanel(
        researchBlock({
          decision: { name: ' Maria da Silva ', role: 'SOCIO' },
        }),
        {},
        { contact_name: 'maria da silva ' }
      ),
      'owners'
    );
    const [joao, maria] = owners.findAll('li');

    expect(maria.text()).toContain('Contato atual');
    expect(joao.find('button').text()).toBe('Usar como contato');
  });

  // O contato do lead pode ser de outro negócio com o mesmo telefone, ou um
  // contato que o usuário já tinha: o selo não afirma o que não aconteceu.
  it('decisor que não é o contato do lead leva o selo Decisor, nunca Contato atual', () => {
    const owners = section(
      mountPanel(researchBlock(), {}, { contact_name: 'Oficina Alpha' }),
      'owners'
    );
    const [joao, maria] = owners.findAll('li');

    expect(joao.text()).toContain('Decisor');
    expect(joao.text()).not.toContain('Contato atual');
    expect(joao.find('button').exists()).toBe(false);
    expect(maria.find('button').text()).toBe('Usar como contato');
    expect(owners.text()).not.toContain('Contato atual');
  });

  it('lead ainda sem contato: o decisor leva o selo Decisor', () => {
    const owners = section(mountPanel(researchBlock()), 'owners');

    expect(owners.findAll('li')[0].text()).toContain('Decisor');
    expect(owners.text()).not.toContain('Contato atual');
  });

  it('sem decisor, todos os sócios podem virar contato', () => {
    const owners = section(
      mountPanel(
        researchBlock({ decision: null, decision_status: 'possible' })
      ),
      'owners'
    );

    expect(owners.findAll('button')).toHaveLength(2);
    expect(owners.text()).not.toContain('Contato atual');
  });

  it('clicar avisa quem abriu com o sócio escolhido', async () => {
    const wrapper = mountPanel(researchBlock());

    await section(wrapper, 'owners')
      .findAll('li')[1]
      .find('button')
      .trigger('click');

    expect(wrapper.emitted('adoptOwner')).toEqual([
      [{ name: 'MARIA DA SILVA', qualification: 'SOCIO' }],
    ]);
  });

  it('enquanto salva, o botão do sócio diz Salvando e nenhum outro responde', () => {
    const owners = section(
      mountPanel(researchBlock({ decision: null }), {
        adoptingOwnerName: 'MARIA DA SILVA',
      }),
      'owners'
    );
    const buttons = owners.findAll('button');

    expect(buttons.map(button => button.text())).toEqual([
      'Usar como contato',
      'Salvando…',
    ]);
    expect(buttons.every(button => button.element.disabled)).toBe(true);
  });

  it('quem só vê não tem Usar como contato', () => {
    const owners = section(
      mountPanel(researchBlock(), { canManage: false }),
      'owners'
    );

    expect(owners.findAll('button')).toHaveLength(0);
  });

  it('não mostra a fonte interna do dado', () => {
    const wrapper = mountPanel(researchBlock());

    expect(wrapper.text()).not.toContain('OpenCNPJ');
  });

  it('sem sócios, não há bloco Quem atende', () => {
    const wrapper = mountPanel(
      researchBlock({
        owners: [],
        decision: null,
        decision_status: 'no_result',
      })
    );

    expect(section(wrapper, 'owners').exists()).toBe(false);
  });
});

describe('LeadDetailResearch · bloco Empresa', () => {
  beforeEach(() => {
    useAlert.mockClear();
  });

  it('mostra razão social, nome fantasia, CNPJ e situação, e copia o CNPJ', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });
    const wrapper = mountPanel(researchBlock());
    const company = section(wrapper, 'company');

    expect(company.find('h4').text()).toBe('Empresa');
    expect(company.text()).toContain('Razão social');
    expect(company.text()).toContain('Padaria Sol Alimentos Ltda.');
    expect(company.text()).toContain('Nome fantasia');
    expect(company.text()).toContain('Padaria Sol');
    expect(company.text()).toContain('CNPJ');
    expect(company.text()).toContain('ATIVA · Registro PR');
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);

    const copy = company.find(
      'button[aria-label="Copiar CNPJ 12.345.678/0001-95"]'
    );
    expect(copy.text()).toBe('12.345.678/0001-95 · copiar');
    await copy.trigger('click');
    await flushPromises();

    expect(writeText).toHaveBeenCalledWith('12345678000195');
    expect(useAlert).toHaveBeenCalledWith('CNPJ copiado.');
  });

  it('avisa quando não consegue copiar', async () => {
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error('negado')) },
    });
    const wrapper = mountPanel(researchBlock());

    await section(wrapper, 'company').find('button').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Não foi possível copiar o CNPJ.');
  });

  it('omite nome fantasia quando é igual à razão social', () => {
    const wrapper = mountPanel(
      researchBlock({
        company: researchCompany({
          legal_name: 'Empresa Repetida Ltda.',
          trade_name: '  Empresa Repetida Ltda.  ',
        }),
      })
    );

    expect(section(wrapper, 'company').text()).not.toContain('Nome fantasia');
  });

  it('mostra situação sem sufixo de registro quando a UF não existe', () => {
    const wrapper = mountPanel(
      researchBlock({
        company: researchCompany({ registration_state: null }),
      })
    );
    const company = section(wrapper, 'company');

    expect(company.find('[data-test="research-registration"]').text()).toBe(
      'ATIVA'
    );
    expect(company.text()).not.toContain('Registro');
  });

  it('destaca situação não ativa na linha e mostra o alerta', () => {
    const wrapper = mountPanel(
      researchBlock({
        company: researchCompany({ registration_status: 'BAIXADA' }),
      })
    );
    const status = wrapper.find('[data-test="research-registration"]');

    expect(status.text()).toBe('BAIXADA · Registro PR');
    expect(status.classes().join(' ')).toContain('amber');
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'Empresa com situação BAIXADA na Receita'
    );
  });

  it('não mostra o bloco Empresa sem CNPJ nem razão social', () => {
    const wrapper = mountPanel(
      researchBlock({
        company: researchCompany({ cnpj: null, legal_name: null }),
      })
    );

    expect(section(wrapper, 'company').exists()).toBe(false);
    expect(wrapper.find('button[aria-label^="Copiar CNPJ"]').exists()).toBe(
      false
    );
  });
});

describe('LeadDetailResearch · botão e confirmação', () => {
  beforeEach(() => {
    confirmation.answer = true;
    confirmation.calls = 0;
  });

  it('lead nunca pesquisado: Pesquisar, sem confirmação e sem forçar', async () => {
    const wrapper = mountPanel(notResearched());

    expect(actionButton(wrapper).text()).toBe('Pesquisar');
    await actionButton(wrapper).trigger('click');
    await flushPromises();

    expect(confirmation.calls).toBe(0);
    expect(wrapper.emitted('research')).toEqual([[{ force: false }]]);
  });

  it('lead pesquisado: Verificar novamente pergunta Refazer pesquisa? e força', async () => {
    const wrapper = mountPanel(researchBlock());

    expect(actionButton(wrapper).text()).toBe('Verificar novamente');
    await actionButton(wrapper).trigger('click');
    await flushPromises();

    expect(confirmation.calls).toBe(1);
    expect(confirmation.props.title).toBe('Refazer pesquisa?');
    expect(confirmation.props.confirmLabel).toBe('Refazer pesquisa');
    expect(confirmation.props.description).not.toContain('crédito');
    expect(wrapper.emitted('research')).toEqual([[{ force: true }]]);
  });

  it('cancelar a confirmação não pede nada', async () => {
    confirmation.answer = false;
    const wrapper = mountPanel(researchBlock());

    await actionButton(wrapper).trigger('click');
    await flushPromises();

    expect(wrapper.emitted('research')).toBeUndefined();
  });

  it.each([
    ['na fila', queuedResearch(), {}],
    ['em pesquisa', queuedResearch({ company_status: 'researching' }), {}],
    [
      'aguardando capacidade',
      queuedResearch({ decision_status: 'waiting_capacity' }),
      {},
    ],
    ['pedido saindo', notResearched(), { requesting: true }],
  ])('%s: Pesquisando…, desabilitado', (_label, research, props) => {
    const wrapper = mountPanel(research, props);

    expect(actionButton(wrapper).text()).toBe('Pesquisando…');
    expect(actionButton(wrapper).element.disabled).toBe(true);
    expect(wrapper.text()).toContain(
      'A pesquisa está confirmando a empresa e o quadro de sócios.'
    );
  });

  it('pesquisa desligada: botão desabilitado e aviso', () => {
    const wrapper = mountPanel(notResearched(), { researchEnabled: false });

    expect(actionButton(wrapper).element.disabled).toBe(true);
    expect(wrapper.text()).toContain(
      'A pesquisa de empresa e decisor está desligada nesta conta.'
    );
  });

  it('quem só vê não tem o botão', () => {
    const wrapper = mountPanel(researchBlock(), { canManage: false });

    expect(actionButton(wrapper).exists()).toBe(false);
  });
});

describe('LeadDetailResearch · estados e mensagens', () => {
  it('mostra os selos e a data da pesquisa', () => {
    const wrapper = mountPanel(researchBlock());

    expect(wrapper.find('[data-research-badge="company"]').text()).toBe(
      'Empresa: Confirmado'
    );
    expect(wrapper.find('[data-research-badge="decision"]').text()).toBe(
      'Decisor: Confirmado'
    );
    expect(wrapper.text()).toContain('Pesquisa atualizada em 20/09/2026');
  });

  it('resultado reutilizado mostra a data do cadastro guardado', () => {
    const wrapper = mountPanel(researchBlock({ reused: true }));

    expect(wrapper.text()).toContain('Resultado reutilizado em 20/09/2026');
  });

  it('falha técnica: a última pesquisa não pôde ser concluída', () => {
    const wrapper = mountPanel(
      researchBlock({ company_status: 'failed', error_code: 'timeout' })
    );

    expect(wrapper.text()).toContain(
      'A última pesquisa não pôde ser concluída.'
    );
    expect(wrapper.text()).not.toContain('timeout');
  });

  it('bloqueada: explica sem mostrar código interno', () => {
    const wrapper = mountPanel(
      notResearched({
        company_status: 'blocked',
        error_code: 'research_disabled',
      })
    );

    expect(wrapper.text()).toContain('A pesquisa deste lead foi bloqueada.');
    expect(wrapper.text()).not.toContain('research_disabled');
  });

  it('nunca pesquisado: diz que não houve pesquisa', () => {
    const wrapper = mountPanel(notResearched());

    expect(wrapper.text()).toContain(
      'Nenhuma pesquisa de empresa e decisor feita para este lead.'
    );
  });

  it.each([
    ['no_qsa', 'A Receita não traz quadro de sócios para esta empresa.'],
    [
      'only_companies',
      'Os sócios desta empresa são outras empresas, não pessoas.',
    ],
    [
      'only_minors',
      'O quadro de sócios só tem menores de idade, que não são mostrados.',
    ],
    [
      'no_eligible_role',
      'Nenhum sócio com vínculo de dono ou de comando (sócio, titular, administrador, diretor).',
    ],
    ['public_entity', 'É um órgão público: não há dono a indicar.'],
    [
      'company_not_found',
      'Nenhuma empresa do cadastro público bate com este lead (nome, telefone, cidade e UF).',
    ],
    [
      'company_ambiguous',
      'Mais de uma empresa do cadastro público combina com este lead; nenhuma foi escolhida.',
    ],
    [
      'explicit_role_not_supported',
      'A pesquisa pelo cadastro público só indica o proprietário; o tipo de decisor pedido ainda não tem pesquisa.',
    ],
    ['codigo_novo', 'Nenhum decisor foi confirmado no cadastro público.'],
  ])('sem decisor pelo motivo %s', (code, text) => {
    const wrapper = mountPanel(
      researchBlock({
        decision_status: 'no_result',
        decision: null,
        owners: [],
        no_decision_reason: code,
      })
    );

    expect(wrapper.find('[data-test="research-no-decision"]').text()).toBe(
      text
    );
  });

  it('com decisor, não mostra motivo de ausência', () => {
    const wrapper = mountPanel(researchBlock());

    expect(wrapper.find('[data-test="research-no-decision"]').exists()).toBe(
      false
    );
  });

  it('nenhum texto de crédito ou cobrança', () => {
    const text = mountPanel(researchBlock({ reused: true }))
      .text()
      .toLowerCase();

    expect(text).not.toContain('crédito');
    expect(text).not.toContain('cobr');
  });
});
