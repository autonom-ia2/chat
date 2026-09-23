// @vitest-environment node
// O modo aprendiz da Central de Ajuda "Plataforma" (#614, etapa C): depois do merge,
// compara o registro do deploy anterior com o de agora e abre UM PR com o que mudou.
// Fixtures em string/objeto — sem tocar disco, no estilo dos outros specs deste módulo.
import {
  proximoIdDoCapitulo,
  artigosParaRemover,
  artigosParaLimparRotas,
  removerReferenciasVejaTambem,
  removerArtigoDoMapa,
  limparRotasNoMapa,
  paresAntigoNovoPorChave,
  substituirValorEmArtigos,
  corrigirEvidenciasDeLinha,
  montarEntradaDoMapa,
  montarArtigoMarkdown,
  pedirArtigoAoGpt,
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

describe('proximoIdDoCapitulo — próximo id livre dentro do capítulo', () => {
  it('sobe 1 a partir do maior id existente', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01' }), artigoDoMapa({ id: '02.08' })],
      },
    ]);

    expect(proximoIdDoCapitulo(mapa, '02')).toBe('02.09');
  });

  it('capítulo sem artigo nenhum começa em .01', () => {
    const mapa = mapaCom([{ id: '05', titulo: 'Cap', artigos: [] }]);

    expect(proximoIdDoCapitulo(mapa, '05')).toBe('05.01');
  });

  it('preenche com zero à esquerda até dois dígitos', () => {
    const mapa = mapaCom([
      { id: '00', titulo: 'Cap', artigos: [artigoDoMapa({ id: '00.09' })] },
    ]);

    expect(proximoIdDoCapitulo(mapa, '00')).toBe('00.10');
  });
});

describe('artigosParaRemover — artigo cujas rotas sumiram TODAS do registro', () => {
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
      atualRegistro: new Set(['tela_b']),
    });

    expect(resultado.map(a => a.id)).toEqual(['02.01']);
  });

  it('não acha quando ainda sobrou alguma rota', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_a', 'tela_b'] })],
      },
    ]);

    const resultado = artigosParaRemover({
      mapa,
      atualRegistro: new Set(['tela_a']),
    });

    expect(resultado).toEqual([]);
  });
});

describe('artigosParaLimparRotas — artigo que perdeu ALGUMA rota, não todas', () => {
  it('lista a rota que sumiu, sem contar o artigo inteiro como removido', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_a', 'tela_b'] })],
      },
    ]);

    const resultado = artigosParaLimparRotas({
      mapa,
      atualRegistro: new Set(['tela_a']),
    });

    expect(resultado).toEqual([
      { artigo: mapa.capitulos[0].artigos[0], rotasQuePerderam: ['tela_b'] },
    ]);
  });

  it('artigo que perdeu todas as rotas não entra aqui (é artigosParaRemover)', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_a'] })],
      },
    ]);

    const resultado = artigosParaLimparRotas({
      mapa,
      atualRegistro: new Set([]),
    });

    expect(resultado).toEqual([]);
  });
});

describe('removerReferenciasVejaTambem — tira a linha do "Veja também", reporta o resto', () => {
  it('tira a linha "- [id] Título" inteira', () => {
    const corpo = [
      '## Veja também',
      '',
      '- [02.01] Outro artigo',
      '- [02.09] Artigo removido',
    ].join('\n');

    const { corpo: novo, citacoesNoMeio } = removerReferenciasVejaTambem(
      corpo,
      '02.09'
    );

    expect(novo).not.toContain('02.09');
    expect(novo).toContain('- [02.01] Outro artigo');
    expect(citacoesNoMeio).toEqual([]);
  });

  it('cita no meio do texto vai para a lista, sem editar a frase', () => {
    const corpo = 'Antes de tudo, veja [02.09] para entender o contexto.';

    const { corpo: novo, citacoesNoMeio } = removerReferenciasVejaTambem(
      corpo,
      '02.09'
    );

    expect(novo).toBe(corpo);
    expect(citacoesNoMeio).toEqual([
      'Antes de tudo, veja [02.09] para entender o contexto.',
    ]);
  });
});

