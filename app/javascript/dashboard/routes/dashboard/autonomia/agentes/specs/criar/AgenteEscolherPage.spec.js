import { mount, flushPromises } from '@vue/test-utils';
import AgenteEscolherPage from '../../pages/AgenteEscolherPage.vue';

// #1543 — página inteira "Criar agente": agente normal em destaque (modelos e "Do meu jeito", com
// ?modelo=) e, em "Precisa de outro tipo?", só o Copiloto da equipe (?atuacao=interno). "Agente da
// equipe" e "Ajuda outros agentes" ainda não existem: não aparecem, nem escondidos nem desabilitados.
// #1433 (tema 13): "Agente da equipe" (?papel=area) aparece só com a Fase 2 ligada na conta.
// Tema 14 (#1434): "Ajuda outros agentes" (?papel=ajudante) também, depois do agente da equipe.
const estado = vi.hoisted(() => ({ podeGerenciar: true }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { useCanManage: () => computed(() => estado.podeGerenciar) };
});

const router = vi.hoisted(() => ({ push: vi.fn() }));
const conta = vi.hoisted(() => ({ fase2: false }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  const getters = {
    'accounts/getAccount': () => () => ({
      autonomia_agents_fase2: conta.fase2,
    }),
    getCurrentAccountId: () => 1,
  };
  return { useMapGetter: nome => computed(() => getters[nome]()) };
});
vi.mock('vue-router', () => ({ useRouter: () => router }));
// #2881: quais agentes prontos por ramo a conta pode usar vem do servidor. Sem resposta combinada, nenhum.
const jornada = vi.hoisted(() => ({
  modelosDeRamo: vi.fn(() => Promise.resolve({ data: { modelos: [] } })),
}));
vi.mock('dashboard/api/autonomia/jornada', () => ({ default: jornada }));

const montar = () => mount(AgenteEscolherPage);

describe('AgenteEscolherPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    estado.podeGerenciar = true;
    conta.fase2 = false;
  });

  it('opens with the title, the three templates and "Do meu jeito" in the navy block', () => {
    const wrapper = montar();
    const heroi = wrapper.get('[data-heroi]');
    expect(heroi.find('h1').text()).toBe('AGENTS.JORNADA.ESCOLHER.TITULO');
    expect(heroi.text()).toContain('AGENTS.JORNADA.ESCOLHER.TEXTO');
    expect(heroi.findAll('[data-usar]')).toHaveLength(3);
    expect(heroi.get('[data-do-meu-jeito]').text()).toBe(
      'AGENTS.JORNADA.MODELOS.DO_MEU_JEITO'
    );
    // Um bloco navy só, e o outro tipo fica fora dele, embaixo.
    expect(wrapper.findAll('[data-heroi]')).toHaveLength(1);
    expect(heroi.find('[data-outro-tipo]').exists()).toBe(false);
  });

  it('uses a template with ?modelo= and ignores a second click while it starts', async () => {
    const wrapper = montar();
    const usar = wrapper.findAll('[data-usar]');
    await usar[1].trigger('click');
    await usar[0].trigger('click');
    await wrapper.get('[data-do-meu-jeito]').trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([[{ modelo: 'sdr' }]]);
  });

  it('starts "Do meu jeito" as the custom template', async () => {
    const wrapper = montar();
    await wrapper.get('[data-do-meu-jeito]').trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([[{ modelo: 'custom' }]]);
  });

  it('offers only the team copilot under "Precisa de outro tipo?", with its explanation, as internal', async () => {
    const wrapper = montar();
    const secao = wrapper.get('[data-outro-tipo]');
    expect(secao.get('h2').text()).toBe('AGENTS.JORNADA.ESCOLHER.OUTRO_TIPO');
    expect(secao.text()).toContain('AGENTS.JORNADA.ESCOLHER.OUTRO_TEXTO');
    const opcoes = secao.findAll('[data-outro]');
    expect(opcoes).toHaveLength(1);
    const copiloto = opcoes[0];
    expect(copiloto.element.tagName).toBe('BUTTON');
    expect(copiloto.attributes('data-outro')).toBe('copiloto');
    expect(copiloto.text()).toContain('AGENTS.JORNADA.MODELOS.COPILOTO');
    expect(copiloto.text()).toContain('AGENTS.JORNADA.MODELOS.COPILOTO_TEXTO');

    await copiloto.trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([[{ atuacao: 'interno' }]]);
  });

  it('without the Fase 2, has no "Agente da equipe" nor "Ajuda outros agentes", not even hidden or disabled', () => {
    const html = montar().html();
    expect(html).not.toContain('ESCOLHER.EQUIPE');
    expect(html).not.toContain('ESCOLHER.AJUDA');
    expect(html).not.toContain('data-outro="equipe"');
    expect(html).not.toContain('data-outro="ajuda"');
    expect(html).not.toContain('data-outro="ajudante"');
  });

  it('goes back to the list', async () => {
    const wrapper = montar();
    await wrapper.get('[data-voltar-lista]').trigger('click');
    expect(router.push).toHaveBeenCalledWith({
      name: 'autonomia_agents_index',
    });
    expect(wrapper.emitted('escolher')).toBeUndefined();
  });

  it('offers no creating action to a view only seat', async () => {
    estado.podeGerenciar = false;
    const wrapper = montar();
    expect(wrapper.text()).toContain('AGENTS.JORNADA.HEROI.SO_VER');
    expect(wrapper.find('[data-usar]').exists()).toBe(false);
    expect(wrapper.find('[data-do-meu-jeito]').exists()).toBe(false);
    expect(wrapper.find('[data-outro-tipo]').exists()).toBe(false);
    await flushPromises();
    expect(wrapper.emitted('escolher')).toBeUndefined();
  });

  it('keeps every action at least 44 px tall and never renders a native select', () => {
    const wrapper = montar();
    expect(wrapper.find('select').exists()).toBe(false);
    ['[data-voltar-lista]', '[data-do-meu-jeito]', '[data-copiloto]'].forEach(
      seletor => {
        expect(wrapper.get(seletor).classes()).toContain('min-h-11');
      }
    );
  });
});

