import { ref } from 'vue';
import { usePodeVerAutomacoes } from '../useAutomacaoNoCrm';

// #2499 F6.3/F6.5 — a tela tem flag própria (automacao_no_crm): sem ela, as partes do card e da etapa somem, mesmo com
// o motor e os gatilhos de card ligados.
const conta = { flags: new Set() };
const chaves = { ver: true };

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: flag => conta.flags.has(flag) }),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: chave =>
    ref(chave === 'automation_view' ? chaves.ver : false),
}));

const MOTOR = ['automacao_fundacao', 'automacao_motor', 'automacao_gatilhos'];

describe('usePodeVerAutomacoes', () => {
  beforeEach(() => {
    chaves.ver = true;
  });

  it('com o motor, os gatilhos e a flag da tela, quem tem automation_view vê', () => {
    conta.flags = new Set([...MOTOR, 'automacao_no_crm']);

    expect(usePodeVerAutomacoes().value).toBe(true);
  });

  it('sem a flag da tela, ninguém vê', () => {
    conta.flags = new Set(MOTOR);

    expect(usePodeVerAutomacoes().value).toBe(false);
  });

  it('sem os gatilhos de card, a flag da tela sozinha não basta', () => {
    conta.flags = new Set([
      'automacao_fundacao',
      'automacao_motor',
      'automacao_no_crm',
    ]);

    expect(usePodeVerAutomacoes().value).toBe(false);
  });

  it('sem a chave de ver, não vê', () => {
    conta.flags = new Set([...MOTOR, 'automacao_no_crm']);
    chaves.ver = false;

    expect(usePodeVerAutomacoes().value).toBe(false);
  });
});
