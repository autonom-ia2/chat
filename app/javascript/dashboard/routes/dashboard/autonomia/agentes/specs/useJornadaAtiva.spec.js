import { jornadaAtiva, useJornadaAtiva } from '../composables/useJornadaAtiva';

const store = vi.hoisted(() => ({ getters: {} }));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));

const conta = (extra = {}) => ({
  id: 3,
  autonomia_agents_enabled: true,
  features: { autonomia_agents_journey: true },
  ...extra,
});

describe('jornadaAtiva', () => {
  it('needs the Agents module and the journey flag on the account', () => {
    expect(jornadaAtiva(conta())).toBe(true);
    expect(jornadaAtiva(conta({ autonomia_agents_enabled: false }))).toBe(
      false
    );
    expect(
      jornadaAtiva(conta({ features: { autonomia_agents_journey: false } }))
    ).toBe(false);
    expect(jornadaAtiva(conta({ features: undefined }))).toBe(false);
    expect(jornadaAtiva(null)).toBe(false);
  });
});

describe('useJornadaAtiva', () => {
  it('reads the current account once, as a plain boolean', () => {
    const atual = conta();
    store.getters = {
      getCurrentAccountId: 3,
      'accounts/getAccount': id => (id === 3 ? atual : {}),
    };

    const ativa = useJornadaAtiva();
    atual.features = { autonomia_agents_journey: false };

    expect(ativa).toBe(true);
  });

  it('is off when the account is not in the store', () => {
    store.getters = {
      getCurrentAccountId: 3,
      'accounts/getAccount': () => ({}),
    };
    expect(useJornadaAtiva()).toBe(false);
  });
});
