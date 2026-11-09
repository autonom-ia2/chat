import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import AcharListasPage from '../pages/AcharListasPage.vue';
import AcharListaPage from '../pages/AcharListaPage.vue';
import AcharListasDaEmpresa from '../components/AcharListasDaEmpresa.vue';

// #2775 — F6, a aba "Suas listas" e a lista aberta, pela API: os números de
// cada lista, abrir, tirar com Desfazer e, na lista já enviada, "Criar uma
// cópia para editar" no lugar de "Tirar".
const { rota, push, permissao } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  const estado = reactive({
    name: 'autonomia_prospecting_achar_listas',
    params: { accountId: '1' },
    query: {},
  });
  return {
    rota: estado,
    permissao: { campanha: true },
    push: vi.fn(async destino => {
      estado.name = destino.name;
      estado.params = { ...destino.params };
      estado.query = { ...destino.query };
    }),
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = {
    getCurrentAccountId: 1,
    getCurrentUser: { id: 7 },
    'accounts/isFeatureEnabledonAccount': () => true,
  };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({ canManagePipelines: computed(() => false) }),
    };
  }
);
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return {
    useCanManage: () => computed(() => true),
    usePermissionGranted: chave =>
      computed(() => chave === 'campaign_manage' && permissao.campanha),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getAudiences: vi.fn(),
    getAudience: vi.fn(),
    removeFromAudience: vi.fn(),
    restoreToAudience: vi.fn(),
    copyAudience: vi.fn(),
    getLeadAudiences: vi.fn(),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({ default: {} }));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const LISTA = {
  id: 4,
  name: 'Padarias · Centro',
  companies: 2,
  whatsapp: 2,
  email: 1,
  in_crm: 1,
  called: 1,
  locked: false,
};
const membro = (id, extra = {}) => ({
  contact_id: id,
  row_number: id,
  name: `Pessoa ${id}`,
  company_name: `Padaria ${id}`,
  whatsapp: true,
  email: false,
  in_crm: false,
  called: false,
  lead_id: id + 100,
  ...extra,
});
const aberta = (extra = {}, membros = [membro(1), membro(2)]) => ({
  data: {
    payload: { ...LISTA, ...extra, members: membros },
    meta: { total_count: membros.length, per_page: 25 },
  },
});

const montar = async pagina => {
  const wrapper = mount(pagina, { attachTo: document.body });
  await flushPromises();
  return wrapper;
};

