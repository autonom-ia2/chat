import { ref } from 'vue';
import { usePassagemVolta } from './usePassagemVolta';

const estado = vi.hoisted(() => ({
  query: {},
  params: { accountId: '16', pipelineId: '6' },
  admin: true,
  recursos: ['assignment_v2'],
}));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ query: estado.query, params: estado.params }),
}));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: ref(estado.admin) }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () =>
    ref((_conta, recurso) => estado.recursos.includes(recurso)),
}));

beforeEach(() => {
  estado.query = {};
  estado.admin = true;
  estado.recursos = ['assignment_v2'];
});

describe('usePassagemVolta: a tela de um funil', () => {
  it('aberta pela lista: volta para "Todos os funis"', () => {
    const { doFunil } = usePassagemVolta();
    expect(doFunil.value).toEqual({
      rotulo: 'CRM_KANBAN.PASSAGEM.HEROI.TODOS_OS_FUNIS',
      destino: { name: 'crm_handoff_settings_index' },
    });
  });

  it('aberta pelo Kanban: volta para o Kanban, no mesmo funil', () => {
    estado.query = { from: 'crm' };
    const { doFunil } = usePassagemVolta();
    expect(doFunil.value).toEqual({
      rotulo: 'CRM_KANBAN.PASSAGEM.HEROI.VOLTAR_KANBAN',
      destino: { name: 'crm_kanban_index', query: { pipeline_id: '6' } },
    });
  });
});

describe('usePassagemVolta: a lista de funis', () => {
  it('administrador com Atribuição: volta para Atribuição de agentes', () => {
    expect(usePassagemVolta().daLista.value.destino).toEqual({
      name: 'assignment_policy_index',
    });
  });

  it('conta sem Atribuição, ou sem ser administrador: volta para o Kanban', () => {
    estado.recursos = [];
    expect(usePassagemVolta().daLista.value.destino).toEqual({
      name: 'crm_kanban_index',
    });
    estado.recursos = ['assignment_v2'];
    estado.admin = false;
    expect(usePassagemVolta().daLista.value.destino).toEqual({
      name: 'crm_kanban_index',
    });
  });
});
