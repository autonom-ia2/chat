import { flushPromises, mount } from '@vue/test-utils';
import { PRESETS } from '../../customRoles/permissionMatrix';
import FuncaoGuiadaPage from '../guiada/FuncaoGuiadaPage.vue';
import { global, loja } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 5.B, 5.C e Guarda: a conversa guiada de ponta a ponta, com a Carla.
const { rota, push, replace, saida } = vi.hoisted(() => ({
  rota: { name: '', params: {}, query: {} },
  push: vi.fn(),
  replace: vi.fn(),
  saida: { guarda: null },
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
const AGENTES = [{ id: 10, name: 'Ana', role: 'agent', custom_role_id: 1 }];

const montar = async ({
  name = 'funcoes_equipe_new',
  params = {},
  query = {},
} = {}) => {
  Object.assign(rota, { name, params: { accountId: '1', ...params }, query });
  const criar = vi.fn(async (_contexto, dados) => ({ id: 9, ...dados }));
  const store = loja({
    giver: CARLA,
    funcoes: [ATENDENTE, GERENTE, ACIMA],
    agentes: AGENTES,
    actions: { 'customRole/createCustomRole': criar },
  });
  const wrapper = mount(FuncaoGuiadaPage, {
    attachTo: document.body,
    global: {
      ...global(store),
      stubs: {
        ...global(store).stubs,
        AssignAgentsDialog: true,
      },
    },
  });
  await flushPromises();
  return { wrapper, criar };
};

const clicar = async (wrapper, seletor) => {
  await wrapper.find(seletor).trigger('click');
  await flushPromises();
};

afterEach(() => {
  document.body.innerHTML = '';
  push.mockReset();
  replace.mockReset();
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
      'Relatórios, Desempenho da equipe e mais 11 áreas'
    );
    expect(wrapper.find('[data-recolhida]').text()).toContain(
      'Hoje só olha a Central de Ajuda (artigos para os clientes). As outras estão desligadas.'
    );
    expect(wrapper.find('[data-previa] [data-frase]').text()).toContain(
      'Quem for Atendente atende'
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
      'O que o Atendente faz com os contatos?'
    );
    await clicar(wrapper, '[data-nivel="manage"]');
    await clicar(wrapper, '[data-botao-grande]');

    const contatos = wrapper.find('[data-linha="contatos"]');
    expect(contatos.text()).toContain('Pode mexer');
    expect(contatos.text()).toContain('você mudou');
    expect(contatos.text()).toContain('· antes: só olha');
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

  it('duplicar uma função acima do alcance volta para a lista', async () => {
    await montar({ name: 'funcoes_equipe_duplicate', params: { roleId: '3' } });
    expect(replace).toHaveBeenCalledWith({ name: 'funcoes_equipe_list' });
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
});
