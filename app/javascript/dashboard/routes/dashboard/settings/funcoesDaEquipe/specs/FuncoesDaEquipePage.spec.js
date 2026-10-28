import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import FuncoesDaEquipePage from '../FuncoesDaEquipePage.vue';

// #2308, especificação 5.A: a lista nova. Faixa só com Pessoas, erro nunca vira lista vazia, função travada
// sem ações, e as fixas.
const { routerPush } = vi.hoisted(() => ({ routerPush: vi.fn() }));
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
const montar = async ({
  funcoes = [ATENDENTE, FINANCEIRO],
  admin = true,
  pessoas = false,
  falha = false,
  plano = true,
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
      'accounts/isFeatureEnabledonAccount': () => () => plano,
      'customRole/getCustomRoles': () => funcoes,
      'customRole/getUIFlags': () => ({
        fetchingList: false,
        fetchingListFailed: falha,
      }),
      'agents/getAgents': () => AGENTES,
    },
    actions: {
      'customRole/getCustomRole': vi.fn(),
      'agents/get': vi.fn(),
    },
  });
  const wrapper = mount(FuncoesDaEquipePage, {
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
        AssignAgentsDialog: true,
        DeleteRoleDialog: true,
        PaywallDasFuncoes: { template: '<div data-paywall />' },
        'woot-delete-modal': true,
      },
    },
  });
  await flushPromises();
  return wrapper;
};

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
      'Cria e muda os contatos e as respostas prontas.'
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
});
