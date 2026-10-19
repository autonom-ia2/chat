import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import PassagemListaPage from './PassagemListaPage.vue';

const estado = vi.hoisted(() => ({
  push: vi.fn(),
  query: {},
  params: { accountId: '16', pipelineId: '6' },
  admin: true,
  recursos: ['assignment_v2'],
  funis: [],
  ajustes: {},
  falhaFunis: false,
}));

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: estado.push }),
  useRoute: () => ({ query: estado.query, params: estado.params }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(estado.admin) }),
}));
// #1797: a volta também olha assignment_manage; aqui a função não tem.
vi.mock('dashboard/composables/useCanManage', () => ({
  useHasCustomRolePermission: () => ref(false),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    ref((_conta, recurso) => estado.recursos.includes(recurso)),
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getPipelines: () =>
      estado.falhaFunis
        ? Promise.reject(new Error('fora'))
        : Promise.resolve({ data: { payload: estado.funis } }),
    getAiSettings: id =>
      estado.ajustes[id]
        ? Promise.resolve({ data: { payload: estado.ajustes[id] } })
        : Promise.reject(new Error('sem')),
  },
}));

const E = 'CRM_KANBAN.PASSAGEM.LISTA.ESTADO';
const ligado = {
  enabled: true,
  handoff: { enabled: true, handoff_mode: 'r2_direct' },
  stages: [
    { handoff_custom: false },
    { handoff_custom: true, handoff: { enabled: false } },
  ],
};

const montar = async () => {
  const pagina = mount(PassagemListaPage);
  await flushPromises();
  return pagina;
};

beforeEach(() => {
  estado.push.mockReset();
  estado.admin = true;
  estado.recursos = ['assignment_v2'];
  estado.funis = [
    { id: 6, name: 'Email Comercial' },
    { id: 7, name: 'Funil Agger' },
    { id: 8, name: 'Suporte' },
  ];
  estado.ajustes = { 6: ligado, 7: { enabled: false } };
  estado.falhaFunis = false;
});

describe('PassagemListaPage', () => {
  it('mostra um cartão por funil, com o estado em frase', async () => {
    const pagina = await montar();
    const cartoes = pagina.findAll('[data-funil-cartao]');
    expect(cartoes).toHaveLength(3);
    expect(cartoes[0].text()).toContain('Email Comercial');
    expect(cartoes[0].text()).toContain(`${E}.PARTE`);
    expect(cartoes[1].text()).toContain(`${E}.SEM_ASSISTENTE`);
    expect(cartoes[2].text()).toContain(`${E}.SEM_SITUACAO`);
  });

  it('abrir um funil vai para a tela dele', async () => {
    const pagina = await montar();
    await pagina.find('[data-funil-cartao="7"]').trigger('click');
    expect(estado.push).toHaveBeenCalledWith({
      name: 'crm_handoff_settings_edit',
      params: { pipelineId: 7 },
    });
  });

  it('a seta e o X do administrador voltam para Atribuição de agentes', async () => {
    const pagina = await montar();
    expect(pagina.find('[data-passagem-voltar]').text()).toBe(
      'ASSIGNMENT_POLICY.INDEX.HEADER.TITLE'
    );
    await pagina.find('[data-passagem-voltar]').trigger('click');
    await pagina.find('[data-passagem-fechar]').trigger('click');
    expect(estado.push.mock.calls).toEqual([
      [{ name: 'assignment_policy_index' }],
      [{ name: 'assignment_policy_index' }],
    ]);
  });

  it('quem não chega em Atribuição volta para o Kanban', async () => {
    estado.admin = false;
    const pagina = await montar();
    await pagina.find('[data-passagem-fechar]').trigger('click');
    expect(estado.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
  });

  it('sem funil: estado vazio com o caminho para criar um', async () => {
    estado.funis = [];
    const pagina = await montar();
    expect(pagina.find('[data-lista-vazia]').exists()).toBe(true);
    await pagina.find('[data-lista-vazia] button').trigger('click');
    expect(estado.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
  });

  it('erro ao carregar: aviso com "Tentar de novo" que carrega de novo', async () => {
    estado.falhaFunis = true;
    const pagina = await montar();
    expect(pagina.find('[role="alert"]').exists()).toBe(true);
    estado.falhaFunis = false;
    await pagina.find('[role="alert"] button').trigger('click');
    await flushPromises();
    expect(pagina.findAll('[data-funil-cartao]')).toHaveLength(3);
  });
});
