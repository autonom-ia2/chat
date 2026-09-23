// @vitest-environment node
// O modo aprendiz da Central de Ajuda "Plataforma" (#614): a cada push, compara o
// registro de ANTES desse push com o de agora e abre UM PR com o que precisa de atenção.
// Fixtures em string/objeto; os testes de limpeza em disco usam um diretório temporário
// de verdade (a função relê o arquivo do disco a cada edição — não dá para simular isso
// só com objeto em memória).
import fs from 'fs';
import os from 'os';
import path from 'path';
import {
  substituir,
  telasNovasSemArtigo,
  montarEntradaDoMapa,
  montarArtigoMarkdown,
  pedirArtigoAoGpt,
  artigosParaRemover,
  removerArtigoDoMapa,
  removerReferenciasVejaTambem,
  limparVejaTambemDeTodos,
  marcarParaRevisao,
  evidenciasQuebradasNoPush,
  valoresI18n,
  valoresRemovidosDoI18n,
  valoresCitadosEmArtigos,
  houveMudancaRelevante,
  corpoDoPr,
} from '../aprendiz.mjs';

const mapaCom = capitulos => ({ capitulos });

const artigoDoMapa = (over = {}) => ({
  id: '02.01',
  titulo: 'Título',
  para_que_serve: 'Serve para algo.',
  publico: 'ambos',
  prioridade: 'P2',
  assuntos: [],
  rotas: ['tela_a'],
  me_leve_ate_la: { rota: 'tela_a', destaque: null },
  requer: null,
  prints: [],
  fontes: [],
  revisar: false,
  nota: null,
  ...over,
});

describe('substituir — troca sem interpretar $& e afins (String.replace não é seguro)', () => {
  it('troca o trecho, mesmo com "$" no texto novo', () => {
    const texto = 'Preço: X.';

    expect(substituir(texto, 'X', 'R$ 100 ($& não é capturado)')).toBe(
      'Preço: R$ 100 ($& não é capturado).'
    );
  });

  it('devolve o texto original quando não acha o trecho', () => {
    expect(substituir('abc', 'zzz', 'novo')).toBe('abc');
  });
});

describe('telasNovasSemArtigo — telas que entraram NESTE push e ainda não têm artigo', () => {
  it('tela nova e sem cobertura aparece', () => {
    const resultado = telasNovasSemArtigo({
      antes: ['inbox_list'],
      atual: new Set(['inbox_list', 'crm_relatorios']),
      cobertas: new Set(['inbox_list']),
    });

    expect(resultado).toEqual(['crm_relatorios']);
  });

  it('tela antiga sem artigo não conta como nova', () => {
    const resultado = telasNovasSemArtigo({
      antes: ['inbox_list', 'tela_antiga'],
      atual: new Set(['inbox_list', 'tela_antiga']),
      cobertas: new Set(['inbox_list']),
    });

    expect(resultado).toEqual([]);
  });
});

describe('montarEntradaDoMapa / montarArtigoMarkdown — o rascunho novo', () => {
  const tela = {
    nome: 'crm_relatorios',
    caminho: '/app/accounts/:accountId/crm/relatorios',
  };
  const rascunho = {
    titulo: 'Relatórios do CRM',
    publico: 'admin',
    prioridade: 'P2',
    o_que_e: 'Os relatórios do CRM mostram o funil em números.',
    por_que_importa: 'Sem eles, ninguém sabe quantos negócios fecharam.',
    como_faz:
      '**CRM → Relatórios**\n\n1. Abra o CRM.\n2. Clique em Relatórios.',
    o_que_da_errado: '- **"Não aparece nada."** Confira o período.',
    veja_tambem: ['10.01'],
    duvidas: 'não sei se agente comum vê',
  };

  it('a entrada do mapa vem com revisar: true e a rota certa', () => {
    const entrada = montarEntradaDoMapa({ id: '10.17', tela, rascunho });

    expect(entrada).toMatchObject({
      id: '10.17',
      titulo: 'Relatórios do CRM',
      rotas: ['crm_relatorios'],
      me_leve_ate_la: { rota: 'crm_relatorios', destaque: null },
      revisar: true,
    });
  });

  it('o markdown tem cabeçalho e as cinco seções, sem evidência inventada', () => {
    const md = montarArtigoMarkdown({
      id: '10.17',
      capitulo: '10',
      tela,
      rascunho,
    });

    expect(md).toContain('id: "10.17"');
    expect(md).toContain('## O que é');
    expect(md).toContain('## Por que importa');
    expect(md).toContain('## Como faz');
    expect(md).toContain('## O que dá errado');
    expect(md).toContain('## Veja também');
    expect(md).toContain('evidencias: []');
  });
});

