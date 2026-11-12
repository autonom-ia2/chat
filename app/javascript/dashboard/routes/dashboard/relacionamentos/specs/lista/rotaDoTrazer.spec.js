import {
  desvioDoTrazer,
  rotaDoTrazer,
  temOndeTrazer,
} from '../../lista/rotaDoTrazer';
import { usarDemo } from '../../fonte/modoDemo';

vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: vi.fn(),
}));

const jornada = (ligada, importacao = ligada) => {
  window.globalConfig = {
    CAMPAIGN_JOURNEY_ENABLED: String(ligada),
    CAMPAIGN_IMPORT_ENABLED: String(importacao),
  };
};

afterEach(() => {
  delete window.globalConfig;
  vi.resetAllMocks();
});

// #2947 — "Trazer minha lista" só lê do servidor quando a E3 (#2896) entrar. Até
// lá, fora da demonstração o botão não pode levar a uma tela que recusa tudo.
describe('rotaDoTrazer', () => {
  it('fora da demonstração leva à importação de contatos que já funciona', () => {
    expect(rotaDoTrazer(null)).toBe('contacts_import_journey');
    expect(rotaDoTrazer(undefined)).toBe('contacts_import_journey');
  });

  it('na demonstração leva à tela nova', () => {
    expect(rotaDoTrazer('cheio')).toBe('relacionamentos_trazer');
    expect(rotaDoTrazer('vazio')).toBe('relacionamentos_trazer');
  });
});

describe('temOndeTrazer', () => {
  it('fora da demonstração, só com a importação de contatos ligada na instalação', () => {
    jornada(true);
    expect(temOndeTrazer(null)).toBe(true);
    jornada(true, false);
    expect(temOndeTrazer(null)).toBe(false);
    jornada(false);
    expect(temOndeTrazer(null)).toBe(false);
  });

  it('sem configuração nenhuma não há para onde levar', () => {
    expect(temOndeTrazer(null)).toBe(false);
  });

  it('na demonstração há sempre', () => {
    jornada(false);
    expect(temOndeTrazer('cheio')).toBe(true);
  });
});

describe('desvioDoTrazer (link direto para a tela nova)', () => {
  const destino = { query: {}, params: { accountId: '7' } };

  it('fora da demonstração manda para a importação, na mesma conta', () => {
    usarDemo.mockReturnValue(null);
    expect(desvioDoTrazer(destino)).toEqual({
      name: 'contacts_import_journey',
      params: { accountId: '7' },
    });
  });

  it('na demonstração não desvia', () => {
    usarDemo.mockReturnValue('cheio');
    expect(desvioDoTrazer({ ...destino, query: { demo: 'cheio' } })).toBeNull();
    expect(usarDemo).toHaveBeenCalledWith({ demo: 'cheio' });
  });
});
