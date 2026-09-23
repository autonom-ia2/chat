// @vitest-environment node
// Confere a Central de Ajuda "Plataforma" contra o Guia da Plataforma (#614). Fixtures em
// string/objeto, no estilo de scripts/guide-map/specs/build.spec.js — sem tocar disco aqui.
import fs from 'fs';
import os from 'os';
import path from 'path';
import {
  separarArtigo,
  lerArtigos,
  telasCobertas,
  telasSemArtigo,
  referenciasQuebradas,
  meLeveDivergente,
  artigosSemMapa,
  mapaSemArquivo,
  idDivergenteDoArquivo,
  conferir,
} from '../conferir.mjs';

// Um artigo mínimo, só com o que cada teste precisa.
const artigo = ({ id, rota, destaque = null, corpo = '' }) => ({
  caminho: `lib/central_de_ajuda/00/${id}-artigo.md`,
  arquivo: `${id}-artigo.md`,
  cabecalho: { id, me_leve_ate_la: { rota, destaque } },
  corpo,
});

const artigoDoMapa = ({ id, rotas, rota = rotas[0], destaque = null }) => ({
  id,
  titulo: `Artigo ${id}`,
  rotas,
  me_leve_ate_la: { rota, destaque },
});

const mapaCom = (artigos, fora = []) => ({
  capitulos: [{ id: '00', titulo: 'Comece por aqui', artigos }],
  fora,
});

describe('separarArtigo — cabeçalho YAML e corpo', () => {
  it('separa o cabeçalho do corpo', () => {
    const texto =
      '---\nid: "00.01"\ntitulo: "Teste"\n---\n\n## O que é\n\nTexto.\n';

    const { cabecalho, corpo } = separarArtigo(texto, 'teste.md');

    expect(cabecalho).toEqual({ id: '00.01', titulo: 'Teste' });
    expect(corpo).toBe('\n## O que é\n\nTexto.\n');
  });

  it('recusa arquivo sem cabeçalho', () => {
    expect(() => separarArtigo('sem cabeçalho aqui', 'teste.md')).toThrow(
      /sem cabeçalho/
    );
  });

  it('recusa cabeçalho sem fechamento', () => {
    expect(() => separarArtigo('---\nid: "00.01"\n', 'teste.md')).toThrow(
      /sem fechamento/
    );
  });
});

describe('lerArtigos — lê lib/central_de_ajuda/*/*.md do disco', () => {
  it('lê cabeçalho e corpo de cada artigo, ordenado por caminho', () => {
    const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'central-de-ajuda-'));
    fs.mkdirSync(path.join(raiz, 'lib/central_de_ajuda/00'), {
      recursive: true,
    });
    fs.writeFileSync(
      path.join(raiz, 'lib/central_de_ajuda/00/00.02-segundo.md'),
      '---\nid: "00.02"\ntitulo: "Segundo"\n---\nCorpo 2\n'
    );
    fs.writeFileSync(
      path.join(raiz, 'lib/central_de_ajuda/00/00.01-primeiro.md'),
      '---\nid: "00.01"\ntitulo: "Primeiro"\n---\nCorpo 1\n'
    );

    const artigos = lerArtigos(raiz);

    expect(artigos.map(a => a.cabecalho.id)).toEqual(['00.01', '00.02']);
    expect(artigos[0].corpo).toBe('Corpo 1\n');
    expect(artigos[0].arquivo).toBe('00.01-primeiro.md');
  });
});

describe('telasCobertas — rotas que já têm explicação', () => {
  it('junta me_leve_ate_la dos artigos, rotas do mapa e rotas de mapa.fora', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom(
      [artigoDoMapa({ id: '00.01', rotas: ['tela_a', 'tela_b'] })],
      [{ rota: 'tela_c', motivo: 'redirecionamento puro' }]
    );

    const cobertas = telasCobertas(mapa, artigos);

    expect(cobertas).toEqual(new Set(['tela_a', 'tela_b', 'tela_c']));
  });
});

describe('telasSemArtigo — telas do Guia sem explicação na Central', () => {
  it('tela nova, sem artigo nenhum, aparece', () => {
    const registro = new Set(['tela_nova']);
    const problema = telasSemArtigo(registro, new Set(), {});

    expect(problema).toEqual(['tela_nova']);
  });

  it('tela coberta pelo mapa (mapa.fora) não aparece', () => {
    const registro = new Set(['tela_fora']);
    const cobertas = new Set(['tela_fora']);

    expect(telasSemArtigo(registro, cobertas, {})).toEqual([]);
  });

  it('tela declarada em _fora_do_guia do porques.md não aparece', () => {
    const registro = new Set(['tela_fora_do_guia']);
    const humanos = {
      _fora_do_guia: { tela_fora_do_guia: 'tela de sistema' },
    };

    expect(telasSemArtigo(registro, new Set(), humanos)).toEqual([]);
  });
});

