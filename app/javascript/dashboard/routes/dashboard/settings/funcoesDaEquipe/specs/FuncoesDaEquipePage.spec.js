import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import FuncoesDaEquipePage from '../FuncoesDaEquipePage.vue';

// #2308, especificação 5.A e 5.E: a lista nova. Faixa só com Pessoas, erro nunca vira lista vazia, função travada
// sem ações, as fixas, a gaveta de pessoas e o apagar com destino.
const { routerPush, validityCheck } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  validityCheck: vi.fn(),
}));
vi.mock('dashboard/api/auth', () => ({ default: { validityCheck } }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: routerPush }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const ATENDENTE = {
  id: 1,
  name: 'Atendente',
  description: 'Quem atende o WhatsApp no dia a dia.',
  permissions: [
    'conversation_participating_manage',
    'conversation_unassigned_manage',
    'contact_view',
    'crm_view',
    'crm_manage_cards',
    'crm_move_cards',
  ],
};
const FINANCEIRO = {
  id: 2,
  name: 'Financeiro',
  permissions: ['financial_view', 'report_manage'],
};
const AGENTES = [
  { id: 10, name: 'Ana', role: 'agent', custom_role_id: 1 },
  { id: 11, name: 'Bia', role: 'agent', custom_role_id: null },
  { id: 12, name: 'Caio', role: 'agent', custom_role_id: null },
  { id: 13, name: 'Duda', role: 'administrator', custom_role_id: null },
];

// Carla: não administradora, monta funções e tem as chaves do Atendente; Pessoas só quando o teste pede.
const recarregar = vi.fn();

const montar = async ({
  funcoes = [ATENDENTE, FINANCEIRO],
  admin = true,
  pessoas = false,
  falha = false,
  plano = true,
  apagar = vi.fn(),
  lentes = false,
  pessoasDaConta = vi.fn(),
} = {}) => {
  const permissoes = [
    'custom_role_manage',
    ...ATENDENTE.permissions,
    ...(pessoas ? ['people_manage'] : []),
  ];
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentRole: () => (admin ? 'administrator' : 'agent'),
      getCurrentCustomRoleId: () => (admin ? null : 99),
      getCurrentUser: () => ({
        id: 50,
        accounts: [{ id: 1, permissions: admin ? [] : permissoes }],
      }),
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        flag === 'crm_numeros_lentes' ? lentes : plano,
      'customRole/getCustomRoles': () => funcoes,
      'customRole/getUIFlags': () => ({
        fetchingList: false,
        fetchingListFailed: falha,
      }),
      'agents/getAgents': () => AGENTES,
    },
    actions: {
      'customRole/getCustomRole': recarregar,
      'customRole/deleteCustomRole': apagar,
      'agents/get': pessoasDaConta,
    },
  });
  const wrapper = mount(FuncoesDaEquipePage, {
    attachTo: document.body,
    global: {
      plugins: [
        store,
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      stubs: {
        Avatar: true,
        GavetaDaFuncao: true,
        PaywallDasFuncoes: { template: '<div data-paywall />' },
        TeleportWithDirection: { template: '<div><slot /></div>' },
      },
    },
  });
  await flushPromises();
  return wrapper;
};

afterEach(() => {
  document.body.innerHTML = '';
  vi.clearAllMocks();
});

const pedirApagar = async cartao => {
  await cartao.find('[data-mais]').trigger('click');
  await cartao.find('[data-acao="apagar"]').trigger('click');
};
const dialogo = wrapper => wrapper.find('dialog');

