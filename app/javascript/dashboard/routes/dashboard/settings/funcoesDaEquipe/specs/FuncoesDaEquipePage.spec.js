import { reactive } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import { PRESETS } from '../../customRoles/permissionMatrix';
import FuncoesDaEquipePage from '../FuncoesDaEquipePage.vue';

// #2308, especificação 5.A e 5.E: a lista nova. Faixa só com Pessoas, erro nunca vira lista vazia, função travada
// sem ações, as fixas, a gaveta de pessoas e o apagar com destino.
const { routerPush, validityCheck, clearCookiesOnLogout } = vi.hoisted(() => ({
  routerPush: vi.fn(),
  validityCheck: vi.fn(),
  clearCookiesOnLogout: vi.fn(),
}));
vi.mock('dashboard/api/auth', () => ({ default: { validityCheck } }));
// O logout de verdade limparia o storage e redirecionaria dentro do jsdom: o teste só confere que foi pedido.
vi.mock('dashboard/store/utils/api', async importOriginal => ({
  ...(await importOriginal()),
  clearCookiesOnLogout,
}));
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
  agentes = AGENTES,
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
      'agents/getAgents': () => agentes,
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

// Especificação 5.E (Vendedor → Sem função), com o que o contrato gerado diz a mais com crm_numeros_lentes desligada.
const PASSAM_DO_VENDEDOR = [
  'Ler e atender as conversas dos colegas, nos canais em que estão',
  'Criar e mudar as respostas prontas',
  'Apagar mensagens',
  'Arquivar vendas',
  'Ver os relatórios das vendas',
  'Ver os valores das vendas em R$',
  'Ver de que anúncio veio cada cliente',
];
const DEIXAM_DO_VENDEDOR = ['Procurar clientes novos'];
const DEIXAM_DO_SUPERVISOR = [
  'Ver: Central de Ajuda (artigos para os clientes)',
  'Ver: Relatórios',
  'Ver: Robôs de IA',
  'Ver: Canais (números de WhatsApp, Instagram, e-mail)',
  'Ver: Regras automáticas',
  'Mexer: Etiquetas',
  'Mexer: Atalhos de mensagens',
];

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
    await financeiro.find('[data-mais]').trigger('click');
    expect(
      financeiro.findAll('[role="menuitem"]').map(item => item.text())
    ).toEqual(['Duplicar']);
    await financeiro.find('[data-acao="duplicar"]').trigger('click');
    expect(routerPush).toHaveBeenCalledWith({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: 2 },
    });
    expect(atendente.find('[data-alterar]').exists()).toBe(true);
  });

  it('a própria função diz que ninguém muda a própria e ainda oferece Duplicar', async () => {
    const minha = { ...ATENDENTE, id: 99, name: 'Gerente da loja' };
    const wrapper = await montar({ funcoes: [minha], admin: false });
    const cartao = wrapper.find('[data-cartao-funcao]');

    expect(cartao.find('[data-travada]').text()).toBe(
      'Ninguém muda a própria função.'
    );
    expect(cartao.find('[data-alterar]').exists()).toBe(false);
    await cartao.find('[data-mais]').trigger('click');
    expect(
      cartao.findAll('[role="menuitem"]').map(item => item.text())
    ).toEqual(['Duplicar']);
  });

  it('enquanto as pessoas carregam: esqueleto, nunca "nenhuma pessoa" nem "Ninguém usa ainda"', async () => {
    let soltar;
    const pessoasDaConta = vi.fn(
      () =>
        new Promise(resolve => {
          soltar = resolve;
        })
    );
    const wrapper = await montar({ pessoasDaConta });

    expect(
      wrapper.find('[data-contagem] [data-pessoas-carregando]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-contagem]').text()).not.toContain('nenhuma');
    expect(
      wrapper.find('[data-cartao-funcao] [data-pessoas-carregando]').exists()
    ).toBe(true);
    expect(wrapper.text()).not.toContain('Ninguém usa ainda');
    expect(wrapper.find('[data-faixa-sem-funcao]').exists()).toBe(false);

    soltar(true);
    await flushPromises();
    expect(wrapper.find('[data-pessoas-carregando]').exists()).toBe(false);
    expect(wrapper.find('[data-contagem]').text()).toBe(
      '2 funções criadas · 1 pessoa com função'
    );
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
      'Montar as colunas das vendas',
      'Pedir ajuda à IA nas vendas',
      'Cuidar de tudo nas vendas',
      'Definir as metas do mês de cada pessoa',
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

    // A lista de agentes do teste não tem ninguém no Financeiro: o aviso é o da tela, nunca o texto cru do servidor.
    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith(
      'Esta função ainda tem pessoas. Escolha para onde vão.'
    );
    expect(useAlert).not.toHaveBeenCalledWith('Has people');
  });

  // A recusa sem código é o corpo real do check_authorization (request_exception_handler.rb).
  it.each([
    [
      'sessão boa e fora do alcance: frase de apagar',
      {},
      'out_of_reach',
      'Você não pode apagar esta função. Peça ao administrador.',
    ],
    [
      'sessão boa e sem código: perdeu o acesso',
      {},
      'You are not authorized to do this action',
      'Você não pode mais mudar as funções. Fale com o administrador.',
    ],
    [
      'sessão boa e flag desligada: indisponível',
      {},
      'feature_off',
      'Funções da equipe não estão disponíveis agora. Fale com o administrador.',
    ],
    [
      'sessão vencida: nenhum aviso e vai para o login',
      null,
      'out_of_reach',
      null,
    ],
  ])('apagar com 401, %s', async (_, sessao, codigo, frase) => {
    if (sessao) validityCheck.mockResolvedValue(sessao);
    else validityCheck.mockRejectedValue({ response: { status: 401 } });
    const apagar = vi.fn().mockRejectedValue(recusa(codigo, 401));
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();

    expect(validityCheck).toHaveBeenCalledTimes(1);
    if (frase) expect(useAlert).toHaveBeenCalledWith(frase);
    else expect(useAlert).not.toHaveBeenCalled();
    expect(clearCookiesOnLogout).toHaveBeenCalledTimes(frase ? 0 : 1);
  });

  it('apagar um Vendedor com gente para "Sem função" desenha o que se ganha e o que se perde', async () => {
    const vendedor = { id: 4, name: 'Vendedor', permissions: PRESETS.SDR() };
    const wrapper = await montar({
      funcoes: [vendedor],
      agentes: [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 4 }],
    });

    await pedirApagar(wrapper.find('[data-cartao-funcao]'));
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    const diff = dialogo(wrapper).find('[data-diff]');
    const itens = grupo =>
      diff.findAll(`[data-grupo="${grupo}"] [data-item]`).map(i => i.text());

    expect(diff.find('p').text()).toBe(
      'Essa pessoa vai ganhar umas coisas e perder outras.'
    );
    expect(diff.find('[data-grupo="DEIXAM"] p').text()).toBe('Vai deixar de');
    expect(itens('PASSAM')).toEqual(PASSAM_DO_VENDEDOR);
    expect(itens('DEIXAM')).toEqual(DEIXAM_DO_VENDEDOR);
  });

  it('apagar um Supervisor para "Sem função": as áreas que somem aparecem com o texto da área, sem chave crua', async () => {
    const supervisor = {
      id: 5,
      name: 'Supervisor',
      permissions: PRESETS.SUPERVISOR(),
    };
    const wrapper = await montar({
      funcoes: [supervisor],
      agentes: [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 5 }],
    });

    await pedirApagar(wrapper.find('[data-cartao-funcao]'));
    wrapper.findComponent(ChoiceSelect).vm.$emit('update:modelValue', 'none');
    await flushPromises();
    const deixam = dialogo(wrapper)
      .findAll('[data-grupo="DEIXAM"] [data-item]')
      .map(i => i.text());
    expect(deixam).toEqual(DEIXAM_DO_SUPERVISOR);
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

  // Rodada 3: o apagar nunca diz "Ninguém usa" sem a contagem das pessoas.
  it('apagar enquanto as pessoas carregam: diz que está vendo e não deixa apagar', async () => {
    const wrapper = await montar({
      pessoasDaConta: vi.fn(() => new Promise(() => {})),
    });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    expect(dialogo(wrapper).text()).not.toContain('Ninguém usa');
    expect(dialogo(wrapper).find('[data-apagar-carregando]').text()).toBe(
      'Vendo quem usa esta função…'
    );
    expect(
      dialogo(wrapper).find('[data-acao]').attributes('disabled')
    ).toBeDefined();
  });

  it('apagar com as pessoas em erro: diz que não deu, oferece tentar e não deixa apagar', async () => {
    const pessoasDaConta = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    const wrapper = await montar({ pessoasDaConta });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    expect(dialogo(wrapper).text()).not.toContain('Ninguém usa');
    expect(dialogo(wrapper).find('[data-apagar-erro]').text()).toContain(
      'Não deu para ver quem usa esta função.'
    );
    expect(
      dialogo(wrapper).find('[data-acao]').attributes('disabled')
    ).toBeDefined();

    await dialogo(wrapper).find('[data-apagar-tentar]').trigger('click');
    await flushPromises();
    expect(pessoasDaConta).toHaveBeenCalledTimes(2);
    expect(dialogo(wrapper).text()).toContain('Ninguém usa esta função.');
  });

  it('apagando: o diálogo fica aberto em "Apagando…", com Manter, Esc e o segundo clique travados', async () => {
    let terminar;
    const apagar = vi.fn(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const fechar = vi.fn();
    HTMLDialogElement.prototype.close = fechar;
    const wrapper = await montar({ apagar });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    const acao = dialogo(wrapper).find('[data-acao]');
    await acao.trigger('click');
    await acao.trigger('click');
    expect(apagar).toHaveBeenCalledTimes(1);
    expect(acao.text()).toBe('Apagando…');
    expect(
      dialogo(wrapper).find('[data-seguro]').attributes('disabled')
    ).toBeDefined();
    await dialogo(wrapper).trigger('cancel');
    expect(fechar).not.toHaveBeenCalled();

    terminar();
    await flushPromises();
    expect(fechar).toHaveBeenCalledTimes(1);
    delete HTMLDialogElement.prototype.close;
  });

  it('apagada a função, o foco cai no título da lista (o "Mais" do cartão sumiu)', async () => {
    const lista = reactive([ATENDENTE, FINANCEIRO]);
    const apagar = vi.fn(() => {
      lista.splice(1, 1);
    });
    const wrapper = await montar({ apagar, funcoes: lista });
    const [, financeiro] = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(financeiro);
    await dialogo(wrapper).find('[data-acao]').trigger('click');
    await flushPromises();
    expect(wrapper.findAll('[data-cartao-funcao]')).toHaveLength(1);
    expect(document.activeElement).toBe(
      wrapper.find('[data-titulo-da-lista]').element
    );
  });

  // Quem apaga sem ser administrador vê como destino só as funções que alcança (reachesRole, especificação 5.D/5.E);
  // a própria função entra, como na gaveta: o servidor só pede o alcance (custom_roles_controller#destination_role_id).
  it('apagar como não administrador: o destino lista só as funções ao alcance, inclusive a própria', async () => {
    const minha = {
      id: 99,
      name: 'Gerente da loja',
      permissions: ['contact_view'],
    };
    const alvo = { id: 3, name: 'Alvo', permissions: ['contact_view'] };
    const wrapper = await montar({
      admin: false,
      funcoes: [ATENDENTE, FINANCEIRO, minha, alvo],
      agentes: [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 3 }],
    });
    const cartoes = wrapper.findAll('[data-cartao-funcao]');

    await pedirApagar(cartoes[3]);
    expect(wrapper.findComponent(ChoiceSelect).props('options')).toEqual([
      { value: 1, label: 'Atendente' },
      { value: 99, label: 'Gerente da loja' },
      { value: 'none', label: 'Sem função' },
    ]);
  });

  it('fechada a gaveta, se "Ver quem são" sumiu (todos ganharam função), o foco cai no título da lista', async () => {
    const agentes = reactive(AGENTES.map(item => ({ ...item })));
    const wrapper = await montar({ pessoas: true, agentes });
    await wrapper.find('[data-faixa-sem-funcao] button').trigger('click');
    const gaveta = wrapper.findComponent({ name: 'GavetaDaFuncao' });
    expect(gaveta.exists()).toBe(true);

    agentes.forEach(item => {
      item.custom_role_id = 1;
    });
    gaveta.vm.$emit('fechar');
    await flushPromises();
    expect(wrapper.find('[data-faixa-sem-funcao]').exists()).toBe(false);
    expect(document.activeElement).toBe(
      wrapper.find('[data-titulo-da-lista]').element
    );
  });
});