describe('removerArtigoDoMapa / limparRotasNoMapa — mudança imutável no mapa', () => {
  it('tira o artigo do capítulo, sem mexer nos outros', () => {
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

  it('tira só a rota que sumiu, mantendo as outras', () => {
    const mapa = mapaCom([
      {
        id: '02',
        titulo: 'Cap',
        artigos: [artigoDoMapa({ id: '02.01', rotas: ['tela_a', 'tela_b'] })],
      },
    ]);

    const novo = limparRotasNoMapa(mapa, '02.01', ['tela_b']);

    expect(novo.capitulos[0].artigos[0].rotas).toEqual(['tela_a']);
  });
});

describe('paresAntigoNovoPorChave — mesmo caminho no JSON, valor diferente', () => {
  it('acha o par quando a MESMA chave muda de valor', () => {
    const antes = { BUTTON: { SAVE: 'Salvar' } };
    const depois = { BUTTON: { SAVE: 'Salvar alterações' } };

    expect(paresAntigoNovoPorChave(antes, depois)).toEqual([
      { antigo: 'Salvar', novo: 'Salvar alterações' },
    ]);
  });

  it('não acha par quando o valor é igual', () => {
    expect(paresAntigoNovoPorChave({ A: 'Texto' }, { A: 'Texto' })).toEqual([]);
  });

  it('não acha par quando a chave sumiu (isso é "saiu", não "mudou")', () => {
    expect(paresAntigoNovoPorChave({ A: 'Texto' }, {})).toEqual([]);
  });
});

describe('substituirValorEmArtigos — troca **antigo** por **novo** no corpo', () => {
  it('troca só nos artigos que citam o valor antigo', () => {
    const artigos = [
      { arquivo: 'a.md', corpo: 'Clique em **Salvar**.' },
      { arquivo: 'b.md', corpo: 'Nada aqui.' },
    ];

    const alterados = substituirValorEmArtigos(artigos, [
      { antigo: 'Salvar', novo: 'Salvar alterações' },
    ]);

    expect(alterados).toEqual([
      { arquivo: 'a.md', corpo: 'Clique em **Salvar alterações**.' },
    ]);
  });
});

describe('corrigirEvidenciasDeLinha — número novo, trecho igual', () => {
  it('troca só a linha da evidência que mudou de número', () => {
    const texto = [
      'evidencias:',
      '  - "app/models/user.rb:1 | def nome"',
      '  - "app/models/user.rb:9 | def outro"',
    ].join('\n');

    const novo = corrigirEvidenciasDeLinha(texto, [
      {
        caminho: 'app/models/user.rb',
        numero: 1,
        trecho: 'def nome',
        novaLinha: 2,
      },
    ]);

    expect(novo).toContain('"app/models/user.rb:2 | def nome"');
    expect(novo).toContain('"app/models/user.rb:9 | def outro"');
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
    const entrada = montarEntradaDoMapa({
      id: '10.17',
      tela,
      rascunho,
      requer: null,
    });

    expect(entrada).toMatchObject({
      id: '10.17',
      titulo: 'Relatórios do CRM',
      rotas: ['crm_relatorios'],
      me_leve_ate_la: { rota: 'crm_relatorios', destaque: null },
      requer: null,
      revisar: true,
    });
  });

  it('o markdown tem cabeçalho e as cinco seções, sem evidência inventada', () => {
    const md = montarArtigoMarkdown({
      id: '10.17',
      capitulo: '10',
      tela,
      rascunho,
      requer: null,
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

describe('pedirArtigoAoGpt — usa pedirAoGpt (mesmo mecanismo do Guia)', () => {
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

  it('manda o kit como instrução e devolve o rascunho', async () => {
    let enviado;
    const buscar = async (_url, opcoes) => {
      enviado = JSON.parse(opcoes.body);
      return resposta(
        200,
        saidaDaIa({ titulo: 'Relatórios do CRM', duvidas: '' })
      );
    };

    const rascunho = await pedirArtigoAoGpt({
      tela: { nome: 'crm_relatorios', caminho: '/x' },
      contexto: 'código da tela',
      exemplos: 'dois artigos de exemplo',
      blocoPorques: 'bloco do porques.md',
      kit: 'texto do kit do escritor',
      capitulos: [{ id: '10', titulo: 'CRM' }],
      chave: 'sk-teste',
      buscar,
    });

    expect(rascunho.titulo).toBe('Relatórios do CRM');
    expect(enviado.instructions).toBe('texto do kit do escritor');
    expect(enviado.input).toContain('crm_relatorios');
    expect(enviado.input).toContain('10 - CRM');
    expect(enviado.text.format.strict).toBe(true);
  });

  // A IA só escolhe entre os capítulos que já existem (ou "99" — nunca inventa numeração).
  it('restringe o capítulo aos que existem no mapa, mais "99"', async () => {
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
      kit: 'x',
      capitulos: [
        { id: '10', titulo: 'CRM' },
        { id: '02', titulo: 'Configurações' },
      ],
      chave: 'sk-teste',
      buscar,
    });

    expect(enviado.text.format.schema.properties.capitulo.enum).toEqual([
      '10',
      '02',
      '99',
    ]);
  });
});

describe('corpoDoPr — o corpo do Pull Request do robô', () => {
  it('avisa que o PR do robô não dispara os checks', () => {
    const corpo = corpoDoPr({
      commit: 'abc1234',
      rascunhos: [],
      removidos: [],
      limpezasDeRotas: [],
      i18nMudou: [],
      i18nSaiuCitado: [],
      paraRevisao: [],
    });

    expect(corpo).toContain(
      'PR aberto pelo robô não dispara os checks; feche e reabra para rodar a trava'
    );
  });

  it('lista rascunho novo, remoção e revisão pendente', () => {
    const corpo = corpoDoPr({
      commit: 'abc1234',
      rascunhos: [
        {
          id: '10.17',
          tela: { nome: 'crm_relatorios' },
          rascunho: { duvidas: 'não sei quem vê' },
        },
      ],
      removidos: [{ id: '02.09', titulo: 'Tela antiga' }],
      limpezasDeRotas: [{ id: '05.02', rotasQuePerderam: ['tela_b'] }],
      i18nMudou: [{ antigo: 'Salvar', novo: 'Salvar alterações' }],
      i18nSaiuCitado: [{ valor: 'Texto sumido', artigos: ['02.04-a.md'] }],
      paraRevisao: [
        { artigo: '02.06-a.md', caminho: 'app/models/user.rb', numero: 12 },
      ],
    });

    expect(corpo).toContain('10.17');
    expect(corpo).toContain('não sei quem vê');
    expect(corpo).toContain('02.09');
    expect(corpo).toContain('05.02');
    expect(corpo).toContain('tela_b');
    expect(corpo).toContain('Salvar alterações');
    expect(corpo).toContain('Texto sumido');
    expect(corpo).toContain('02.06-a.md');
  });
});
