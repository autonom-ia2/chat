import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import { useAlert } from 'dashboard/composables';
import AcharListasPage from '../pages/AcharListasPage.vue';
import AcharListaPage from '../pages/AcharListaPage.vue';
import AcharListasDaEmpresa from '../components/AcharListasDaEmpresa.vue';
import AcharCanaisDesligados from '../components/AcharCanaisDesligados.vue';

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
  lead_id: id + 100,
  ...extra,
});
const aberta = (extra = {}, membros = [membro(1), membro(2)], meta = {}) => ({
  data: {
    payload: { ...LISTA, ...extra, members: membros },
    meta: {
      total_count: membros.length,
      per_page: 25,
      has_more: false,
      ...meta,
    },
  },
});
const travada = () =>
  Object.assign(new Error('x'), {
    response: { data: { code: 'prospecting.audience.audience_locked' } },
  });

// As páginas montadas saem no fim de cada teste: uma página esquecida
// continuaria vigiando a rota (compartilhada) e pediria a lista de novo.
const montadas = [];
const montar = async pagina => {
  const wrapper = mount(pagina, { attachTo: document.body });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

describe('Suas listas e a lista aberta', () => {
  afterEach(() => {
    montadas.splice(0).forEach(wrapper => wrapper.unmount());
  });

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
        meta: { has_more: false },
      },
    });

    const wrapper = await montar(AcharListasPage);

    const cartoes = wrapper.findAll('[data-lista]');
    expect(cartoes).toHaveLength(2);
    expect(cartoes[0].find('[data-empresas]').text()).toBe('2 empresas');
    expect(cartoes[0].find('[data-numeros]').text()).toBe(
      '2 com WhatsApp · 1 com e-mail · 1 já no funil'
    );
    expect(wrapper.find('[data-ver-mais-listas]').exists()).toBe(false);
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

  // Revisão do #2775, item 13: um foco de teclado só por cartão.
  it('cada cartão tem um foco de teclado só, o "Abrir"', async () => {
    AutonomiaProspectingAPI.getAudiences.mockResolvedValue({
      data: { payload: [LISTA], meta: { has_more: false } },
    });

    const wrapper = await montar(AcharListasPage);

    const cartao = wrapper.find('[data-lista]');
    const focaveis = cartao.findAll('button, a[href], [tabindex]');
    expect(focaveis).toHaveLength(1);
    expect(focaveis[0].attributes('data-abrir-lista')).toBeDefined();

    await cartao.find('[data-lista-corpo]').trigger('click');
    expect(push).toHaveBeenCalledTimes(1);
    await cartao.find('[data-abrir-lista]').trigger('click');
    expect(push).toHaveBeenCalledTimes(2);
  });

  // Revisão do #2775, item 1: quem tem mais de 25 listas acha todas.
  it('"Ver mais listas" traz as seguintes pelo cursor até acabar', async () => {
    AutonomiaProspectingAPI.getAudiences
      .mockResolvedValueOnce({
        data: {
          payload: [LISTA],
          meta: { has_more: true, next_before_at: 'T1', next_before_id: 4 },
        },
      })
      .mockResolvedValueOnce({
        data: {
          payload: [{ ...LISTA, id: 26, name: 'A 26ª' }],
          meta: { has_more: false, next_before_id: null },
        },
      });

    const wrapper = await montar(AcharListasPage);
    expect(wrapper.findAll('[data-lista]')).toHaveLength(1);

    await wrapper.find('[data-ver-mais-listas]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getAudiences).toHaveBeenLastCalledWith({
      depois: { em: 'T1', id: 4 },
      leadIds: [],
    });
    expect(wrapper.findAll('[data-lista]')).toHaveLength(2);
    expect(wrapper.text()).toContain('A 26ª');
    expect(wrapper.find('[data-ver-mais-listas]').exists()).toBe(false);
  });

  // Revisão do #2775, rodada 2, item 1: o clique duplo não pula uma página.
  it('clique duplo em "Ver mais listas" pede uma página só e desliga o botão', async () => {
    AutonomiaProspectingAPI.getAudiences.mockResolvedValueOnce({
      data: {
        payload: [LISTA],
        meta: { has_more: true, next_before_at: 'T1', next_before_id: 4 },
      },
    });
    let terminar;
    AutonomiaProspectingAPI.getAudiences.mockReturnValueOnce(
      new Promise(resolve => {
        terminar = resolve;
      })
    );

    const wrapper = await montar(AcharListasPage);
    const botao = wrapper.find('[data-ver-mais-listas]');
    await botao.trigger('click');
    await botao.trigger('click');
    expect(botao.attributes('disabled')).toBeDefined();
    terminar({
      data: {
        payload: [{ ...LISTA, id: 26, name: 'A 26ª' }],
        meta: { has_more: false, next_before_id: null },
      },
    });
    await flushPromises();

    expect(AutonomiaProspectingAPI.getAudiences).toHaveBeenCalledTimes(2);
    expect(wrapper.findAll('[data-lista]')).toHaveLength(2);
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

  // Revisão do #2775, item 2: "Ver mais" pelo cursor, sem pular quem vem depois.
  it('"Ver mais" pede as empresas depois da última linha, mesmo depois de tirar', async () => {
    rota.name = 'autonomia_prospecting_achar_lista';
    rota.params = { accountId: '1', listaId: '4' };
    AutonomiaProspectingAPI.getAudience
      .mockResolvedValueOnce(
        aberta({}, [membro(1), membro(2)], {
          total_count: 3,
          next_after: 2,
          has_more: true,
        })
      )
      .mockResolvedValueOnce(aberta({}, [membro(3)], { total_count: 2 }));
    AutonomiaProspectingAPI.removeFromAudience.mockResolvedValue({
      data: { payload: { audience: LISTA, removed_contact_ids: [1] } },
    });

    const wrapper = await montar(AcharListaPage);
    await wrapper.find('[data-tirar]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-ver-mais]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getAudience).toHaveBeenLastCalledWith('4', {
      after: 2,
    });
    expect(wrapper.findAll('[data-membro]').map(item => item.text())).toEqual([
      expect.stringContaining('Pessoa 2'),
      expect.stringContaining('Pessoa 3'),
    ]);
    expect(wrapper.find('[data-ver-mais]').exists()).toBe(false);
  });

  // Revisão do #2775, item 12: a lista virou "já enviada" com a tela aberta.
  it('tirar de uma lista que virou enviada: a frase própria e a tela recarrega enviada', async () => {
    rota.name = 'autonomia_prospecting_achar_lista';
    rota.params = { accountId: '1', listaId: '4' };
    AutonomiaProspectingAPI.getAudience
      .mockResolvedValueOnce(aberta())
      .mockResolvedValueOnce(aberta({ locked: true }));
    AutonomiaProspectingAPI.removeFromAudience.mockRejectedValue(travada());

    const wrapper = await montar(AcharListaPage);
    await wrapper.find('[data-tirar]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Esta lista acabou de ser usada numa campanha enviada e não muda mais. Para mudar, crie uma cópia.'
    );
    expect(AutonomiaProspectingAPI.getAudience).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-aviso-enviada]').exists()).toBe(true);
    expect(wrapper.find('[data-tirar]').exists()).toBe(false);
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

  // Revisão do #2775, itens 3 e 10: um clique duplo cria uma cópia só, e a tela
  // diz quantas empresas não foram para a cópia.
  it('clique duplo em "Criar uma cópia" cria uma só e diz quem ficou de fora', async () => {
    rota.name = 'autonomia_prospecting_achar_lista';
    rota.params = { accountId: '1', listaId: '4' };
    AutonomiaProspectingAPI.getAudience.mockResolvedValue(
      aberta({ locked: true })
    );
    let terminar;
    AutonomiaProspectingAPI.copyAudience.mockReturnValue(
      new Promise(resolve => {
        terminar = resolve;
      })
    );

    const wrapper = await montar(AcharListaPage);
    const botao = wrapper.find('[data-rodape] button');
    await botao.trigger('click');
    await botao.trigger('click');
    expect(botao.attributes('disabled')).toBeDefined();
    terminar({
      data: { payload: { ...LISTA, id: 9, skipped_contact_ids: [7] } },
    });
    await flushPromises();

    expect(AutonomiaProspectingAPI.copyAudience).toHaveBeenCalledTimes(1);
    expect(useAlert).toHaveBeenCalledWith(
      'Pronto. A cópia foi criada sem 1 empresa que não pode mais receber mensagem.'
    );
  });

  // Nota da Campanhas no #2797: quem cai num canal desligado fica sabendo.
  it('no pronto, avisa o canal desligado que ganhou gente, com plural e o caminho para ligar', async () => {
    rota.params = { accountId: '1' };
    const aviso = mount(AcharCanaisDesligados, {
      props: {
        canais: [
          { canal: 'email', n: 3 },
          { canal: 'whatsapp', n: 1 },
        ],
      },
    });

    expect(aviso.find('[data-canal-desligado="email"]').text()).toBe(
      '3 entraram, mas o e-mail desta lista está desligado. Para ligar, vá em Campanhas › Públicos.'
    );
    expect(aviso.find('[data-canal-desligado="whatsapp"]').text()).toBe(
      '1 entrou, mas o WhatsApp desta lista está desligado. Para ligar, vá em Campanhas › Públicos.'
    );
    await aviso.find('[data-ir-para-publicos]').trigger('click');
    expect(push).toHaveBeenCalledWith({
      name: 'campaigns_journey_audiences',
      params: { accountId: '1' },
    });
    aviso.unmount();

    const nada = mount(AcharCanaisDesligados, { props: { canais: [] } });
    expect(nada.find('[data-canais-desligados]').isVisible()).toBe(false);
    nada.unmount();
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
