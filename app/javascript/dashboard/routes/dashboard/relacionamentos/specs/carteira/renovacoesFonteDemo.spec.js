import { FUNIL_PAROU } from '../../carteira/funilDasRenovacoes';
import { esquecerAjustesDaDemo } from '../../demo/carteiraAjustes';
import { renovacoesFonte } from '../../fonte/renovacoesFonte';
import { carregarDemonstracao } from './apoio';

// Os ajustes das renovações na demonstração (#2898), no formato do servidor:
// `escolha` diz como está a escolha do funil, e o funil que parou de servir
// (`?demo-carteira=funil-arquivado` ou `funil-apagado`) não vem em `ajustes`.
// A fonte real está em renovacoesFonteReal.spec.js.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({ default: {} }));

const fonte = (demo = 'cheio', peca = null) =>
  renovacoesFonte({ demo, peca, atraso: 0 });
const OUTRO_FUNIL = { funilId: 2, etapaId: 21, dias: 45, mensagens: 'mandar' };

// Os módulos da demonstração chegam por import() dinâmico: baixados antes, a
// fonte responde na hora.
beforeAll(async () => {
  await carregarDemonstracao();
  await import('../../demo/carteiraAjustes.js');
  await import('../../demo/carteiraResultados.js');
}, 60000);
afterEach(esquecerAjustesDaDemo);

describe('os ajustes das renovações na demonstração', () => {
  it('a conta cheia já escolheu o funil', async () => {
    const lido = await fonte().ajustes();

    expect(lido.escolha).toBe('feita');
    expect(lido.funilParou).toBe('');
    expect(lido.ajustes).toMatchObject({ funilId: 1, etapaId: 11 });
    expect(lido.semPermissao).toBe(false);
  });

  it('a conta sem seguro nunca escolheu, e isso não é funil parado', async () => {
    const lido = await fonte('sem-seguros').ajustes();

    expect(lido.escolha).toBe('nunca_feita');
    expect(lido.funilParou).toBe('');
    expect(lido.ajustes).toMatchObject({ funilId: null, etapaId: null });
  });

  it.each([
    ['funil-arquivado', 'funil_arquivado', FUNIL_PAROU.ARQUIVADO],
    ['funil-apagado', 'sumiu', FUNIL_PAROU.APAGADO],
  ])(
    'a peça %s mostra o funil que parou: sem funil nos ajustes, com os dias',
    async (peca, escolha, estado) => {
      const lido = await fonte('cheio', peca).ajustes();

      expect(lido.escolha).toBe(escolha);
      expect(lido.funilParou).toBe(estado);
      expect(lido.ajustes).toMatchObject({
        funilId: null,
        etapaId: null,
        dias: 60,
      });
      expect(lido.funis.length).toBeGreaterThan(0);
    }
  );

  it('salvar outro funil tira a conta do estado parado', async () => {
    const parada = fonte('cheio', 'funil-arquivado');

    await parada.salvar(OUTRO_FUNIL);
    const lido = await parada.ajustes();

    expect(lido.escolha).toBe('feita');
    expect(lido.funilParou).toBe('');
    expect(lido.ajustes).toEqual(OUTRO_FUNIL);
  });
});
