import { nextTick } from 'vue';
import { config, flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/prospectingAchar.json';
import AutonomiaProspectingAPI from 'dashboard/api/autonomiaProspecting';
import AcharBuscasPage from '../pages/AcharBuscasPage.vue';
import AcharPortaPage from '../pages/AcharPortaPage.vue';

// #2693 — "Suas buscas" e as últimas buscas da porta pela fonte da API (sem
// ?demo=), com o dono de cada busca vindo de user_id/user_name: quem não vê as
// de todos só vê as próprias; "da equipe" e "Feita por" dependem de
// "Ver buscas de todos" e de haver busca de outra pessoa; a busca sem dono não
// diz "Feita por você"; "Ver mais" lê a próxima página; "Buscar de novo" faz
// uma busca nova e abre a lista dela na rota NOVA.
const { rota, push, permissao } = await vi.hoisted(async () => {
  const { reactive } = await import('vue');
  return {
    rota: reactive({ name: '', params: { accountId: '1' }, query: {} }),
    push: vi.fn(),
    permissao: { verTodas: false, buscar: true },
  };
});

vi.mock('vue-router', () => ({
  useRoute: () => rota,
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const valores = { getCurrentAccountId: 1, getCurrentUser: { id: 7 } };
  return { useMapGetter: nome => computed(() => valores[nome]) };
});
// Trocar o dono (#2694) é crm_manage_pipelines: aqui ninguém gere funis.
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
    useCanManage: () => computed(() => permissao.buscar),
    usePermissionGranted: () => computed(() => permissao.verTodas),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/autonomiaProspecting', () => ({
  default: {
    getSettings: vi.fn(),
    getSearches: vi.fn(),
    createSearch: vi.fn(),
    deleteSearch: vi.fn(),
  },
}));

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const search = (id, extra = {}) => ({
  id,
  query: `Busca ${id}`,
  location: 'Centro, Campinas, SP',
  location_label: 'Centro, Campinas, SP',
  radius: 3000,
  requested_radius: 3000,
  area_type: 'radius',
  area_config: { radius: 3000 },
  requested_limit: 20,
  results_count: 10,
  crm_count: 2,
  created_at: new Date().toISOString(),
  user_id: 7,
  user_name: 'Lucas',
  ...extra,
});
const MINHA = search(1);
const DA_PAULA = search(2, { user_id: 8, user_name: 'Paula' });
const SEM_DONO = search(3, { user_id: null, user_name: null });

const responder = (payload, meta = { has_more: false }) =>
  AutonomiaProspectingAPI.getSearches.mockResolvedValueOnce({
    data: { payload, meta },
  });

const montar = async pagina => {
  const wrapper = mount(pagina);
  await flushPromises();
  return wrapper;
};
const titulo = wrapper => wrapper.find('h1').text();
const cartoes = wrapper => wrapper.findAll('[data-busca]');
const feitaPor = wrapper =>
  cartoes(wrapper).map(cartao =>
    cartao.find('[data-feita-por]').exists()
      ? cartao.find('[data-feita-por]').text()
      : ''
  );

