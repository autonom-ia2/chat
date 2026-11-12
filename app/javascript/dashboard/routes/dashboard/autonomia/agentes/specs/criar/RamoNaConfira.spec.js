import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import RamoNaConfira from '../../components/criar/RamoNaConfira.vue';

// A gaveta abre num TeleportWithDirection, que lê a direção do texto na store.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ getters: {}, dispatch: vi.fn() }),
    useMapGetter: () => computed(() => false),
  };
});

// #2881 — o bloco do agente pronto por ramo no Confira. Perguntas e documentos pedem só a permissão da página; mexer
// nas ferramentas pede a chave "Ferramentas dos agentes" (a mesma do "Incluir" da vitrine). Sem ela, as ferramentas e
// a frase de cada uma aparecem, sem botões, e nenhuma mudança de ferramenta sai.
const FERRAMENTAS = [
  { fonte: 'cnpj', usar_quando: 'Use quando vier o CNPJ da empresa.' },
  { fonte: 'cep', usar_quando: 'Use quando vier o CEP da obra.' },
];
const TAMBEM = [{ fonte: 'cidades', usar_quando: 'Use quando vier a cidade.' }];
const PERGUNTAS = [{ id: 'p1', texto: 'Qual o CNPJ?', tirada: false }];

const comChave = () => ({
  visiveis: ref(['cnpj', 'cep']),
  combinaTambem: ref(['cidades']),
  escolhidas: ref(['cnpj', 'cep']),
  semPermissao: ref(false),
  podeIncluir: ref(true),
});
const semChave = () => ({
  visiveis: ref([]),
  combinaTambem: ref([]),
  escolhidas: ref(['cnpj', 'cep']),
  semPermissao: ref(true),
  podeIncluir: ref(false),
});

const montadas = [];
const montar = (prontas, ramo = {}) => {
  const doRamo = {
    perguntas: ref(PERGUNTAS),
    documentos: ref([]),
    ferramentas: ref(FERRAMENTAS),
    tambem: ref(TAMBEM),
    pagas: ref(['certidoes_empresa']),
    gravando: ref({}),
    mudar: vi.fn(),
    ...ramo,
  };
  const wrapper = mount(RamoNaConfira, {
    props: {
      ramo: doRamo,
      prontas,
      nome: 'Bia',
      podeMudar: true,
      linkDaVitrine: '/app/vitrine?agente=90',
    },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return { wrapper, ramo: doRamo };
};
const abrir = async (wrapper, linha) => {
  await wrapper.get(`[data-linha="${linha}"] button`).trigger('click');
  return document.body.querySelector('[role="dialog"]');
};

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('RamoNaConfira', () => {
  it('with the tools key, the tools can be removed, changed and joined by the "also fits" ones', async () => {
    const { wrapper, ramo } = montar(comChave());
    const gaveta = await abrir(wrapper, 'ferramentas');

    expect(gaveta.querySelectorAll('[data-ferramenta]')).toHaveLength(2);
    expect(gaveta.querySelector('[data-ja-vem]')).toBeNull();
    gaveta
      .querySelector('[data-ferramenta="cnpj"] [data-tirar-ferramenta]')
      .click();
    gaveta.querySelector('[data-incluir-tambem]').click();
    await flushPromises();

    expect(ramo.mudar.mock.calls).toEqual([
      ['ferramentas', [FERRAMENTAS[1]]],
      ['ferramentas', [...FERRAMENTAS, ...TAMBEM]],
    ]);
    expect(gaveta.querySelector('[data-quer-tambem]')).not.toBeNull();
  });

  it('a tools change keeps, in place, the tools of the server list that the screen does not show', async () => {
    const jaTem = { fonte: 'feriados', usar_quando: 'Use para contar prazo.' };
    const desconhecida = { fonte: 'fonte_nova', usar_quando: 'Use sempre.' };
    const doServidor = [FERRAMENTAS[0], desconhecida, FERRAMENTAS[1], jaTem];
    // `fonte_nova`: this screen's showcase does not know it. `feriados`: the agent already has it.
    const { wrapper, ramo } = montar(comChave(), {
      modelo: ref({ ferramentas: doServidor }),
      ferramentas: ref([FERRAMENTAS[0], FERRAMENTAS[1], jaTem]),
    });
    const gaveta = await abrir(wrapper, 'ferramentas');

    expect(gaveta.querySelectorAll('[data-ferramenta]')).toHaveLength(2);
    gaveta
      .querySelector('[data-ferramenta="cnpj"] [data-tirar-ferramenta]')
      .click();
    gaveta.querySelector('[data-incluir-tambem]').click();
    await flushPromises();

    expect(ramo.mudar.mock.calls).toEqual([
      ['ferramentas', [desconhecida, FERRAMENTAS[1], jaTem]],
      ['ferramentas', [...doServidor, ...TAMBEM]],
    ]);
  });

  it('without the tools key, shows the tools and each "Use when" sentence, with no button, and sends no tools change', async () => {
    const { wrapper, ramo } = montar(semChave());
    const gaveta = await abrir(wrapper, 'ferramentas');

    expect(
      [...gaveta.querySelectorAll('[data-quando]')].map(frase =>
        frase.textContent.trim()
      )
    ).toEqual(FERRAMENTAS.map(item => item.usar_quando));
    [
      '[data-tirar-ferramenta]',
      '[data-alterar-quando]',
      '[data-incluir-tambem]',
      '[data-ver-mais-ferramentas]',
      '[data-quer-tambem]',
      '[data-pode-alterar]',
    ].forEach(seletor => expect(gaveta.querySelector(seletor)).toBeNull());
    // O aviso de sempre: o agente começa sem elas.
    expect(gaveta.querySelector('[data-ja-vem]').textContent).toContain(
      'AGENTS.VITRINE.JA_VEM.SEM_PERMISSAO'
    );
    expect(ramo.mudar).not.toHaveBeenCalled();
  });

  it('without the tools key, questions and documents still change, and the change carries only that list', async () => {
    const { wrapper, ramo } = montar(semChave());
    const gaveta = await abrir(wrapper, 'perguntas');

    gaveta.querySelector('[data-item="p1"] [data-tirar-item]').click();
    await flushPromises();

    expect(ramo.mudar.mock.calls).toEqual([
      ['perguntas', [{ ...PERGUNTAS[0], tirada: true }]],
    ]);
  });

  it('shows only the tools the "Start" will really include', async () => {
    const prontas = { ...comChave(), visiveis: ref(['cep']) };
    const { wrapper } = montar(prontas);
    const gaveta = await abrir(wrapper, 'ferramentas');

    expect(
      [...gaveta.querySelectorAll('[data-ferramenta]')].map(item =>
        item.getAttribute('data-ferramenta')
      )
    ).toEqual(['cep']);
  });

  it('has no tools line when the account has no ready-made tools at all', () => {
    const prontas = {
      visiveis: ref([]),
      combinaTambem: ref([]),
      escolhidas: ref([]),
      semPermissao: ref(false),
      podeIncluir: ref(false),
    };
    const { wrapper } = montar(prontas);

    expect(wrapper.find('[data-linha="ferramentas"]').exists()).toBe(false);
    expect(wrapper.findAll('[data-linha]')).toHaveLength(2);
  });

  it('who cannot manage the agents only reads the questions', async () => {
    const { wrapper } = montar(comChave());
    await wrapper.setProps({ podeMudar: false });
    const gaveta = await abrir(wrapper, 'perguntas');

    expect(gaveta.querySelector('[data-tirar-item]')).toBeNull();
    expect(gaveta.querySelector('[data-incluir-item]')).toBeNull();
  });
});
