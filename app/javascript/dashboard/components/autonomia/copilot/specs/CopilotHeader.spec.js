import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import CopilotHeader from '../CopilotHeader.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));

// #3191 — cabeçalho do Copiloto da equipe no desenho do Guia: foto e nome do
// agente, "Novo assunto" escrito e a troca de agente com itens de 44 px.
const CLARA = { id: 7, name: 'Clara', avatar_url: 'https://exemplo/clara.png' };
const BRUNO = { id: 8, name: 'Bruno', avatar_url: '' };

const montar = (props = {}) =>
  mount(CopilotHeader, {
    attachTo: document.body,
    props: { agente: CLARA, agentes: [CLARA], canReset: true, ...props },
    global: {
      mocks: { $t: key => key },
      directives: { onClickaway: {} },
    },
  });

const itens = wrapper => wrapper.findAll('[role="menuitemradio"]');

describe('CopilotHeader (#3191)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('mostra o nome e a foto do agente, e "Só você vê"', () => {
    const wrapper = montar();

    expect(wrapper.get('h2').text()).toBe('Clara');
    expect(wrapper.get('[data-foto]').attributes('src')).toBe(CLARA.avatar_url);
    expect(wrapper.text()).toContain('AUTONOMIA_COPILOT.SUBTITLE');
  });

  it('"Novo assunto" vem escrito, só depois de começar, e emite reset', async () => {
    expect(
      montar({ canReset: false }).find('[data-novo-assunto]').exists()
    ).toBe(false);

    const wrapper = montar();
    const botao = wrapper.get('[data-novo-assunto]');
    expect(botao.text()).toContain('AUTONOMIA_COPILOT.NEW_TOPIC');
    await botao.trigger('click');
    expect(wrapper.emitted('reset')).toHaveLength(1);
  });

  it('com um agente só não há o que trocar', () => {
    expect(montar().find('[data-trocar-agente]').exists()).toBe(false);
  });

  it('com dois agentes, o nome abre a lista no agente da vez', async () => {
    const wrapper = montar({ agentes: [CLARA, BRUNO] });
    const gatilho = wrapper.get('[data-trocar-agente]');

    await gatilho.trigger('click');
    await nextTick();

    expect(gatilho.attributes('aria-expanded')).toBe('true');
    expect(itens(wrapper)).toHaveLength(2);
    expect(itens(wrapper)[0].attributes('aria-checked')).toBe('true');
    expect(itens(wrapper)[1].attributes('aria-checked')).toBe('false');
    expect(document.activeElement).toBe(itens(wrapper)[0].element);
    itens(wrapper).forEach(item =>
      expect(item.classes()).toContain('min-h-11')
    );
  });

  it('escolher outro agente emite trocar e fecha a lista', async () => {
    const wrapper = montar({ agentes: [CLARA, BRUNO] });
    await wrapper.get('[data-trocar-agente]').trigger('click');
    await nextTick();

    await itens(wrapper)[1].trigger('click');
    await nextTick();

    expect(wrapper.emitted('trocar')).toEqual([[BRUNO]]);
    expect(itens(wrapper)).toHaveLength(0);
  });

  it('escolher o mesmo agente não troca nada', async () => {
    const wrapper = montar({ agentes: [CLARA, BRUNO] });
    await wrapper.get('[data-trocar-agente]').trigger('click');
    await nextTick();

    await itens(wrapper)[0].trigger('click');

    expect(wrapper.emitted('trocar')).toBeUndefined();
  });

  it('setas andam pela lista e Esc fecha devolvendo o foco', async () => {
    const wrapper = montar({ agentes: [CLARA, BRUNO] });
    const gatilho = wrapper.get('[data-trocar-agente]');
    await gatilho.trigger('click');
    await nextTick();

    await itens(wrapper)[0].trigger('keydown', { key: 'ArrowDown' });
    expect(document.activeElement).toBe(itens(wrapper)[1].element);

    await itens(wrapper)[1].trigger('keydown', { key: 'Escape' });
    await nextTick();
    await nextTick();
    expect(itens(wrapper)).toHaveLength(0);
    expect(document.activeElement).toBe(gatilho.element);
  });

  it('fechar e voltar (celular) emitem close', async () => {
    const wrapper = montar();

    await wrapper
      .get('button[aria-label="AUTONOMIA_COPILOT.CLOSE"]')
      .trigger('click');
    await wrapper
      .get('button[aria-label="AUTONOMIA_COPILOT.BACK"]')
      .trigger('click');

    expect(wrapper.emitted('close')).toHaveLength(2);
  });
});
