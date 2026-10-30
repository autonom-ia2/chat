import { flushPromises, mount } from '@vue/test-utils';
import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';
import { PRESETS } from '../../customRoles/permissionMatrix';
import FuncaoGuiadaPage from '../guiada/FuncaoGuiadaPage.vue';
import { espiarDialogo, global, loja } from './montar';
import { ADMIN, CARLA, SEM_VER_VENDAS } from './quemMonta';

// #2308, especificação 5.B, 5.C, 5.F e Guarda: a conversa guiada de ponta a ponta, com a Carla (e o administrador
// para o aviso de perda de acesso).
const { rota, push, replace, saida, validityCheck, clearCookiesOnLogout } =
  vi.hoisted(() => ({
    rota: { name: '', params: {}, query: {} },
    push: vi.fn(),
    replace: vi.fn(),
    saida: { guarda: null },
    validityCheck: vi.fn(),
    clearCookiesOnLogout: vi.fn(),
  }));
vi.mock('dashboard/api/auth', () => ({ default: { validityCheck } }));
vi.mock('dashboard/store/utils/api', async importOriginal => ({
  ...(await importOriginal()),
  clearCookiesOnLogout,
}));
vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push, replace, resolve: () => ({ href: '/canais' }) }),
  onBeforeRouteLeave: guarda => {
    saida.guarda = guarda;
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const ATENDENTE = { id: 1, name: 'Atendente', permissions: PRESETS.AGENT() };
// A função da própria Carla: duplicar a própria pode (só não abre uma acima do alcance), e o R$ dela fica de fora.
const GERENTE = {
  id: 7,
  name: 'Gerente',
  description: 'Cuida das vendas',
  permissions: [
    'crm_view',
    'crm_manage_cards',
    'sales_value_view',
    'crm_metas_manage',
  ],
};
const ACIMA = { id: 3, name: 'Financeiro', permissions: ['financial_view'] };
// Acima do alcance da Carla pelo R$ (sales_value_view é de delegação): o exemplo da especificação 5.C.
const GERENTE_DE_VENDAS = {
  id: 5,
  name: 'Gerente de vendas',
  permissions: [
    'crm_view',
    'crm_manage_cards',
    'crm_move_cards',
    'sales_value_view',
    'crm_metas_manage',
  ],
};
const AGENTES = [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 1 }];

const montar = async ({
  name = 'funcoes_equipe_new',
  params = {},
  query = {},
  giver = CARLA,
  funcoes = [ATENDENTE, GERENTE, ACIMA],
  agentes = AGENTES,
  actions = {},
} = {}) => {
  Object.assign(rota, { name, params: { accountId: '1', ...params }, query });
  const criar = vi.fn(async (_contexto, dados) => ({ id: 9, ...dados }));
  const alterar = vi.fn(async (_contexto, { id, ...dados }) => ({
    id,
    ...dados,
  }));
  const store = loja({
    giver,
    funcoes,
    agentes,
    actions: {
      'customRole/createCustomRole': criar,
      'customRole/updateCustomRole': alterar,
      ...actions,
    },
  });
  const wrapper = mount(FuncaoGuiadaPage, {
    attachTo: document.body,
    global: {
      ...global(store),
      stubs: { ...global(store).stubs, Avatar: true },
    },
  });
  await flushPromises();
  return { wrapper, criar, alterar, store };
};

const SEM_PESSOAS = {
  ...CARLA,
  permissions: CARLA.permissions.filter(chave => chave !== 'people_manage'),
};
const recusa = code =>
  Object.assign(new Error('recusa'), { status: 401, code, attributes: [] });
const dialogoCom = (wrapper, texto) =>
  wrapper.findAll('dialog').find(item => item.find('h2').text() === texto);

const clicar = async (wrapper, seletor) => {
  await wrapper.find(seletor).trigger('click');
  await flushPromises();
};

afterEach(() => {
  document.body.innerHTML = '';
  push.mockReset();
  replace.mockReset();
  validityCheck.mockReset();
  clearCookiesOnLogout.mockReset();
});