describe('Suas buscas pela API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    permissao.verTodas = false;
    permissao.buscar = true;
    rota.name = 'autonomia_prospecting_achar_buscas';
    rota.query = {};
  });

  it('sem "Ver buscas de todos" mostra só as próprias, sem "Feita por"', async () => {
    responder([MINHA, DA_PAULA, SEM_DONO]);
    const wrapper = await montar(AcharBuscasPage);

    expect(titulo(wrapper)).toBe('Suas buscas');
    expect(cartoes(wrapper)).toHaveLength(1);
    expect(cartoes(wrapper)[0].text()).toContain('Busca 1 · Centro');
    expect(feitaPor(wrapper)).toEqual(['']);
  });

  it('o administrador com só as próprias continua em "Suas buscas"', async () => {
    permissao.verTodas = true;
    responder([MINHA]);
    const wrapper = await montar(AcharBuscasPage);

    expect(titulo(wrapper)).toBe('Suas buscas');
    expect(feitaPor(wrapper)).toEqual(['']);
  });

  it('com busca de outra pessoa vira "Buscas da equipe"; a sem dono não diz "você"', async () => {
    permissao.verTodas = true;
    responder([MINHA, DA_PAULA, SEM_DONO]);
    const wrapper = await montar(AcharBuscasPage);

    expect(titulo(wrapper)).toBe('Buscas da equipe');
    expect(feitaPor(wrapper)).toEqual([
      'Feita por você',
      'Feita por Paula',
      '',
    ]);
  });

  // Vídeo da F6: o título não aparece como "Suas buscas" e depois vira "Buscas
  // da equipe"; até a primeira leitura, um esqueleto.
  it('o título não troca: esqueleto até as buscas chegarem, depois "Buscas da equipe"', async () => {
    permissao.verTodas = true;
    let responderBuscas;
    AutonomiaProspectingAPI.getSearches.mockReturnValueOnce(
      new Promise(resolve => {
        responderBuscas = resolve;
      })
    );
    const wrapper = mount(AcharBuscasPage);
    const vistos = [];
    const anotar = () => vistos.push(titulo(wrapper));
    await nextTick();
    anotar();
    expect(wrapper.find('[data-titulo-carregando]').exists()).toBe(true);

    responderBuscas({
      data: { payload: [MINHA, DA_PAULA], meta: { has_more: false } },
    });
    await flushPromises();
    anotar();

    expect(vistos).toEqual(['', 'Buscas da equipe']);
    expect(wrapper.find('[data-titulo-carregando]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('"Apagar" só no menu da busca de quem está logado', async () => {
    permissao.verTodas = true;
    responder([MINHA, DA_PAULA]);
    const wrapper = await montar(AcharBuscasPage);
    const acoesDo = async indice => {
      await cartoes(wrapper)[indice].find('[data-mais-busca]').trigger('click');
      return cartoes(wrapper)
        [indice].findAll('[role="menuitem"]')
        .map(item => item.text());
    };

    expect(await acoesDo(0)).toContain('Apagar');
    expect(await acoesDo(1)).not.toContain('Apagar');
  });

  it('"Ver mais" traz a próxima página (meta.has_more)', async () => {
    responder([MINHA], { has_more: true });
    responder([search(4)], { has_more: false });
    const wrapper = await montar(AcharBuscasPage);

    await wrapper.find('[data-ver-mais]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.getSearches).toHaveBeenLastCalledWith({
      page: 2,
    });
    expect(cartoes(wrapper)).toHaveLength(2);
    expect(wrapper.find('[data-ver-mais]').exists()).toBe(false);
  });

  it('apagar uma busca e depois "Ver mais" não pula nenhuma', async () => {
    // Servidor com 3 por página: 1..3, 4..6. Depois de apagar a 1, a
    // página 2 começa na 5; a 4 só volta relendo a partir da página 1.
    const todas = [1, 2, 3, 4, 5, 6].map(id => search(id));
    let restantes = [...todas];
    const POR_PAGINA = 3;
    AutonomiaProspectingAPI.getSearches.mockImplementation(({ page }) =>
      Promise.resolve({
        data: {
          payload: restantes.slice((page - 1) * POR_PAGINA, page * POR_PAGINA),
          meta: { has_more: page * POR_PAGINA < restantes.length },
        },
      })
    );
    AutonomiaProspectingAPI.deleteSearch.mockImplementation(id => {
      restantes = restantes.filter(busca => busca.id !== id);
      return Promise.resolve({});
    });
    const wrapper = await montar(AcharBuscasPage);

    await cartoes(wrapper)[0].find('[data-mais-busca]').trigger('click');
    await cartoes(wrapper)[0]
      .findAll('[role="menuitem"]')
      .find(item => item.text() === 'Apagar')
      .trigger('click');
    await wrapper.find('[data-confirmar-apagar]').trigger('click');
    await flushPromises();
    await wrapper.find('[data-ver-mais]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.deleteSearch).toHaveBeenCalledWith(1);
    expect(cartoes(wrapper).map(cartao => cartao.text())).toEqual(
      [2, 3, 4, 5, 6].map(id => expect.stringContaining(`Busca ${id} ·`))
    );
    expect(wrapper.find('[data-ver-mais]').exists()).toBe(false);
  });

  it('quem só vê recebe um aviso que não promete as buscas da equipe', async () => {
    permissao.buscar = false;
    rota.query = { aviso: 'so-ver' };
    responder([]);
    const wrapper = await montar(AcharBuscasPage);

    expect(wrapper.text()).toContain(
      'Seu acesso à Prospecção é só para ver: você não faz busca nova.'
    );
    expect(wrapper.text()).not.toContain('buscas da equipe, mas');
  });

  it('"Buscar de novo" cria uma busca nova sem cache e abre a lista dela', async () => {
    responder([MINHA]);
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: { id: 90 } } },
    });
    const wrapper = await montar(AcharBuscasPage);

    await cartoes(wrapper)[0].find('[data-mais-busca]').trigger('click');
    const botao = cartoes(wrapper)[0]
      .findAll('[role="menuitem"]')
      .find(item => item.text() === 'Buscar de novo');
    await botao.trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith(
      expect.objectContaining({ query: 'Busca 1', radius: 3000, fresh: true })
    );
    expect(push).toHaveBeenLastCalledWith(
      expect.objectContaining({
        name: 'autonomia_prospecting_achar_nova',
        params: expect.objectContaining({ searchId: 90 }),
      })
    );
  });
});

