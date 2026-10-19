// #1872 — o ✨ do e-mail novo abre o menu da IA do cliente (slot copilot-menu) e ele fica aberto.
// No navegador, o ✨ abre no mousedown e o clique termina no mouseup, às vezes já em cima do menu;
// o evento `click` então nasce no ancestral comum (fora do menu) e fechava o que acabou de abrir.
import { flushPromises, mount } from '@vue/test-utils';
import { h } from 'vue';
import { createStore } from 'vuex';
import Editor from '../Editor.vue';

const espiaoDoCaptain = vi.hoisted(() => vi.fn());
// O Editor guarda a EditorView numa variável do módulo: a subclasse a entrega ao teste.
let view = null;
vi.mock('@chatwoot/prosemirror-schema', async importOriginal => {
  const actual = await importOriginal();
  class EditorViewDoTeste extends actual.EditorView {
    constructor(...args) {
      super(...args);
      view = this;
    }
  }
  return { ...actual, EditorView: EditorViewDoTeste };
});

vi.mock('dashboard/composables/useCaptain', () => ({
  useCaptain: () => ({ captainTasksEnabled: { value: false } }),
}));
vi.mock('dashboard/composables', async importOriginal => ({
  ...(await importOriginal()),
  useTrack: espiaoDoCaptain,
  useAlert: vi.fn(),
}));

// jsdom não tem layout; o ProseMirror mede o cursor pelos retângulos do Range.
const zero = { top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0 };
Range.prototype.getClientRects = () => [zero];
Range.prototype.getBoundingClientRect = () => zero;

const store = createStore({
  getters: { getUISettings: () => ({}), 'globalConfig/get': () => ({}) },
  actions: { updateUISettings: () => {} },
});

let wrapper;
const montar = (copilotAvailable = true) => {
  wrapper = mount(Editor, {
    props: {
      modelValue: 'Oi Marina',
      channelType: 'Channel::Email',
      copilotAvailable,
      focusOnMount: false,
    },
    slots: {
      'copilot-menu': () =>
        h('div', { 'data-menu-da-ia': '' }, [
          h('button', { 'data-acao': 'improve' }, 'Melhorar'),
        ]),
    },
    global: { plugins: [store], mocks: { $t: chave => chave } },
    attachTo: document.body,
  });
  return wrapper;
};

const clicar = alvo =>
  alvo.dispatchEvent(
    new MouseEvent('click', { bubbles: true, cancelable: true, detail: 1 })
  );
const pressionar = alvo =>
  alvo.dispatchEvent(
    new MouseEvent('mousedown', { bubbles: true, cancelable: true })
  );
// O clique-fora do vueuse junta cliques da mesma volta do relógio; cada clique, numa volta.
const proximaVolta = () =>
  new Promise(resolve => {
    setTimeout(resolve, 0);
  });
const menuAberto = () => wrapper.find('[data-menu-da-ia]').exists();

afterEach(() => {
  wrapper?.unmount();
  document.body.innerHTML = '';
});

describe('Editor: menu do ✨ pelo slot (IA do e-mail)', () => {
  it('mousedown no ✨ e mouseup em cima do menu: o menu continua aberto', async () => {
    montar();
    await flushPromises();
    const brilho = wrapper.element.querySelector('.ProseMirror-copilot');
    expect(brilho).not.toBeNull();

    pressionar(brilho);
    await flushPromises();
    expect(menuAberto()).toBe(true);

    // O mouseup caiu num botão do menu: o `click` nasce no ancestral comum, fora do menu.
    clicar(wrapper.element);
    await proximaVolta();
    expect(menuAberto()).toBe(true);

    // Clicar dentro do menu também não fecha.
    clicar(wrapper.find('[data-acao="improve"]').element);
    await proximaVolta();
    expect(menuAberto()).toBe(true);

    // Um clique de verdade fora fecha.
    clicar(document.body);
    await proximaVolta();
    expect(menuAberto()).toBe(false);
  });

  it('o menu do slot não dispara o evento do Captain', async () => {
    montar();
    await flushPromises();
    pressionar(wrapper.element.querySelector('.ProseMirror-copilot'));
    await flushPromises();
    expect(menuAberto()).toBe(true);
    expect(espiaoDoCaptain).not.toHaveBeenCalled();
  });
});

describe('Editor: a disponibilidade da IA chega depois de a pessoa digitar', () => {
  it('o ✨ aparece, o foco continua no texto e a próxima tecla entra nele', async () => {
    montar(false);
    await flushPromises();
    expect(wrapper.element.querySelector('.ProseMirror-copilot')).toBeNull();

    view.focus();
    const fim = view.state.doc.content.size - 1;
    view.dispatch(
      view.state.tr.setSelection(
        view.state.selection.constructor.near(view.state.doc.resolve(fim))
      )
    );
    expect(document.activeElement).toBe(view.dom);

    await wrapper.setProps({ copilotAvailable: true });
    await flushPromises();

    expect(
      wrapper.element.querySelector('.ProseMirror-copilot')
    ).not.toBeNull();
    expect(document.activeElement).toBe(view.dom);
    expect(view.hasFocus()).toBe(true);
    expect(view.state.selection.from).toBe(fim);

    // A tecla seguinte cai onde o cursor estava.
    view.dispatch(view.state.tr.insertText('!'));
    expect(view.state.doc.textContent).toBe('Oi Marina!');
  });

  it('sem o foco no texto, a troca da régua não puxa o foco para ele', async () => {
    montar(false);
    await flushPromises();
    const outro = document.createElement('input');
    document.body.appendChild(outro);
    outro.focus();

    await wrapper.setProps({ copilotAvailable: true });
    await flushPromises();

    expect(document.activeElement).toBe(outro);
  });
});
