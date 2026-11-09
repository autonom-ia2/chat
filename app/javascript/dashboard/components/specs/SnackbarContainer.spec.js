import { mount } from '@vue/test-utils';
import SnackbarContainer from '../SnackbarContainer.vue';

const rota = { name: 'contacts_dashboard_index', query: {} };
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({ useRoute: () => rota }));
vi.mock(
  'dashboard/components-next/Conversation/ListaDeConversas/useListaNova',
  () => ({ useListaNova: () => ({ value: false }) })
);

// #2206 — abaixo de 640 px o aviso fica embaixo, acima do botão flutuante do menu (bottom-4, ~48 px de altura);
// do sm (640 px) para cima, continua no topo, como sempre.
// Guarda de classe: o jsdom não aplica CSS; a posição real está nos prints de 390 e 1440 do PR.
describe('SnackbarContainer (#2206)', () => {
  let wrapper;
  afterEach(() => wrapper?.unmount());
  const classes = () => {
    wrapper = mount(SnackbarContainer, {
      global: { stubs: { WootSnackbar: true } },
    });
    return wrapper.find('[popover]').classes();
  };

  it('no celular, ancora embaixo, acima do lugar do botão do menu', () => {
    expect(classes()).toEqual(
      expect.arrayContaining(['bottom-20', 'top-auto'])
    );
    expect(classes()).not.toContain('top-4');
  });

  it('na conversa aberta (sem botão do menu, caixa de resposta embaixo), fica no topo', () => {
    rota.name = 'inbox_conversation';
    expect(classes()).toContain('top-4');
    expect(classes()).not.toContain('bottom-20');
    rota.name = 'contacts_dashboard_index';
  });

  it('do sm para cima, volta ao topo como antes', () => {
    expect(classes()).toEqual(
      expect.arrayContaining(['sm:top-4', 'sm:bottom-auto'])
    );
  });
});
