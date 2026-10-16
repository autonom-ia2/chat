import {
  FUNNEL_ALL,
  FUNNEL_NONE,
  funnelChoiceKey,
  readFunnelChoice,
  visibleFunnelChoice,
  writeFunnelChoice,
} from '../useFunnelFilterChoice';

describe('useFunnelFilterChoice (#1150)', () => {
  afterEach(() => {
    window.localStorage.clear();
    vi.restoreAllMocks();
  });

  it('guarda a escolha por conta e por pessoa', () => {
    writeFunnelChoice(1, 7, '12');
    writeFunnelChoice(2, 7, FUNNEL_NONE);

    expect(funnelChoiceKey(1, 7)).toBe('crm_filtro_funil:1:7');
    expect(readFunnelChoice(1, 7)).toBe('12');
    expect(readFunnelChoice(2, 7)).toBe(FUNNEL_NONE);
    expect(readFunnelChoice(1, 8)).toBe(FUNNEL_ALL);
  });

  it('"Sem filtro de funil" apaga a chave', () => {
    writeFunnelChoice(1, 7, '12');
    writeFunnelChoice(1, 7, FUNNEL_ALL);

    expect(window.localStorage.getItem('crm_filtro_funil:1:7')).toBeNull();
    expect(readFunnelChoice(1, 7)).toBe(FUNNEL_ALL);
  });

  it('sem armazenamento (janela privada, cota cheia) não quebra e volta para todos', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('SecurityError');
    });
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('QuotaExceededError');
    });

    expect(() => writeFunnelChoice(1, 7, '12')).not.toThrow();
    expect(readFunnelChoice(1, 7)).toBe(FUNNEL_ALL);
  });

  it('funil guardado que deixou de ser visível volta para "Sem filtro de funil"', () => {
    expect(visibleFunnelChoice('12', [12, 13])).toBe('12');
    expect(visibleFunnelChoice('99', [12, 13])).toBe(FUNNEL_ALL);
    expect(visibleFunnelChoice(FUNNEL_NONE, [])).toBe(FUNNEL_NONE);
    expect(visibleFunnelChoice(FUNNEL_ALL, [12])).toBe(FUNNEL_ALL);
  });
});