describe('pedirArtigoAoGpt — o capítulo só pode ser um dos que já existem', () => {
  const resposta = (status, corpo) => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => corpo,
  });
  const saidaDaIa = objeto => ({
    output: [
      {
        type: 'message',
        content: [{ type: 'output_text', text: JSON.stringify(objeto) }],
      },
    ],
  });

  it('restringe o capítulo ao enum dos que existem no mapa — nada de "99"', async () => {
    let enviado;
    const buscar = async (_url, opcoes) => {
      enviado = JSON.parse(opcoes.body);
      return resposta(200, saidaDaIa({ titulo: 'X', duvidas: '' }));
    };

    await pedirArtigoAoGpt({
      tela: { nome: 'crm_relatorios', caminho: '/x' },
      contexto: 'x',
      exemplos: 'x',
      blocoPorques: null,
      kit: 'texto do kit',
      capitulos: [
        { id: '10', titulo: 'CRM' },
        { id: '02', titulo: 'Configurações' },
      ],
      idsDosArtigos: ['02.04', '10.01'],
      chave: 'sk-teste',
      buscar,
    });

    expect(enviado.text.format.schema.properties.capitulo.enum).toEqual([
      '10',
      '02',
    ]);
    expect(
      enviado.text.format.schema.properties.veja_tambem.items.enum
    ).toEqual(['02.04', '10.01']);
    expect(enviado.text.format.name).toBe('artigo_da_central');
    expect(enviado.instructions).toBe('texto do kit');
  });
});

describe('artigosParaRemover — todas as rotas sumiram, e nenhuma está em _fora_do_guia', () => {
  it('acha o artigo quando nenhuma rota dele sobrou', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_velha'] })],
      },
    ]);

    const resultado = artigosParaRemover({
      mapa,
      antesRegistro: new Set(['tela_velha', 'tela_b']),
      atualRegistro: new Set(['tela_b']),
      humanos: {},
    });

    expect(resultado.map(a => a.id)).toEqual(['02.01']);
  });

  // A rota já tinha sumido antes deste push: o PR daquela remoção é outro. Sem isto,
  // cada push seguinte abriria um PR novo para o mesmo artigo.
  it('não acha de novo quando a rota já tinha sumido antes deste push', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_velha'] })],
      },
    ]);

    const resultado = artigosParaRemover({
      mapa,
      antesRegistro: new Set(['tela_b']),
      atualRegistro: new Set(['tela_b']),
      humanos: {},
    });

    expect(resultado).toEqual([]);
  });

  it('não acha quando ainda sobrou alguma rota (limpeza parcial foi removida desta etapa)', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_a', 'tela_b'] })],
      },
    ]);

    const resultado = artigosParaRemover({
      mapa,
      antesRegistro: new Set(['tela_a', 'tela_b']),
      atualRegistro: new Set(['tela_a']),
      humanos: {},
    });

    expect(resultado).toEqual([]);
  });

  // A rota não sumiu do produto — só foi reclassificada fora do Guia (tela de sistema,
  // redirecionamento). Tratar como "removida" apagaria um artigo que ainda vale.
  it('não acha quando a rota que sumiu está declarada em _fora_do_guia', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_sistema'] })],
      },
    ]);

    const resultado = artigosParaRemover({
      mapa,
      antesRegistro: new Set(['tela_sistema']),
      atualRegistro: new Set([]),
      humanos: { _fora_do_guia: { tela_sistema: 'redirecionamento puro' } },
    });

    expect(resultado).toEqual([]);
  });
});

describe('removerArtigoDoMapa — tira o artigo, sem mexer nos outros', () => {
  it('tira só o id pedido', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01' }), artigoDoMapa({ id: '02.02' })],
      },
    ]);

    const novo = removerArtigoDoMapa(mapa, '02.01');

    expect(novo.capitulos[0].artigos.map(a => a.id)).toEqual(['02.02']);
    expect(mapa.capitulos[0].artigos).toHaveLength(2); // original intacto
  });
});

describe('removerReferenciasVejaTambem — tira a linha, reporta o resto', () => {
  it('tira a linha "- [id] Título" inteira', () => {
    const corpo = [
      '## Veja também',
      '',
      '- [02.01] Outro',
      '- [02.09] Removido',
    ].join('\n');

    const { corpo: novo, citacoesNoMeio } = removerReferenciasVejaTambem(
      corpo,
      '02.09'
    );

    expect(novo).not.toContain('02.09');
    expect(novo).toContain('- [02.01] Outro');
    expect(citacoesNoMeio).toEqual([]);
  });

  it('cita no meio do texto vai para a lista, sem editar a frase', () => {
    const corpo = 'Antes de tudo, veja [02.09] para entender o contexto.';

    const { corpo: novo, citacoesNoMeio } = removerReferenciasVejaTambem(
      corpo,
      '02.09'
    );

    expect(novo).toBe(corpo);
    expect(citacoesNoMeio).toEqual([corpo]);
  });
});