describe('FuncaoGuiadaPage', () => {
  it('Escolha → Ajustes → Confira → Sucesso, partindo de uma função que a conta já tem', async () => {
    const { wrapper, criar } = await montar();

    expect(wrapper.find('h1').text()).toBe('Para quem é esta função?');
    const atendente = wrapper.find('[data-pronta="AGENT"]');
    expect(atendente.text()).toContain('Você já tem esta função · 1 pessoa');
    expect(atendente.find('[data-principal]').text()).toBe(
      'Pôr uma pessoa nela'
    );

    await clicar(wrapper, '[data-pronta="AGENT"] [data-criar-a-partir]');
    expect(wrapper.find('h1').text()).toBe('Quer mudar alguma coisa?');
    expect(wrapper.text()).toContain(
      'A função pronta Atendente já vem assim. Se estiver bom, toque em "Continuar".'
    );
    expect(wrapper.find('[data-linha="conversas"]').text()).toContain(
      'Atende as próprias, pega as novas e ajuda quando um colega chama'
    );
    expect(wrapper.find('[data-linha="cuidado"]').text()).toContain(
      'Nenhuma ligada · apagar, planilhas, campanhas e IA'
    );
    expect(wrapper.find('[data-recolhida]').text()).toContain(
      'Relatórios, Desempenho da equipe e mais 10 áreas'
    );
    expect(wrapper.find('[data-recolhida]').text()).toContain(
      'Hoje estão todas desligadas.'
    );
    expect(wrapper.find('[data-previa] [data-frase]').text()).toContain(
      'Com a função Atendente, a pessoa atende'
    );

    await clicar(wrapper, '[data-botao-grande]');
    expect(wrapper.find('h1').text()).toBe('Está certo assim?');
    expect(wrapper.find('input').element.value).toBe('Atendente 2');
    expect(wrapper.text()).toContain(
      'Você já tem uma função Atendente. Pode trocar este nome.'
    );

    await clicar(wrapper, '[data-botao-grande]');
    expect(criar).toHaveBeenCalledWith(expect.anything(), {
      name: 'Atendente 2',
      description: 'Quem atende o WhatsApp no dia a dia.',
      permissions: PRESETS.AGENT(),
    });
    expect(wrapper.find('[data-sucesso]').text()).toContain(
      'Função Atendente 2 criada.'
    );
    expect(wrapper.find('[data-sucesso]').text()).toContain(
      'Quem vai ser Atendente 2?'
    );
    expect(wrapper.find('[data-previa]').text()).toContain('Salva');
    expect(await saida.guarda()).toBe(true);
  });

  it('a pergunta volta a Ajustes e a linha mudada mostra o que era antes', async () => {
    const { wrapper } = await montar({ query: { pronta: 'AGENT' } });

    await clicar(wrapper, '[data-linha="contatos"] [data-alterar-area]');
    expect(wrapper.find('h1').text()).toBe(
      'Com a função Atendente, o que a pessoa faz com os contatos?'
    );
    await clicar(wrapper, '[data-nivel="manage"]');
    await clicar(wrapper, '[data-botao-grande]');

    const contatos = wrapper.find('[data-linha="contatos"]');
    expect(contatos.text()).toContain('Pode mexer');
    expect(contatos.text()).toContain('você mudou');
    expect(contatos.text()).toContain('· antes: só olhava');
  });

  it('a guarda pergunta antes de sair com mudanças, e "Continuar ajustando" fica', async () => {
    const { wrapper } = await montar({ query: { pronta: 'AGENT' } });
    expect(await saida.guarda()).toBe(true);

    await clicar(wrapper, '[data-linha="contatos"] [data-alterar-area]');
    await clicar(wrapper, '[data-nivel="none"]');

    const resposta = saida.guarda();
    await flushPromises();
    const guarda = wrapper
      .findAll('dialog')
      .find(d => d.text().includes('Sair sem salvar?'));
    expect(guarda.text()).toContain('O que você mudou vai se perder.');
    await guarda.find('[data-seguro]').trigger('click');
    expect(await resposta).toBe(false);

    const deNovo = saida.guarda();
    await flushPromises();
    await guarda.find('[data-acao]').trigger('click');
    expect(await deNovo).toBe(true);
  });

  it('alterar abre em Ajustes com o nome da função', async () => {
    const { wrapper } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
    });
    expect(wrapper.find('h1').text()).toBe('Alterar Atendente');
    expect(wrapper.find('[data-voltar]').text()).toBe('Voltar para a lista');
  });

  it('alterar a própria função volta para a lista', async () => {
    await montar({ name: 'funcoes_equipe_edit', params: { roleId: '7' } });
    expect(replace).toHaveBeenCalledWith({ name: 'funcoes_equipe_list' });
  });

  // Revisão do #2308 (rodada 1): duplicar uma função acima do alcance abre a cópia cortada, com o aviso da 5.C.
  it('duplicar uma função acima do alcance abre a cópia sem o que a Carla não pode dar, e avisa', async () => {
    const { wrapper, criar } = await montar({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: '5' },
      funcoes: [ATENDENTE, GERENTE, GERENTE_DE_VENDAS],
    });
    expect(replace).not.toHaveBeenCalled();
    expect(wrapper.find('h1').text()).toBe('Confira a cópia');
    expect(wrapper.find('[data-aviso-copia]').text()).toBe(
      'Ficou de fora o que você não pode dar: ver os valores das vendas em R$ e, junto, as metas do mês.'
    );
    await clicar(wrapper, '[data-botao-grande]');
    expect(criar.mock.calls[0][1].permissions).toEqual([
      'crm_view',
      'crm_manage_cards',
      'crm_move_cards',
    ]);
  });

  // Rodada 3: sem crm_view, editar as vendas também fica de fora (traz crm_view), e a cópia salva sem trava.
  it('duplicar com quem monta sem crm_view corta também a chave de editar as vendas', async () => {
    const vendedor = {
      id: 6,
      name: 'Vendedor',
      permissions: ['contact_view', 'crm_view', 'crm_manage_cards'],
    };
    const { wrapper, criar } = await montar({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: '6' },
      giver: SEM_VER_VENDAS,
      funcoes: [ATENDENTE, vendedor],
    });
    expect(wrapper.find('h1').text()).toBe('Confira a cópia');
    await clicar(wrapper, '[data-botao-grande]');
    expect(criar.mock.calls[0][1].permissions).toEqual(['contact_view']);
  });

  // #2352: a chave do portal de artigos não tem área nas telas de função. Quem não a pode dar duplica sem ela e sem
  // aviso (antes o aviso nomeava uma área que não existe mais).
  it('duplicar corta em silêncio a chave que nenhuma tela de função mostra', async () => {
    const comPortal = {
      id: 8,
      name: 'Com portal',
      permissions: ['contact_view', 'knowledge_base_manage'],
    };
    const { wrapper, criar } = await montar({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: '8' },
      giver: SEM_VER_VENDAS,
      funcoes: [ATENDENTE, comPortal],
    });
    expect(wrapper.find('h1').text()).toBe('Confira a cópia');
    expect(wrapper.find('[data-aviso-copia]').exists()).toBe(false);
    await clicar(wrapper, '[data-botao-grande]');
    expect(criar.mock.calls[0][1].permissions).toEqual(['contact_view']);
  });

  // Revisão do #2308 (rodada 1): sem custom_roles na conta, a conversa mostra o paywall, nunca o erro de internet nem a busca.
  it('com custom_roles desligado, mostra o paywall e não busca as funções', async () => {
    const buscar = vi.fn();
    Object.assign(rota, { name: 'funcoes_equipe_new', params: {}, query: {} });
    const store = loja({
      flags: [],
      actions: { 'customRole/getCustomRole': buscar },
    });
    const wrapper = mount(FuncaoGuiadaPage, { global: global(store) });
    await flushPromises();
    expect(wrapper.find('[data-paywall]').exists()).toBe(true);
    expect(wrapper.find('[data-erro]').exists()).toBe(false);
    expect(buscar).not.toHaveBeenCalled();
  });

  it('duplicar abre "Confira a cópia" e avisa o que ficou de fora', async () => {
    const { wrapper } = await montar({
      name: 'funcoes_equipe_duplicate',
      params: { roleId: '7' },
    });
    expect(wrapper.find('h1').text()).toBe('Confira a cópia');
    expect(wrapper.find('input').element.value).toBe('Gerente 2');
    expect(wrapper.find('[data-aviso-copia]').text()).toContain(
      'ver os valores das vendas em R$ e, junto, as metas do mês'
    );
  });

  it('"Pôr uma pessoa nela" abre a gaveta "Quem vai ser …?"', async () => {
    const { wrapper } = await montar();

    await clicar(wrapper, '[data-pronta="AGENT"] [data-principal]');
    expect(wrapper.find('aside h2').text()).toBe('Quem vai ser Atendente?');
    expect(wrapper.find('[data-ja-sao]').text()).toContain('Ana');
  });

  it.each([
    ['ABOVE', { id: 4, name: 'Vendedor', permissions: ['financial_view'] }],
    ['MINE', { id: 7, name: 'Vendedor', permissions: PRESETS.SDR() }],
  ])('"Pôr uma pessoa nela" some com a trava %s', async (trava, vendedor) => {
    const { wrapper } = await montar({ funcoes: [ATENDENTE, vendedor] });
    const cartao = wrapper.find('[data-pronta="SDR"]');

    expect(cartao.text()).not.toContain('Pôr uma pessoa nela');
    expect(cartao.find('[data-trava-pessoa]').text()).toBe(
      trava === 'ABOVE'
        ? 'Só o administrador põe pessoas nela.'
        : 'Ninguém muda a própria função.'
    );
  });

  const tirarAsVendas = async wrapper => {
    await clicar(wrapper, '[data-linha="vendas"] [data-alterar-area]');
    await clicar(wrapper, '[data-nivel="none"]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
  };

  it('perda de acesso: o administrador vê quem perde o quê antes de salvar; "Voltar" não salva', async () => {
    const { wrapper, alterar } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
      giver: ADMIN,
    });

    await tirarAsVendas(wrapper);
    const perda = wrapper
      .findAll('dialog')
      .find(item => item.find('[data-nomes]').exists());
    // Texto da 5.F com a decisão de gênero: uma perda só vai no título e a lista não a repete (rodada 3); a área das
    // vendas não se repete, porque a capacidade dela já saiu.
    expect(perda.find('h2').text()).toBe(
      '1 pessoa vai deixar de criar e mover as vendas em andamento'
    );
    expect(perda.find('[data-nomes]').text()).toBe('Ana');
    expect(perda.text()).toContain('Essa pessoa tem a função Atendente.');
    expect(perda.text()).not.toContain('não vai mais poder');
    expect(perda.find('[data-perdas]').exists()).toBe(false);
    expect(alterar).not.toHaveBeenCalled();

    await perda.find('[data-seguro]').trigger('click');
    await flushPromises();
    expect(alterar).not.toHaveBeenCalled();

    await clicar(wrapper, '[data-botao-grande]');
    await perda.find('[data-acao]').trigger('click');
    await flushPromises();
    expect(alterar).toHaveBeenCalledTimes(1);
  });

  it('perda de acesso com várias pessoas: plural certo e todos os nomes', async () => {
    const { wrapper } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
      giver: ADMIN,
      agentes: [
        ...AGENTES,
        { id: 11, name: 'Beto', role: 'agent', custom_role_id: 1 },
      ],
    });

    await tirarAsVendas(wrapper);
    const perda = wrapper
      .findAll('dialog')
      .find(item => item.find('[data-nomes]').exists());
    expect(perda.find('h2').text()).toBe(
      '2 pessoas vão deixar de criar e mover as vendas em andamento'
    );
    expect(perda.find('[data-nomes]').text()).toBe('Ana e Beto');
    expect(perda.text()).toContain('Essas pessoas têm a função Atendente.');
  });

  it('perda de acesso com uma coisa só: o título diz qual, e os nomes param em 3', async () => {
    const { wrapper } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
      giver: ADMIN,
      agentes: ['Ana', 'Beto', 'Caio', 'Duda', 'Eva'].map((name, i) => ({
        id: 20 + i,
        name,
        role: 'agent',
        custom_role_id: 1,
      })),
    });
    await clicar(wrapper, '[data-linha="contatos"] [data-alterar-area]');
    await clicar(wrapper, '[data-nivel="none"]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    const perda = wrapper
      .findAll('dialog')
      .find(item => item.find('[data-nomes]').exists());
    expect(perda.find('h2').text()).toBe(
      '5 pessoas vão deixar de ver os contatos'
    );
    expect(perda.find('[data-nomes]').text()).toBe(
      'Ana, Beto, Caio e mais 2 pessoas'
    );
  });

  // Rodada 5: o texto da perda diz também o que fica, pela página (sem o `fica`, ele pararia em quem tem a função).
  it('perda de acesso numa queda de nível: diz o que fica, como na especificação 5.F', async () => {
    const vendedor = { id: 1, name: 'Vendedor', permissions: PRESETS.SDR() };
    const { wrapper } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
      giver: ADMIN,
      funcoes: [vendedor],
      agentes: [
        ...AGENTES,
        { id: 11, name: 'Beto', role: 'agent', custom_role_id: 1 },
      ],
    });
    await clicar(wrapper, '[data-linha="contatos"] [data-alterar-area]');
    await clicar(wrapper, '[data-nivel="view"]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    const perda = wrapper
      .findAll('dialog')
      .find(item => item.find('[data-nomes]').exists());

    expect(perda.find('h2').text()).toBe(
      '2 pessoas vão deixar de mudar os dados dos contatos'
    );
    expect(perda.find('[data-texto-perda]').text()).toBe(
      'Essas pessoas têm a função Vendedor. A partir de agora, só vão olhar os contatos.'
    );
  });

  it('perda de acesso não aparece para quem não é administrador', async () => {
    const { wrapper, alterar } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
    });

    const { mostrar, soltar } = espiarDialogo();
    await tirarAsVendas(wrapper);
    expect(mostrar).not.toHaveBeenCalled();
    // O diálogo da perda fica montado fechado: o que importa é que ele não abriu.
    const dialogo = wrapper.find('[data-nomes]').element.closest('dialog');
    expect(dialogo.hasAttribute('open')).toBe(false);
    expect(alterar).toHaveBeenCalledTimes(1);
    soltar();
  });

  it.each([
    // Criar nunca recusa com own_role (não há função ainda): o código possível aqui é out_of_reach (rodada 4).
    [
      'sessão boa: diz o motivo e fica no Confira',
      'resolve',
      'Você não pode dar parte disto. Peça ao administrador.',
    ],
    ['sessão vencida: vai para o login, sem mensagem', 'reject', ''],
  ])('401 ao salvar, %s', async (_, sessao, frase) => {
    if (sessao === 'resolve') validityCheck.mockResolvedValue({});
    else validityCheck.mockRejectedValue({ response: { status: 401 } });
    const { wrapper } = await montar({
      query: { pronta: 'AGENT' },
      actions: {
        'customRole/createCustomRole': vi.fn(() =>
          Promise.reject(recusa('out_of_reach'))
        ),
      },
    });

    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    expect(wrapper.find('h1').text()).toBe('Está certo assim?');
    expect(wrapper.find('[data-sucesso]').exists()).toBe(false);
    if (frase) expect(wrapper.text()).toContain(frase);
    else {
      // Sessão vencida: nenhuma mensagem (especificação 14), nem no aviso nem no campo do nome.
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
      expect(wrapper.find('[data-erro-salvar]').exists()).toBe(false);
      expect(wrapper.find('[data-erro-nome]').exists()).toBe(false);
      [
        ptBR.FUNCOES_EQUIPE.SALVAR.FORA_DO_ALCANCE,
        ptBR.FUNCOES_EQUIPE.SALVAR.SEM_ACESSO,
        ptBR.FUNCOES_EQUIPE.SALVAR.REDE,
      ].forEach(texto => expect(wrapper.text()).not.toContain(texto));
    }
    expect(clearCookiesOnLogout).toHaveBeenCalledTimes(frase ? 0 : 1);
  });

  it('sem Pessoas, o Sucesso não tem "Escolher pessoas" e a Escolha não tem "Pôr uma pessoa nela"', async () => {
    const { wrapper } = await montar({ giver: SEM_PESSOAS });
    expect(wrapper.text()).not.toContain('Pôr uma pessoa nela');

    await clicar(wrapper, '[data-pronta="AGENT"] [data-principal]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-botao-grande]');
    const sucesso = wrapper.find('[data-sucesso]');
    const titulo = sucesso.find('h1');
    expect(titulo.text()).toBe('Função Atendente 2 criada.');
    expect(document.activeElement).toBe(titulo.element);
    expect(sucesso.text()).toContain(
      'Peça ao administrador para pôr pessoas nela.'
    );
    expect(sucesso.find('[data-botao-grande]').text()).toBe(
      'Voltar para a lista'
    );
    expect(wrapper.find('[data-voltar]').exists()).toBe(false);
    await clicar(wrapper, '[data-sucesso] [data-botao-grande]');
    expect(push).toHaveBeenCalledWith({ name: 'funcoes_equipe_list' });
  });

  it('erro de rede ao abrir: mostra o erro com "Tentar de novo", e tentar recarrega', async () => {
    const pessoas = vi
      .fn()
      .mockResolvedValueOnce(false)
      .mockResolvedValue(true);
    const { wrapper } = await montar({
      name: 'funcoes_equipe_edit',
      params: { roleId: '1' },
      actions: { 'agents/get': pessoas },
    });
    expect(wrapper.find('[data-erro]').attributes('role')).toBe('alert');
    expect(replace).not.toHaveBeenCalled();

    await clicar(wrapper, '[data-tentar-de-novo]');
    expect(pessoas).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-erro]').exists()).toBe(false);
    expect(wrapper.find('h1').text()).toBe('Alterar Atendente');
  });

  it.each([
    ['inexistente', 'NAO_EXISTE'],
    ['fora do alcance', 'FINANCE'],
  ])('?pronta= %s fica na Escolha', async (_, pronta) => {
    const { wrapper } = await montar({ query: { pronta } });
    expect(wrapper.find('h1').text()).toBe('Para quem é esta função?');
  });

  it('"Trocar a função pronta" com ajustes pergunta antes; sem ajustes, volta direto', async () => {
    const { mostrar, soltar } = espiarDialogo();
    const { wrapper } = await montar({ query: { pronta: 'AGENT' } });

    await clicar(wrapper, '[data-linha="contatos"] [data-alterar-area]');
    await clicar(wrapper, '[data-nivel="manage"]');
    await clicar(wrapper, '[data-botao-grande]');
    await clicar(wrapper, '[data-voltar]');
    expect(mostrar).toHaveBeenCalledTimes(1);
    expect(wrapper.find('h1').text()).toBe('Quer mudar alguma coisa?');

    const trocar = dialogoCom(wrapper, 'Trocar a função pronta?');
    await trocar.find('[data-acao]').trigger('click');
    await flushPromises();
    expect(wrapper.find('h1').text()).toBe('Para quem é esta função?');
    expect(document.activeElement).toBe(wrapper.find('h1').element);
    soltar();
  });

  it('salvando: o voltar fica desligado, a guarda não deixa sair e um segundo toque não duplica', async () => {
    let terminar;
    const criar = vi.fn(
      () =>
        new Promise(resolve => {
          terminar = resolve;
        })
    );
    const { wrapper } = await montar({
      query: { pronta: 'AGENT' },
      actions: { 'customRole/createCustomRole': criar },
    });
    await clicar(wrapper, '[data-botao-grande]');

    await wrapper.find('[data-botao-grande]').trigger('click');
    await wrapper.find('[data-botao-grande]').trigger('click');
    expect(criar).toHaveBeenCalledTimes(1);
    expect(wrapper.find('[data-voltar]').attributes('disabled')).toBeDefined();
    expect(await saida.guarda()).toBe(false);

    terminar({ id: 9, name: 'Atendente 2' });
    await flushPromises();
    expect(wrapper.find('[data-sucesso]').exists()).toBe(true);
  });
});