describe('Últimas buscas da porta pela API', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    permissao.verTodas = false;
    rota.name = 'autonomia_prospecting_achar';
    rota.query = {};
    AutonomiaProspectingAPI.getSettings.mockResolvedValue({
      data: { payload: {} },
    });
  });

  it('os painéis da porta guardam o que foi escolhido e os ajustes chegam ao servidor', async () => {
    responder([
      search(1, { location_place_id: 'p1', location_label: 'Centro' }),
    ]);
    AutonomiaProspectingAPI.createSearch.mockResolvedValue({
      data: { payload: { search: { id: 91 } } },
    });
    const wrapper = await montar(AcharPortaPage);
    const escolha = rotulo =>
      wrapper.findAll('[data-escolha]').find(item => item.text() === rotulo);
    const abrirComo = () =>
      wrapper.find('[data-linha-frase] [data-alterar]').trigger('click');
    const frase = () => wrapper.find('[data-linha-frase]').text();

    // "Como procurar": 10 km; vai a "Mais ajustes" e volta: os 10 km ficam.
    await abrirComo();
    await escolha('Na cidade · 10 km').trigger('click');
    await wrapper.find('[data-mais-ajustes]').trigger('click');
    await wrapper
      .find('[data-secao="site"]')
      .findAll('[data-escolha]')[1]
      .trigger('click');
    await wrapper.find('[data-aplicar]').trigger('click');
    expect(escolha('Na cidade · 10 km').attributes('aria-checked')).toBe(
      'true'
    );
    await wrapper.find('[data-salvar]').trigger('click');
    expect(frase()).toContain('Até 10 km');
    expect(frase()).toContain('+ 1 ajuste');

    // Reabrir "Mais ajustes" mostra o "Tem site"; "Pronto" não apaga nada.
    await abrirComo();
    await wrapper.find('[data-mais-ajustes]').trigger('click');
    expect(
      wrapper
        .find('[data-secao="site"]')
        .findAll('[data-escolha]')[1]
        .attributes('aria-checked')
    ).toBe('true');
    await wrapper.find('[data-aplicar]').trigger('click');
    await wrapper.find('[data-salvar]').trigger('click');
    expect(frase()).toContain('+ 1 ajuste');

    // Cancelar "Como procurar" (Fechar) descarta o rascunho.
    await abrirComo();
    await escolha('Bem perto · 1 km').trigger('click');
    await wrapper.find('[data-fechar]').trigger('click');
    expect(frase()).toContain('Até 10 km');

    await wrapper.find('input').setValue('Padarias');
    await wrapper.find('[data-principal]').trigger('click');
    await flushPromises();

    expect(AutonomiaProspectingAPI.createSearch).toHaveBeenCalledWith(
      expect.objectContaining({
        query: 'Padarias',
        radius: 10000,
        metadata: expect.objectContaining({
          advanced_filters: { has_website: 'yes' },
        }),
      })
    );
  });

  it('sem "Ver buscas de todos" mostra só as próprias (user_id)', async () => {
    responder([DA_PAULA, MINHA, SEM_DONO]);
    const wrapper = await montar(AcharPortaPage);
    const ultimas = wrapper.find('[data-ultimas]');

    expect(ultimas.find('h2').text()).toBe('Suas últimas buscas');
    expect(cartoes(ultimas)).toHaveLength(1);
    expect(cartoes(ultimas)[0].text()).toContain('Busca 1');
  });

  it('com "Ver buscas de todos" mostra as da equipe com quem fez (user_name)', async () => {
    permissao.verTodas = true;
    responder([DA_PAULA, MINHA, SEM_DONO]);
    const wrapper = await montar(AcharPortaPage);
    const ultimas = wrapper.find('[data-ultimas]');

    expect(ultimas.find('h2').text()).toBe('Últimas buscas da equipe');
    expect(feitaPor(ultimas)).toEqual([
      'Feita por Paula',
      'Feita por você',
      '',
    ]);
  });
});