describe('Suas listas e a lista aberta', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    permissao.campanha = true;
    window.globalConfig = {
      CAMPAIGN_JOURNEY_ENABLED: 'true',
      CAMPAIGN_IMPORT_ENABLED: 'true',
    };
    rota.name = 'autonomia_prospecting_achar_listas';
    rota.params = { accountId: '1' };
    rota.query = {};
  });

  it('a aba mostra cada lista com os números e a marca "Já enviada"', async () => {
    AutonomiaProspectingAPI.getAudiences.mockResolvedValue({
      data: {
        payload: [LISTA, { ...LISTA, id: 5, name: 'Antiga', locked: true }],
      },
    });

    const wrapper = await montar(AcharListasPage);

    const cartoes = wrapper.findAll('[data-lista]');
    expect(cartoes).toHaveLength(2);
    expect(cartoes[0].find('[data-empresas]').text()).toBe('2 empresas');
    expect(cartoes[0].find('[data-numeros]').text()).toBe(
      '2 com WhatsApp · 1 com e-mail · 1 já no funil · 1 já chamada'
    );
    expect(cartoes[0].find('[data-enviada]').exists()).toBe(false);
    expect(cartoes[1].find('[data-enviada]').text()).toBe('Já enviada');
    expect(wrapper.find('[data-aba="listas"]').attributes('aria-current')).toBe(
      'page'
    );

    await cartoes[0].find('[data-abrir-lista]').trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'autonomia_prospecting_achar_lista',
        params: expect.objectContaining({ listaId: 4 }),
      })
    );
  });

  it('sem gerenciar campanhas, a aba diz por que não mostra nada e não pede listas', async () => {
    permissao.campanha = false;

    const wrapper = await montar(AcharListasPage);

    expect(wrapper.find('[data-sem-permissao]').exists()).toBe(true);
    expect(wrapper.find('[data-abas]').exists()).toBe(false);
    expect(AutonomiaProspectingAPI.getAudiences).not.toHaveBeenCalled();
  });

  it('tirar uma empresa grava na hora e o Desfazer a devolve', async () => {
    rota.name = 'autonomia_prospecting_achar_lista';
    rota.params = { accountId: '1', listaId: '4' };
    AutonomiaProspectingAPI.getAudience.mockResolvedValue(aberta());
    AutonomiaProspectingAPI.removeFromAudience.mockResolvedValue({
      data: {
        payload: {
          audience: { ...LISTA, companies: 1 },
          removed_contact_ids: [1],
        },
      },
    });
    AutonomiaProspectingAPI.restoreToAudience.mockResolvedValue({
      data: { payload: { audience: LISTA } },
    });

    const wrapper = await montar(AcharListaPage);
    expect(wrapper.findAll('[data-membro]')).toHaveLength(2);

    await wrapper.find('[data-tirar]').trigger('click');
    await flushPromises();
    expect(AutonomiaProspectingAPI.removeFromAudience).toHaveBeenCalledWith(
      '4',
      {
        contactIds: [1],
        leadIds: [],
      }
    );
    expect(wrapper.findAll('[data-membro]')).toHaveLength(1);
    expect(wrapper.find('[data-empresas]').text()).toBe('1 empresa');
    expect(wrapper.find('[data-aviso-tirou]').text()).toContain(
      'Pessoa 1 saiu da lista.'
    );

    await wrapper.find('[data-aviso-tirou] button').trigger('click');
    await flushPromises();
    expect(AutonomiaProspectingAPI.restoreToAudience).toHaveBeenCalledWith(
      '4',
      {
        contactIds: [1],
      }
    );
    expect(wrapper.findAll('[data-membro]')).toHaveLength(2);
  });

  it('a lista editável abre a Nova campanha com ela no "Criar a mensagem"', async () => {
    rota.name = 'autonomia_prospecting_achar_lista';
    rota.params = { accountId: '1', listaId: '4' };
    AutonomiaProspectingAPI.getAudience.mockResolvedValue(aberta());

    const wrapper = await montar(AcharListaPage);
    await wrapper.find('[data-rodape] button').trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_new',
      params: { accountId: '1' },
      query: { audience: '4' },
    });
  });

  it('a lista já enviada não oferece "Tirar" e cria uma cópia para editar', async () => {
    rota.name = 'autonomia_prospecting_achar_lista';
    rota.params = { accountId: '1', listaId: '4' };
    AutonomiaProspectingAPI.getAudience.mockResolvedValue(
      aberta({ locked: true })
    );
    AutonomiaProspectingAPI.copyAudience.mockResolvedValue({
      data: { payload: { ...LISTA, id: 9, name: 'Padarias · Centro (cópia)' } },
    });

    const wrapper = await montar(AcharListaPage);
    expect(wrapper.find('[data-aviso-enviada]').exists()).toBe(true);
    expect(wrapper.find('[data-tirar]').exists()).toBe(false);
    expect(wrapper.find('[data-rodape] button').text()).toContain(
      'Criar uma cópia para editar'
    );

    await wrapper.find('[data-rodape] button').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.copyAudience).toHaveBeenCalledWith(4);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. A cópia foi criada e já pode ser mudada.'
    );
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'autonomia_prospecting_achar_lista',
        params: expect.objectContaining({ listaId: 9 }),
      })
    );
  });

  it('na gaveta: "Está na lista X · Tirar", e a enviada só tem o selo', async () => {
    AutonomiaProspectingAPI.getLeadAudiences.mockResolvedValue({
      data: {
        payload: [
          { id: 4, name: 'Padarias', locked: false },
          { id: 5, name: 'Antiga', locked: true },
        ],
      },
    });
    AutonomiaProspectingAPI.removeFromAudience.mockResolvedValue({
      data: { payload: { audience: LISTA, removed_contact_ids: [1] } },
    });

    const wrapper = mount(AcharListasDaEmpresa, { props: { empresaId: 101 } });
    await flushPromises();

    const linhas = wrapper.findAll('[data-lista-da-empresa]');
    expect(linhas.map(linha => linha.text())).toEqual([
      expect.stringContaining('Está na lista Padarias'),
      expect.stringContaining('Já enviada'),
    ]);
    expect(linhas[1].find('[data-tirar-da-lista]').exists()).toBe(false);

    await wrapper.find('[data-tirar-da-lista]').trigger('click');
    await flushPromises();
    expect(AutonomiaProspectingAPI.removeFromAudience).toHaveBeenCalledWith(4, {
      contactIds: [],
      leadIds: [101],
    });
    expect(wrapper.find('[data-saiu-da-lista]').text()).toContain(
      'Saiu da lista Padarias.'
    );
  });
});
