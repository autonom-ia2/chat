// Atalhos do menu (#1618): Alt+V mandava para 'contacts_dashboard', rota que não
// existe; a lista de contatos se chama 'contacts_dashboard_index'.
import { useSidebarKeyboardShortcuts } from '../useSidebarKeyboardShortcuts';

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

describe('useSidebarKeyboardShortcuts', () => {
  beforeEach(() => {
    push.mockReset();
    useSidebarKeyboardShortcuts(vi.fn());
  });

  it('Alt+V abre a lista de contatos pela rota que existe', () => {
    eventos['Alt+KeyV'].action();
    expect(push).toHaveBeenCalledWith({ name: 'contacts_dashboard_index' });
  });
});
