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
