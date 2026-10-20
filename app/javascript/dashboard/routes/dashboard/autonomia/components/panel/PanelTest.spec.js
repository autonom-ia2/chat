import { mount, flushPromises } from '@vue/test-utils';
import PanelTest from './PanelTest.vue';
import ChatComposer from '../builder/ChatComposer.vue';

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
  wrapper
    .findComponent(ChatComposer)
    .vm.$emit('send', { content: 'Oi', images: [] });
  await flushPromises();
};

beforeEach(() => {
  store.dispatch.mockReset();
  alerta.mockReset();
  sessionStorage.clear();
});

describe('PanelTest', () => {
  it('shows the reason the server refused the photo', async () => {
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
    wrapper.unmount();
  });

  it('keeps the generic error for any other failure', async () => {
    store.dispatch.mockRejectedValueOnce(
      Object.assign(new Error('500'), { response: { status: 500 } })
    );
    const wrapper = montar();

    await enviar(wrapper);

    expect(alerta).toHaveBeenCalledWith('AGENTS.TEST.ERROR');
    wrapper.unmount();
  });
});