describe('referenciasQuebradas — [dd.dd] que não existe no mapa', () => {
  it('[99.99] quebrado aparece', () => {
    const artigos = [
      artigo({ id: '00.01', rota: 'tela_a', corpo: 'Veja [99.99] para mais.' }),
    ];
    const idsDoMapa = new Set(['00.01']);

    const quebradas = referenciasQuebradas(artigos, idsDoMapa);

    expect(quebradas).toEqual([
      { artigo: '00.01-artigo.md', referencia: '99.99' },
    ]);
  });

  it('[02.04](http...) já é link e não conta como quebrada', () => {
    const artigos = [
      artigo({
        id: '00.01',
        rota: 'tela_a',
        corpo: 'Veja [02.04](http://exemplo.com) para mais.',
      }),
    ];
    const idsDoMapa = new Set(['00.01']);

    expect(referenciasQuebradas(artigos, idsDoMapa)).toEqual([]);
  });

  it('[02.04] que existe no mapa não é quebrada', () => {
    const artigos = [
      artigo({ id: '00.01', rota: 'tela_a', corpo: 'Veja [02.04] para mais.' }),
    ];
    const idsDoMapa = new Set(['00.01', '02.04']);

    expect(referenciasQuebradas(artigos, idsDoMapa)).toEqual([]);
  });
});

describe('meLeveDivergente — cabeçalho e mapa apontam para rotas diferentes', () => {
  it('me_leve_ate_la divergente aparece', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom([
      artigoDoMapa({ id: '00.01', rotas: ['tela_a'], rota: 'tela_b' }),
    ]);

    expect(meLeveDivergente(artigos, mapa)).toEqual(['00.01']);
  });

  it('me_leve_ate_la igual não aparece', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom([artigoDoMapa({ id: '00.01', rotas: ['tela_a'] })]);

    expect(meLeveDivergente(artigos, mapa)).toEqual([]);
  });
});

describe('artigosSemMapa / mapaSemArquivo — disco e mapa desalinhados', () => {
  it('artigo no disco sem entrada no mapa aparece', () => {
    const artigos = [artigo({ id: '00.09', rota: 'tela_orfa' })];
    const mapa = mapaCom([]);

    expect(artigosSemMapa(artigos, mapa)).toEqual(['00.09-artigo.md']);
  });

  it('entrada do mapa sem arquivo no disco aparece', () => {
    const artigos = [];
    const mapa = mapaCom([artigoDoMapa({ id: '00.09', rotas: ['tela_orfa'] })]);

    expect(mapaSemArquivo(artigos, mapa)).toEqual(['00.09']);
  });
});

describe('idDivergenteDoArquivo — id do cabeçalho != prefixo do nome do arquivo', () => {
  it('acusa quando o id do cabeçalho não bate com o nome do arquivo', () => {
    const artigos = [
      {
        arquivo: '00.01-primeiro.md',
        cabecalho: { id: '00.02' },
      },
    ];

    expect(idDivergenteDoArquivo(artigos)).toEqual(['00.01-primeiro.md']);
  });

  it('não acusa quando bate', () => {
    const artigos = [
      { arquivo: '00.01-primeiro.md', cabecalho: { id: '00.01' } },
    ];

    expect(idDivergenteDoArquivo(artigos)).toEqual([]);
  });
});

describe('conferir — junta todos os problemas', () => {
  it('sem problema nenhum, ok e contadores batem', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom([artigoDoMapa({ id: '00.01', rotas: ['tela_a'] })]);
    const registro = new Set(['tela_a']);

    const resultado = conferir({ artigos, mapa, registro, humanos: {} });

    expect(resultado.ok).toBe(true);
    expect(resultado.artigos).toBe(1);
    expect(resultado.telas).toBe(1);
  });

  it('com problema, ok fica falso e a lista descreve o problema', () => {
    const artigos = [artigo({ id: '00.01', rota: 'tela_a' })];
    const mapa = mapaCom([artigoDoMapa({ id: '00.01', rotas: ['tela_a'] })]);
    const registro = new Set(['tela_a', 'tela_sem_artigo']);

    const resultado = conferir({ artigos, mapa, registro, humanos: {} });

    expect(resultado.ok).toBe(false);
    expect(resultado.problemas.join('\n')).toContain('tela_sem_artigo');
  });
});