describe('Funções da equipe: lista', () => {
  it('mostra título, contagem, cartões com a frase curta e as fixas', async () => {
    const wrapper = await montar();

    expect(wrapper.find('h1').text()).toBe('Funções da equipe');
    expect(wrapper.find('[data-contagem]').text()).toBe(
      '2 funções criadas · 1 pessoa com função'
    );
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');
    expect(atendente.find('[data-frase]').text()).toBe(
      'Atende as próprias conversas e pega as novas que estão sem ninguém. Cria e move as vendas em andamento. Só olha os contatos.'
    );
    expect(atendente.text()).toContain('1 pessoa');
    expect(wrapper.find('[data-fixa-admin]').text()).toContain(
      '1 pessoa · não muda'
    );
    expect(wrapper.find('[data-fixa-sem-funcao]').text()).toContain(
      'Mexe em todos os contatos e nas respostas prontas.'
    );
    expect(wrapper.find('[data-fixa-sem-funcao]').text()).toContain(
      '2 pessoas · não muda'
    );
  });

  it('a faixa de quem está sem função só aparece com Pessoas', async () => {
    const admin = await montar();
    const faixa = admin.find('[data-faixa-sem-funcao]');
    expect(faixa.attributes('role')).toBe('status');
    expect(faixa.text()).toContain('2 pessoas estão sem função.');
    expect(faixa.text()).toContain('2 pessoas sem função.');

    const comPessoas = await montar({ admin: false, pessoas: true });
    expect(comPessoas.find('[data-faixa-sem-funcao]').exists()).toBe(true);

    const soMontaFuncoes = await montar({ admin: false });
    expect(soMontaFuncoes.find('[data-faixa-sem-funcao]').exists()).toBe(false);
  });

  it('erro de rede mostra o erro e "Tentar de novo", nunca a lista vazia', async () => {
    const wrapper = await montar({ funcoes: [], falha: true });

    expect(wrapper.find('[data-erro]').text()).toContain(
      'Não deu para abrir as funções agora.'
    );
    expect(wrapper.find('[data-tentar-de-novo]').exists()).toBe(true);
    expect(wrapper.find('[data-vazio]').exists()).toBe(false);
    expect(wrapper.find('[data-cartao-funcao]').exists()).toBe(false);
  });

  it('sem nenhuma função, o herói e as 3 prontas em destaque', async () => {
    const wrapper = await montar({ funcoes: [] });

    expect(wrapper.find('[data-vazio]').exists()).toBe(true);
    expect(wrapper.findAll('[data-pronta]')).toHaveLength(3);
    expect(wrapper.find('[data-erro]').exists()).toBe(false);

    await wrapper.find('[data-pronta="AGENT"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_new',
      query: { pronta: 'AGENT' },
    });
  });

  it('função acima do alcance fica travada, sem Alterar nem Mais', async () => {
    const wrapper = await montar({ admin: false, pessoas: true });
    const [atendente, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    expect(financeiro.find('[data-travada]').text()).toBe(
      'Só o administrador muda esta função.'
    );
    expect(financeiro.find('[data-alterar]').exists()).toBe(false);
    expect(financeiro.find('[data-mais]').exists()).toBe(false);
    expect(atendente.find('[data-alterar]').exists()).toBe(true);
  });

  it('"Escolher pessoas" só com Pessoas e numa função ao alcance', async () => {
    const vazia = { ...ATENDENTE, id: 3, name: 'Nova' };
    const comPessoas = await montar({
      funcoes: [vazia],
      admin: false,
      pessoas: true,
    });
    expect(comPessoas.find('[data-escolher-pessoas]').exists()).toBe(true);

    const semPessoas = await montar({ funcoes: [vazia], admin: false });
    expect(semPessoas.find('[data-ninguem]').text()).toBe('Ninguém usa ainda');
    expect(semPessoas.find('[data-escolher-pessoas]').exists()).toBe(false);
  });

  it('Criar, Alterar e Duplicar abrem a conversa guiada (PR 3)', async () => {
    const wrapper = await montar();
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await wrapper.find('[data-criar]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({ name: 'funcoes_equipe_new' });

    await atendente.find('[data-alterar]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_edit',
      params: { roleId: 1 },
    });

    await atendente.find('[data-mais]').trigger('click');
    await atendente.find('[data-acao="duplicar"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: 1 },
    });
  });

  it('fora do plano, o bloqueio de plano no lugar da lista', async () => {
    const wrapper = await montar({ plano: false });

    expect(wrapper.find('[data-paywall]').exists()).toBe(true);
    expect(wrapper.find('[data-cartao-funcao]').exists()).toBe(false);
  });

  it('"Ver quem são" abre a gaveta de quem está sem função; a pilha abre quem usa', async () => {
    const wrapper = await montar();
    const gaveta = () => wrapper.findComponent({ name: 'GavetaDaFuncao' });

    await wrapper.find('[data-ver-quem-sao]').trigger('click');
    expect(gaveta().props('funcao')).toBeNull();

    gaveta().vm.$emit('fechar');
    await flushPromises();
    expect(gaveta().exists()).toBe(false);

    await wrapper.find('[data-pessoas]').trigger('click');
    expect(gaveta().props('funcao')).toEqual(ATENDENTE);
    expect(wrapper.find('[data-pessoas]').attributes('aria-label')).toBe(
      'Ver a pessoa que é Atendente'
    );
  });

  it('"Ver tudo o que pode" do Sem função segue a flag crm_numeros_lentes', async () => {
    const itens = async lentes => {
      const wrapper = await montar({ lentes });
      await wrapper.find('[data-ver-tudo-sem-funcao]').trigger('click');
      return wrapper
        .findAll('[data-grupo="NAO_PODE"] [data-item]')
        .map(item => item.text());
    };

    expect(await itens(false)).toEqual([
      'Procurar clientes novos',
      'Levar a lista de clientes para uma planilha',
    ]);
    expect(await itens(true)).toContain('Ver os relatórios das vendas');
  });

  it('apagar sem ninguém: "Apagar a função …?" e apaga sem destino', async () => {
    const apagar = vi.fn();
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    expect(dialogo(wrapper).find('h2').text()).toBe(
      'Apagar a função Financeiro?'
    );
    expect(dialogo(wrapper).text()).toContain(
      'Ninguém usa esta função. A função some da lista.'
    );
    expect(dialogo(wrapper).find('[data-seguro]').text()).toBe('Manter');
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(apagar).toHaveBeenCalledWith(expect.anything(), {
      id: 2,
      destinationRoleId: undefined,
    });
    expect(useAlert).toHaveBeenCalledWith('Função Financeiro apagada.');
  });

  it('apagar com gente: destino obrigatório, e "Sem função" mostra o que muda', async () => {
    const apagar = vi.fn();
    const wrapper = await montar({ apagar });
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(atendente);
    expect(dialogo(wrapper).find('h2').text()).toBe('Para onde vai a pessoa?');
    const mover = dialogo(wrapper).find('[data-acao]');
    expect(mover.text()).toBe('Mover as pessoas e apagar');
    expect(mover.attributes('disabled')).toBeDefined();

    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    const diff = dialogo(wrapper).find('[data-diff]');
    expect(diff.text()).toContain(
      'Essa pessoa vai passar a poder mais coisas.'
    );
    expect(diff.find('[data-grupo="PASSAM"]').text()).toContain(
      'Ler e atender as conversas dos colegas, nos canais em que estão'
    );
    expect(mover.attributes('disabled')).toBeUndefined();

    await mover.trigger('click');
    await flushPromises();
    expect(apagar).toHaveBeenCalledWith(expect.anything(), {
      id: 1,
      destinationRoleId: 'none',
    });
  });

  it('409: avisa que alguém mudou a função e recarrega', async () => {
    const apagar = vi.fn().mockRejectedValue(
      Object.assign(new Error('conflito'), {
        code: 'changed_meanwhile',
        status: 409,
      })
    );
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');
    recarregar.mockClear();

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Alguém mudou esta função agora. Confira de novo.'
    );
    expect(recarregar).toHaveBeenCalled();
  });

  it('destination_invalid: reabre a pergunta com o motivo', async () => {
    const apagar = vi
      .fn()
      .mockRejectedValue(
        Object.assign(new Error('recusado'), { code: 'destination_invalid' })
      );
    const wrapper = await montar({ apagar });
    const [atendente] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(atendente);
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(dialogo(wrapper).find('[data-erro-destino]').text()).toBe(
      'Essa função não está mais disponível. Escolha outra.'
    );
    expect(
      dialogo(wrapper).find('[data-acao]').attributes('disabled')
    ).toBeDefined();
    expect(recarregar).toHaveBeenCalledTimes(2);
  });

  const recusa = (code, status) =>
    Object.assign(new Error('Has people'), { code, status });

  it('destination_required: recarrega as pessoas e, achando gente, pergunta o destino', async () => {
    const apagar = vi.fn().mockRejectedValue(recusa('destination_required'));
    const pessoasDaConta = vi.fn();
    const wrapper = await montar({ apagar, pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    // A lista de agentes do teste não tem ninguém no Financeiro: o aviso do servidor aparece.
    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith('Has people');
  });

  it.each([
    [
      'sessão boa: diz o motivo',
      {},
      'Você não pode dar parte disto. Peça ao administrador.',
    ],
    ['sessão vencida: nenhum aviso', null, null],
  ])('apagar com 401, %s', async (_, sessao, frase) => {
    if (sessao) validityCheck.mockResolvedValue(sessao);
    else validityCheck.mockRejectedValue({ response: { status: 401 } });
    const apagar = vi.fn().mockRejectedValue(recusa('out_of_reach', 401));
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(validityCheck).toHaveBeenCalledTimes(1);
    if (frase) expect(useAlert).toHaveBeenCalledWith(frase);
    else expect(useAlert).not.toHaveBeenCalled();
  });

  it('falha ao buscar as pessoas não vira "nenhuma pessoa": diz que não deu e oferece tentar', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    const wrapper = await montar({ pessoasDaConta });

    expect(wrapper.find('[data-contagem]').text()).toContain(
      'Não deu para ver quem tem cada função.'
    );
    expect(wrapper.find('[data-contagem]').text()).not.toContain('nenhuma');
    expect(wrapper.find('[data-faixa-sem-funcao]').exists()).toBe(false);
    expect(wrapper.find('[data-cartao-funcao]').text()).not.toContain(
      'Ninguém usa'
    );

    await wrapper.find('[data-tentar-pessoas]').trigger('click');
    await flushPromises();
    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-contagem]').text()).toBe(
      '2 funções criadas · 1 pessoa com função'
    );
  });
});
