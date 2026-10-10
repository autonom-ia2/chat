import { defineComponent, h, ref, nextTick } from 'vue';
import { mount } from '@vue/test-utils';
import AgenteGaveta from '../components/AgenteGaveta.vue';
import AgenteConfirmacao from '../components/AgenteConfirmacao.vue';
import AgenteMenuMais from '../components/AgenteMenuMais.vue';

// O Dialog do produto leva o TeleportWithDirection, que lê a direção do texto na store.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});

const tecla = (key, extra = {}) =>
  document.dispatchEvent(
    new KeyboardEvent('keydown', { key, bubbles: true, ...extra })
  );

// Casca com o botão que abre a gaveta, para conferir a volta do foco.
const Casca = defineComponent({
  setup() {
    const aberta = ref(false);
    return () =>
      h('div', [
        h(
          'button',
          {
            id: 'gatilho',
            onClick: () => {
              aberta.value = true;
            },
          },
          'Abrir'
        ),
        aberta.value
          ? h(
              AgenteGaveta,
              {
                titulo: 'Criar agente',
                onFechar: () => {
                  aberta.value = false;
                },
              },
              {
                default: () => [
                  h('button', { id: 'primeiro' }, 'Um'),
                  h('button', { id: 'ultimo' }, 'Dois'),
                ],
              }
            )
          : null,
      ]);
  },
});

describe('AgenteGaveta', () => {
  let wrapper;

  // A gaveta vai para o body (TeleportWithDirection): procurar no documento, não no wrapper.
  const no = seletor => document.querySelector(seletor);

  const abrir = async () => {
    wrapper = mount(Casca, { attachTo: document.body });
    const gatilho = wrapper.get('#gatilho');
    gatilho.element.focus();
    await gatilho.trigger('click');
    await nextTick();
  };

  const clicar = async seletor => {
    no(seletor).click();
    await nextTick();
  };

  afterEach(() => wrapper?.unmount());

  it('is a labelled modal dialog that takes the focus to the close button', async () => {
    await abrir();
    const dialogo = no('[role="dialog"]');

    expect(dialogo.getAttribute('aria-modal')).toBe('true');
    const titulo = document.getElementById(
      dialogo.getAttribute('aria-labelledby')
    );
    expect(titulo.textContent.trim()).toBe('Criar agente');
    expect(document.activeElement).toBe(no('[data-fechar]'));
    expect(no('[data-fechar]').classList).toContain('size-11');
  });

  it('lives on the body, out of the page that scrolls', async () => {
    await abrir();
    const dialogo = no('[role="dialog"]');

    expect(wrapper.element.contains(dialogo)).toBe(false);
    expect(document.body.contains(dialogo)).toBe(true);
  });

  it('keeps Tab and Shift+Tab inside', async () => {
    await abrir();
    const fechar = no('[data-fechar]');
    const ultimo = no('#ultimo');

    ultimo.focus();
    tecla('Tab');
    expect(document.activeElement).toBe(fechar);

    tecla('Tab', { shiftKey: true });
    expect(document.activeElement).toBe(ultimo);
  });

  it('closes on Escape and gives the focus back to the trigger', async () => {
    await abrir();
    tecla('Escape');
    await nextTick();

    expect(no('[role="dialog"]')).toBeNull();
    expect(document.activeElement).toBe(wrapper.get('#gatilho').element);
  });

  it('closes on the backdrop and on the close button', async () => {
    await abrir();
    await clicar('[data-fundo]');
    expect(no('[role="dialog"]')).toBeNull();

    await wrapper.get('#gatilho').trigger('click');
    await nextTick();
    await clicar('[data-fechar]');
    expect(no('[role="dialog"]')).toBeNull();
  });
});

describe('AgenteConfirmacao', () => {
  beforeAll(() => {
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  const montar = props =>
    mount(AgenteConfirmacao, {
      props: {
        titulo: 'Excluir este rascunho?',
        texto: 'O que você contou até aqui se perde.',
        confirmar: 'Excluir',
        ...props,
      },
      attachTo: document.body,
    });

  it('asks with a title, a text and two AA buttons, cancel first', async () => {
    const wrapper = montar();
    wrapper.vm.abrir();
    await nextTick();

    const caixa = document.body.querySelector('dialog');
    expect(caixa.textContent).toContain('Excluir este rascunho?');
    expect(caixa.textContent).toContain('O que você contou até aqui se perde.');
    const botoes = [...caixa.querySelectorAll('[data-botoes] button')];
    expect(botoes.map(b => b.textContent.trim())).toEqual([
      'AGENTS.JORNADA.COMUM.CANCELAR',
      'Excluir',
    ]);
    expect(botoes[1].className).toContain('bg-n-ruby-11');
    wrapper.unmount();
  });

  it('emits confirmar on the main button and closes on the other', async () => {
    const wrapper = montar();
    wrapper.vm.abrir();
    await nextTick();
    const [cancelar, confirmar] = document.body.querySelectorAll(
      '[data-botoes] button'
    );

    confirmar.click();
    cancelar.click();
    expect(wrapper.emitted('confirmar')).toHaveLength(1);
    expect(wrapper.emitted('fechada')).toHaveLength(1);
    expect(HTMLDialogElement.prototype.close).toHaveBeenCalled();
    wrapper.unmount();
  });
});

describe('AgenteMenuMais', () => {
  let wrapper;
  const montar = () => {
    wrapper = mount(AgenteMenuMais, {
      props: {
        rotulo: 'Mais opções de Bia',
        itens: [{ chave: 'excluir', texto: 'Excluir rascunho', perigo: true }],
      },
      attachTo: document.body,
    });
    return wrapper;
  };

  afterEach(() => wrapper?.unmount());

  it('opens a menu and moves the focus to the first item', async () => {
    montar();
    const botao = wrapper.get('[aria-haspopup="menu"]');
    expect(botao.attributes('aria-label')).toBe('Mais opções de Bia');
    expect(botao.attributes('aria-expanded')).toBe('false');
    expect(botao.classes()).toContain('size-11');

    await botao.trigger('click');
    await nextTick();

    expect(botao.attributes('aria-expanded')).toBe('true');
    const item = wrapper.get('[role="menuitem"]');
    expect(document.activeElement).toBe(item.element);
  });

  it('emits the chosen item and closes', async () => {
    montar();
    await wrapper.get('[aria-haspopup="menu"]').trigger('click');
    await nextTick();
    await wrapper.get('[role="menuitem"]').trigger('click');

    expect(wrapper.emitted('escolher')).toEqual([['excluir']]);
    expect(wrapper.find('[role="menu"]').exists()).toBe(false);
  });

  it('closes on Escape and gives the focus back to the button', async () => {
    montar();
    const botao = wrapper.get('[aria-haspopup="menu"]');
    await botao.trigger('click');
    await nextTick();
    await wrapper.get('[role="menu"]').trigger('keydown', { key: 'Escape' });
    await nextTick();

    expect(wrapper.find('[role="menu"]').exists()).toBe(false);
    expect(document.activeElement).toBe(botao.element);
  });
});
