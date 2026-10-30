import { mount, flushPromises } from '@vue/test-utils';
import PanelTest from './PanelTest.vue';
import ChatBubble from '../builder/ChatBubble.vue';

// #1427 — o Testar do painel antigo também manda foto pelo POST /test. Na Fase 2 o servidor confere a foto e responde 422
// `foto_recusada` com o motivo: o aviso mostra esse motivo, não a falha genérica.
const store = vi.hoisted(() => ({
  dispatch: vi.fn(),
  getters: { 'autonomiaAgents/getRecord': () => ({ id: 7 }) },
}));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const montar = () =>
  mount(PanelTest, {
    props: { agentId: 7 },
    global: { stubs: { Accordion: true } },
  });

const enviar = async wrapper => {
  await wrapper.get('textarea').setValue('Quanto custa este?');
  await wrapper.get('textarea').trigger('keydown.enter');
  await flushPromises();
};

beforeEach(() => {
  store.dispatch.mockReset();
  alerta.mockReset();
  sessionStorage.clear();
});

describe('PanelTest', () => {
  it('shows the reason the server refused the photo, drops the question and gives the text back', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('422'), {
        response: {
          status: 422,
          data: {
            code: 'foto_recusada',
            error: 'A foto é grande demais. O tamanho máximo é 5 MB.',
          },
        },
      })
    );
    const wrapper = montar();

    await enviar(wrapper);

    expect(alerta).toHaveBeenCalledWith(
      'A foto é grande demais. O tamanho máximo é 5 MB.'
    );
    expect(wrapper.findAllComponents(ChatBubble)).toHaveLength(0);
    expect(wrapper.get('textarea').element.value).toBe('Quanto custa este?');
    wrapper.unmount();
  });

  // Tema 6 (#1428): sem o portão, a IA que falhou volta 200 com `error` e sem texto.
  it.each([
    [{ reply: null, error: 'ai_unavailable', handoff: { should: false } }],
    [{ reply: '', handoff: { should: false } }],
  ])(
    'shows the error, not an empty bubble, when the answer has no text (%o)',
    async dados => {
      store.dispatch.mockResolvedValueOnce(dados);
      const wrapper = montar();

      await enviar(wrapper);

      expect(alerta).toHaveBeenCalledWith('AGENTS.TEST.ERROR');
      expect(wrapper.findAllComponents(ChatBubble)).toHaveLength(1);
      wrapper.unmount();
    }
  );

  it('keeps the generic error for any other failure', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('500'), { response: { status: 500 } })
    );
    const wrapper = montar();

    await enviar(wrapper);

    expect(alerta).toHaveBeenCalledWith('AGENTS.TEST.ERROR');
    expect(wrapper.findAllComponents(ChatBubble)).toHaveLength(1);
    expect(wrapper.get('textarea').element.value).toBe('');
    wrapper.unmount();
  });
});