describe('limparVejaTambemDeTodos — relê o disco a cada edição, dois artigos, sem ENOENT', () => {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'central-aprendiz-veja-'));

  const artigoTexto = (id, corpoExtra) =>
    [
      '---',
      `id: "${id}"`,
      'titulo: "Teste"',
      '---',
      '## Veja também',
      '',
      '- [02.09] Removido',
      '- [02.10] Também removido',
      corpoExtra || '',
    ].join('\n');

  beforeAll(() => {
    fs.mkdirSync(path.join(raiz, 'lib/central_de_ajuda/02'), {
      recursive: true,
    });
    fs.writeFileSync(
      path.join(raiz, 'lib/central_de_ajuda/02/02.01-b.md'),
      artigoTexto('02.01')
    );
    fs.writeFileSync(
      path.join(raiz, 'lib/central_de_ajuda/02/02.02-c.md'),
      artigoTexto('02.02', 'Veja [02.09] no meio da frase também.')
    );
  });

  afterAll(() => fs.rmSync(raiz, { recursive: true, force: true }));

  it('limpa os dois ids removidos nos dois artigos, sem quebrar em arquivo inexistente', () => {
    const artigosRestantes = [
      { arquivo: '02.01-b.md', caminho: 'lib/central_de_ajuda/02/02.01-b.md' },
      { arquivo: '02.02-c.md', caminho: 'lib/central_de_ajuda/02/02.02-c.md' },
      {
        arquivo: 'nao-existe.md',
        caminho: 'lib/central_de_ajuda/02/nao-existe.md',
      },
    ];

    const citacoesNoMeio = limparVejaTambemDeTodos(
      artigosRestantes,
      ['02.09', '02.10'],
      raiz
    );

    const textoB = fs.readFileSync(
      path.join(raiz, 'lib/central_de_ajuda/02/02.01-b.md'),
      'utf8'
    );
    const textoC = fs.readFileSync(
      path.join(raiz, 'lib/central_de_ajuda/02/02.02-c.md'),
      'utf8'
    );

    expect(textoB).not.toContain('[02.09]');
    expect(textoB).not.toContain('[02.10]');
    expect(textoC).not.toContain('- [02.09]');
    expect(textoC).not.toContain('- [02.10]');
    // A citação no meio da frase, em 02.02-c.md, não foi editada e foi reportada.
    expect(textoC).toContain('Veja [02.09] no meio da frase também.');
    expect(citacoesNoMeio).toEqual([{ id: '02.09', arquivo: '02.02-c.md' }]);
  });
});

describe('marcarParaRevisao — revisar: true + nota, junta motivos do mesmo artigo', () => {
  it('marca revisar e grava a nota', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', revisar: false, nota: null })],
      },
    ]);

    const novo = marcarParaRevisao(
      mapa,
      '02.01',
      'evidência sumiu: app/foo.rb:12'
    );

    expect(novo.capitulos[0].artigos[0]).toMatchObject({
      revisar: true,
      nota: 'evidência sumiu: app/foo.rb:12',
    });
  });

  it('junta o motivo novo ao motivo já marcado, sem perder o anterior', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [
          artigoDoMapa({ id: '02.01', revisar: true, nota: 'primeiro motivo' }),
        ],
      },
    ]);

    const novo = marcarParaRevisao(mapa, '02.01', 'segundo motivo');

    expect(novo.capitulos[0].artigos[0].nota).toBe(
      'primeiro motivo; segundo motivo'
    );
  });
});

describe('evidenciasQuebradasNoPush — só a que aponta para arquivo alterado neste push', () => {
  const raiz = fs.mkdtempSync(
    path.join(os.tmpdir(), 'central-aprendiz-evidencia-')
  );

  beforeAll(() => {
    fs.mkdirSync(path.join(raiz, 'app/models'), { recursive: true });
    fs.writeFileSync(
      path.join(raiz, 'app/models/user.rb'),
      'class User\nend\n'
    );
  });

  afterAll(() => fs.rmSync(raiz, { recursive: true, force: true }));

  const artigo = evidencias => ({
    arquivo: '00.01-artigo.md',
    cabecalho: { id: '00.01', evidencias },
  });

  it('trecho sumiu, e o arquivo ESTÁ na lista de alterados: entra', () => {
    const artigos = [artigo(['app/models/user.rb:2 | def nome_antigo'])];

    const resultado = evidenciasQuebradasNoPush({
      artigos,
      raiz,
      arquivosAlterados: new Set(['app/models/user.rb']),
    });

    expect(resultado).toHaveLength(1);
    expect(resultado[0].situacao).toBe('trecho_sumiu');
  });

  it('trecho sumiu, mas o arquivo NÃO está na lista de alterados: não entra', () => {
    const artigos = [artigo(['app/models/user.rb:2 | def nome_antigo'])];

    const resultado = evidenciasQuebradasNoPush({
      artigos,
      raiz,
      arquivosAlterados: new Set(['app/outro.rb']),
    });

    expect(resultado).toEqual([]);
  });
});

