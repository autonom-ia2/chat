// Atalhos do menu (#1618): Alt+V mandava para 'contacts_dashboard', rota que não
// existe; a lista de contatos se chama 'contacts_dashboard_index'. O nome usado
// é conferido nas rotas reais de contatos, não só no mock do roteador.
import { useSidebarKeyboardShortcuts } from '../useSidebarKeyboardShortcuts';
import { routes as contactRoutes } from 'dashboard/routes/dashboard/contacts/routes';

const push = vi.fn();
let eventos = {};

vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'home' }),
  useRouter: () => ({ push }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: keyboardEvents => {
    eventos = keyboardEvents;
  },
}));

const nomesDasRotas = rotas =>
  rotas.flatMap(rota => [
    ...(rota.name ? [rota.name] : []),
    ...nomesDasRotas(rota.children || []),
  ]);

describe('useSidebarKeyboardShortcuts', () => {
  beforeEach(() => {
    push.mockReset();
    useSidebarKeyboardShortcuts(vi.fn());
  });

  it('Alt+V abre a lista de contatos por uma rota registrada', () => {
    eventos['Alt+KeyV'].action();

    const [[destino]] = push.mock.calls;
    expect(destino).toEqual({ name: 'contacts_dashboard_index' });
    expect(nomesDasRotas(contactRoutes)).toContain(destino.name);
  });
});