// #2881 — "Prontos para o seu ramo": quem decide quais cartões aparecem é o servidor. Lista vazia ou leitura que
// falhou: a página fica exatamente como sempre foi.
describe('AgenteEscolherPage com agentes prontos por ramo (#2881)', () => {
  const comRamos = async modelos => {
    jornada.modelosDeRamo.mockResolvedValueOnce({ data: { modelos } });
    const wrapper = montar();
    await flushPromises();
    return wrapper;
  };

  beforeEach(() => {
    vi.clearAllMocks();
    estado.podeGerenciar = true;
    conta.fase2 = false;
  });

  it('shows the row first, only with the keys the server sent, and keeps the three general templates below', async () => {
    const wrapper = await comRamos(['transporte_carga', 'seguro_de_vida']);
    const fileira = wrapper.get('[data-heroi] [data-ramos]');

    expect(jornada.modelosDeRamo).toHaveBeenCalledTimes(1);
    expect(fileira.get('h2').text()).toBe('AGENTS.JORNADA.RAMOS.TITULO');
    const cartoes = fileira.findAll('[data-ramo]');
    expect(cartoes).toHaveLength(1);
    expect(cartoes[0].get('h3').text()).toBe(
      'AGENTS.JORNADA.RAMOS.ITENS.CARGA.TITULO'
    );
    expect(wrapper.get('[data-heroi]').text()).toContain(
      'AGENTS.JORNADA.RAMOS.TEXTO_DA_PAGINA'
    );
    expect(wrapper.findAll('[data-usar]')).toHaveLength(3);
    expect(wrapper.find('[data-do-meu-jeito]').exists()).toBe(true);
  });

  it('shows the three cards, in the order of the screen, when the server sends the three keys', async () => {
    const wrapper = await comRamos([
      'transporte_carga',
      'seguro_garantia',
      'seguro_auto',
    ]);

    expect(
      wrapper.findAll('[data-ramo] h3').map(titulo => titulo.text())
    ).toEqual([
      'AGENTS.JORNADA.RAMOS.ITENS.AUTO.TITULO',
      'AGENTS.JORNADA.RAMOS.ITENS.GARANTIA.TITULO',
      'AGENTS.JORNADA.RAMOS.ITENS.CARGA.TITULO',
    ]);
  });

  it('with an empty list, the page is the one of today', async () => {
    const wrapper = await comRamos([]);

    expect(wrapper.find('[data-ramos]').exists()).toBe(false);
    expect(wrapper.find('[data-ramo]').exists()).toBe(false);
    expect(wrapper.get('[data-heroi]').text()).toContain(
      'AGENTS.JORNADA.ESCOLHER.TEXTO'
    );
    expect(wrapper.html()).not.toContain('AGENTS.JORNADA.RAMOS');
    expect(wrapper.findAll('[data-usar]')).toHaveLength(3);
  });

  it('when the read fails, the page is the one of today and the failure is logged, not swallowed', async () => {
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    jornada.modelosDeRamo.mockRejectedValueOnce(
      Object.assign(new Error('500'), { response: { status: 500 } })
    );
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-ramos]').exists()).toBe(false);
    expect(wrapper.findAll('[data-usar]')).toHaveLength(3);
    expect(wrapper.get('[data-heroi]').text()).toContain(
      'AGENTS.JORNADA.ESCOLHER.TEXTO'
    );
    expect(aviso).toHaveBeenCalledWith('[agentes] ramos: leitura falhou', 500);
    aviso.mockRestore();
  });

  it('an answer that is not a list shows no card', async () => {
    jornada.modelosDeRamo.mockResolvedValueOnce({ data: { modelos: 'tudo' } });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-ramos]').exists()).toBe(false);
  });

  it('a card goes to the creation with ?ramo=, and a second click while it starts is ignored', async () => {
    const wrapper = await comRamos(['seguro_auto', 'seguro_garantia']);
    const usar = wrapper.findAll('[data-usar-ramo]');

    await usar[1].trigger('click');
    await usar[0].trigger('click');
    await wrapper.findAll('[data-usar]')[0].trigger('click');

    expect(wrapper.emitted('escolher')).toEqual([
      [{ ramo: 'seguro_garantia' }],
    ]);
    expect(usar[0].attributes('disabled')).toBeDefined();
    expect(usar[1].attributes('aria-busy')).toBe('true');
  });

  it('offers no "use this one" on the cards to a view only seat', async () => {
    estado.podeGerenciar = false;
    const wrapper = await comRamos(['seguro_auto']);

    expect(wrapper.findAll('[data-ramo]')).toHaveLength(1);
    expect(wrapper.find('[data-usar-ramo]').exists()).toBe(false);
  });

  it('keeps the card button at least 44 px tall and never renders a native select', async () => {
    const wrapper = await comRamos(['seguro_auto']);

    expect(wrapper.find('select').exists()).toBe(false);
    expect(wrapper.get('[data-usar-ramo]').classes()).toContain('min-h-12');
  });
});

