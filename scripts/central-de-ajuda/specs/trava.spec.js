// @vitest-environment node
// A trava da Central de Ajuda "Plataforma" no Pull Request (#614): roda `conferir()`
// (o mesmo central:check) e comenta o que fazer quando falha. Sem dispensa por rótulo —
// retirada depois da revisão independente (rótulo sem motivo escrito não deixava rastro
// de por que a tela ficou fora).
import * as trava from '../trava.mjs';
import { conferir } from '../conferir.mjs';
import { MARCA_DO_COMENTARIO, comentarioDaTrava } from '../trava.mjs';

const artigo = ({ id, rota, corpo = '' }) => ({
  caminho: `lib/central_de_ajuda/00/${id}-artigo.md`,
  arquivo: `${id}-artigo.md`,
  cabecalho: { id, me_leve_ate_la: { rota, destaque: null } },
  corpo,
});

const artigoDoMapa = ({ id, rotas, rota = rotas[0] }) => ({
  id,
  titulo: `Artigo ${id}`,
  rotas,
  me_leve_ate_la: { rota, destaque: null },
});

const mapaCom = (artigosDoMapa, fora = []) => ({
  capitulos: [{ id: '00', titulo: 'Comece por aqui', artigos: artigosDoMapa }],
  fora,
});

describe('a dispensa por rótulo foi removida', () => {
  it('não exporta mais decidir, motivoDaDispensa nem o rótulo de dispensa', () => {
    expect(trava.decidir).toBeUndefined();
    expect(trava.motivoDaDispensa).toBeUndefined();
    expect(trava.ROTULO_DISPENSA).toBeUndefined();
    expect(trava.novasSemArtigo).toBeUndefined();
  });
});

describe('conferir() + comentarioDaTrava — tela nova sem artigo barra', () => {
  it('tela do registro sem nenhum artigo vira problema e barra', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom([artigoDoMapa({ id: '00.01', rotas: ['tela_a'] })]);
    const registro = new Set(['tela_a', 'tela_nova_sem_artigo']);

    const resultado = conferir({ artigos, mapa, registro, humanos: {} });
    const comentario = comentarioDaTrava({ problemas: resultado.problemas });

    expect(resultado.ok).toBe(false);
    expect(comentario).toContain('tela_nova_sem_artigo');
    expect(comentario).toContain('fora de dia');
    expect(comentario).toContain('mapa.fora');
  });
});

describe('conferir() + comentarioDaTrava — tela em mapa.fora passa', () => {
  it('tela declarada em mapa.fora não bloqueia, e o comentário fica "em dia"', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom(
      [artigoDoMapa({ id: '00.01', rotas: ['tela_a'] })],
      [{ rota: 'tela_fora_do_produto', motivo: 'redirecionamento puro' }]
    );
    const registro = new Set(['tela_a', 'tela_fora_do_produto']);

    const resultado = conferir({ artigos, mapa, registro, humanos: {} });
    const comentario = comentarioDaTrava({ problemas: resultado.problemas });

    expect(resultado.ok).toBe(true);
    expect(comentario).toContain('Central em dia');
    expect(comentario.startsWith(MARCA_DO_COMENTARIO)).toBe(true);
  });
});

describe('comentarioDaTrava — formato', () => {
  it('sempre leva a marca que o workflow procura', () => {
    expect(
      comentarioDaTrava({ problemas: [] }).startsWith(MARCA_DO_COMENTARIO)
    ).toBe(true);
    expect(
      comentarioDaTrava({ problemas: ['x'] }).startsWith(MARCA_DO_COMENTARIO)
    ).toBe(true);
  });

  it('lista as duas saídas quando barra: escrever o artigo, ou mapa.fora', () => {
    const comentario = comentarioDaTrava({
      problemas: ['Alguma coisa quebrada'],
    });

    expect(comentario).toContain('Escrever o artigo');
    expect(comentario).toContain('Declarar fora do produto');
    expect(comentario).toContain('mapa.fora');
    expect(comentario).toContain('Alguma coisa quebrada');
  });
});