describe('valoresI18n / valoresRemovidosDoI18n / valoresCitadosEmArtigos', () => {
  it('valoresI18n pega string aninhada, ignora número e booleano', () => {
    expect(valoresI18n({ A: { B: 'Texto' }, C: 1, D: true })).toEqual([
      'Texto',
    ]);
  });

  it('valoresRemovidosDoI18n: some de todos os arquivos', () => {
    const antes = [{ A: 'Texto antigo' }, { B: 'Outro' }];
    const depois = [{ A: 'Texto novo' }, { B: 'Outro' }];

    expect(valoresRemovidosDoI18n(antes, depois)).toEqual(['Texto antigo']);
  });

  it('valoresRemovidosDoI18n: só mudou de arquivo não conta como saiu', () => {
    const antes = [{ A: 'Texto' }, { B: 'Outro' }];
    const depois = [{ A: 'Outro' }, { B: 'Texto' }];

    expect(valoresRemovidosDoI18n(antes, depois)).toEqual([]);
  });

  it('valoresCitadosEmArtigos: só quem cita em negrito entra', () => {
    const artigos = [
      { arquivo: 'a.md', corpo: 'Clique em **Salvar alterações**.' },
      { arquivo: 'b.md', corpo: 'Nada aqui.' },
    ];

    expect(
      valoresCitadosEmArtigos(['Salvar alterações', 'Sem uso'], artigos)
    ).toEqual([{ valor: 'Salvar alterações', artigos: ['a.md'] }]);
  });
});

describe('houveMudancaRelevante — nada relevante, sem escrita', () => {
  it('tudo vazio: false', () => {
    expect(
      houveMudancaRelevante({
        novas: [],
        removidos: [],
        evidenciasQuebradas: [],
        i18nCitado: [],
      })
    ).toBe(false);
  });

  it('qualquer uma não-vazia: true', () => {
    expect(
      houveMudancaRelevante({
        novas: [],
        removidos: [{ id: '02.01' }],
        evidenciasQuebradas: [],
        i18nCitado: [],
      })
    ).toBe(true);
  });
});

describe('corpoDoPr — o corpo do Pull Request do robô', () => {
  it('avisa que o PR do robô não dispara os checks', () => {
    const corpo = corpoDoPr({
      commit: 'abc1234',
      rascunhos: [],
      removidos: [],
      citacoesNoMeio: [],
      paraRevisaoPorEvidencia: [],
      paraRevisaoPorI18n: [],
    });

    expect(corpo).toContain(
      'PR aberto pelo robô não dispara os checks; feche e reabra para rodar a trava'
    );
  });

  it('avisa sobre renomeação quando há rascunho novo E remoção juntos', () => {
    const corpo = corpoDoPr({
      commit: 'abc1234',
      rascunhos: [
        {
          id: '10.17',
          tela: { nome: 'crm_relatorios' },
          rascunho: { duvidas: '' },
        },
      ],
      removidos: [{ id: '02.09', titulo: 'Tela antiga' }],
      citacoesNoMeio: [],
      paraRevisaoPorEvidencia: [],
      paraRevisaoPorI18n: [],
    });

    expect(corpo).toContain('renomeação');
    expect(corpo).toContain('junte à mão');
  });

  it('lista citação no meio do texto com o nome do artigo onde está', () => {
    const corpo = corpoDoPr({
      commit: 'abc1234',
      rascunhos: [],
      removidos: [{ id: '02.09', titulo: 'Tela antiga' }],
      citacoesNoMeio: [{ id: '02.09', arquivo: '05.02-b.md' }],
      paraRevisaoPorEvidencia: [],
      paraRevisaoPorI18n: [],
    });

    expect(corpo).toContain('02.09');
    expect(corpo).toContain('05.02-b.md');
  });

  it('lista revisão por evidência e por i18n', () => {
    const corpo = corpoDoPr({
      commit: 'abc1234',
      rascunhos: [],
      removidos: [],
      citacoesNoMeio: [],
      paraRevisaoPorEvidencia: [
        { id: '02.06', motivo: 'evidência sumiu: app/models/user.rb:12' },
      ],
      paraRevisaoPorI18n: [
        { id: '02.04', motivo: 'texto de tela "Salvar" saiu do i18n' },
      ],
    });

    expect(corpo).toContain('02.06');
    expect(corpo).toContain('app/models/user.rb:12');
    expect(corpo).toContain('02.04');
    expect(corpo).toContain('Salvar');
  });
});