describe('AgenteEscolherPage com a Fase 2 (#1433, tema 13)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    estado.podeGerenciar = true;
    conta.fase2 = true;
  });

  it('offers "Agente da equipe" first, then "Ajuda outros agentes" (tema 14), and still the copilot', () => {
    const wrapper = montar();
    const opcoes = wrapper.get('[data-outro-tipo]').findAll('[data-outro]');
    expect(opcoes.map(opcao => opcao.attributes('data-outro'))).toEqual([
      'equipe',
      'ajudante',
      'copiloto',
    ]);
    expect(opcoes[0].element.tagName).toBe('BUTTON');
    expect(opcoes[0].text()).toContain('AGENTS.JORNADA.ESCOLHER.EQUIPE.TITULO');
    expect(opcoes[0].text()).toContain('AGENTS.JORNADA.ESCOLHER.EQUIPE.TEXTO');
    expect(opcoes[0].classes()).toContain('min-h-11');
  });

  it('starts the team agent with ?papel=area and ignores other clicks while it starts', async () => {
    const wrapper = montar();
    await wrapper.get('[data-agente-da-equipe]').trigger('click');
    await wrapper.get('[data-copiloto]').trigger('click');
    await wrapper.findAll('[data-usar]')[0].trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([[{ papel: 'area' }]]);
    expect(wrapper.get('[data-copiloto]').attributes('disabled')).toBeDefined();
  });

  it('keeps it away from a view only seat', () => {
    estado.podeGerenciar = false;
    expect(montar().find('[data-agente-da-equipe]').exists()).toBe(false);
    expect(montar().find('[data-ajudante]').exists()).toBe(false);
  });

  it('explains "Ajuda outros agentes" with the prototype text and starts it with ?papel=ajudante', async () => {
    const wrapper = montar();
    const cartao = wrapper.get('[data-ajudante]');
    expect(cartao.element.tagName).toBe('BUTTON');
    expect(cartao.text()).toContain('AGENTS.JORNADA.ESCOLHER.AJUDA.TITULO');
    expect(cartao.text()).toContain('AGENTS.JORNADA.ESCOLHER.AJUDA.TEXTO');
    expect(cartao.classes()).toContain('min-h-11');

    await cartao.trigger('click');
    await wrapper.get('[data-agente-da-equipe]').trigger('click');
    await wrapper.get('[data-copiloto]').trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([[{ papel: 'ajudante' }]]);
    expect(
      wrapper.get('[data-agente-da-equipe]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('select').exists()).toBe(false);
  });
});
