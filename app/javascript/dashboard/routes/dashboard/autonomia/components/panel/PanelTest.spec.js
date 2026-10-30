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

  // Teste do PR #2386 (C26): sem texto e com passagem, fica só a marca da passagem, sem balão vazio e sem erro.
  it('shows only the handoff note, without an empty bubble, when the answer is a handoff with no text', async () => {
    store.dispatch.mockResolvedValueOnce({
      reply: '',
      confidence: 0.3,
      handoff: { should: true, reason: 'human_requested' },
    });
    const wrapper = montar();

    await enviar(wrapper);

    expect(alerta).not.toHaveBeenCalled();
    expect(wrapper.findAllComponents(ChatBubble)).toHaveLength(1);
    expect(wrapper.text()).toContain('AGENTS.TEST.HANDOFF_NOTICE');
    wrapper.unmount();
  });

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
