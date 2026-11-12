import {
  andamentoDaTela,
  colunaPeloIndice,
  corpoDoDestino,
  erroDaLeitura,
  erroDoEnvio,
  leituraComColunas,
  leituraDaTela,
  listaDaTela,
  paginasDeProblemas,
} from '../../fonte/trazerTraducao';

// A tradução entre o servidor e a tela de "Trazer minha lista" (#2896): funções
// puras. O contrato do servidor está em
// spec/requests/api/v1/accounts/relacionamentos_trazer_spec.rb.
const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.xlsx',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 2, nome: 'Fone 2', destino: 'telefone', duvidosa: true },
    {
      indice: 6,
      nome: 'Situação',
      destino: 'informacao',
      campo: { nome: 'Situação', para_que_serve: '' },
    },
  ],
  perguntas: [{ id: 'clientes' }, { id: 'telefone', coluna: 'Fone 2' }],
  respostas: {},
  resumo: { total: 200, novas: 180, completadas: 15, comProblema: 5 },
  exemplos: [
    {
      nome: 'Marina Esteveira',
      telefone: '+55 11 94271-0003',
      email: 'marina.esteveira@exemplo.com.br',
      empresa: 'Casa Aurora',
      cliente: false,
    },
  ],
  problemas: [
    {
      linha: 14,
      tipo: 'telefone',
      nome: 'Tadeu Imbirussu',
      valor: '+55 11 9738-0014',
      estado: 'aberto',
    },
  ],
  problemas_total: 5,
  pagina: 1,
  por_pagina: 200,
};

describe('leituraDaTela', () => {
  it('entrega o que a tela lê e deixa de fora a paginação e a situação', () => {
    const leitura = leituraDaTela(PRONTA);
    expect(leitura).toEqual({
      id: 812,
      arquivo: 'Clientes 2025.xlsx',
      valores: 'inteiros',
      colunas: PRONTA.colunas,
      perguntas: PRONTA.perguntas,
      resumo: PRONTA.resumo,
      exemplos: PRONTA.exemplos,
      problemas: PRONTA.problemas,
    });
  });

  it('usa os problemas de todas as páginas, na ordem em que vieram', () => {
    const outraPagina = [
      {
        linha: 37,
        tipo: 'email',
        nome: 'Rita',
        valor: 'rita',
        estado: 'aberto',
      },
    ];
    const leitura = leituraDaTela(PRONTA, [
      ...PRONTA.problemas,
      ...outraPagina,
    ]);
    expect(leitura.problemas.map(problema => problema.linha)).toEqual([14, 37]);
  });

  it('devolve cópias: mexer na leitura não mexe na resposta', () => {
    const leitura = leituraDaTela(PRONTA);
    leitura.colunas[0].destino = 'nao_guardar';
    leitura.problemas[0].estado = 'deixado';
    leitura.resumo.total = 0;
    expect(PRONTA.colunas[0].destino).toBe('nome');
    expect(PRONTA.problemas[0].estado).toBe('aberto');
    expect(PRONTA.resumo.total).toBe(200);
  });

  it('o telefone dos exemplos chega do servidor sem formato e sai como a pessoa lê', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      exemplos: [
        { nome: 'Ana', telefone: '+5511987650001', email: '', empresa: '' },
        { nome: 'Bruno', telefone: '', email: 'bruno@exemplo.com.br' },
      ],
    });
    expect(leitura.exemplos.map(exemplo => exemplo.telefone)).toEqual([
      '+55 11 98765-0001',
      '',
    ]);
    expect(leitura.exemplos[1].email).toBe('bruno@exemplo.com.br');
  });

  it('o valor do problema fica como está na planilha', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      problemas: [{ ...PRONTA.problemas[0], valor: '(11) 2345-678' }],
    });
    expect(leitura.problemas[0].valor).toBe('(11) 2345-678');
  });

  it('planilha já apagada chega com os valores mascarados', () => {
    expect(leituraDaTela({ ...PRONTA, valores: 'mascarados' }).valores).toBe(
      'mascarados'
    );
  });
});

describe('paginasDeProblemas', () => {
  it.each([
    [5, 200, 1],
    [200, 200, 1],
    [201, 200, 2],
    [1000, 200, 5],
    [0, 200, 1],
  ])('%s problemas de %s em %s: %s página(s)', (total, porPagina, paginas) => {
    expect(
      paginasDeProblemas({ problemas_total: total, por_pagina: porPagina })
    ).toBe(paginas);
  });

  it('sem os números da paginação é uma página só', () => {
    expect(paginasDeProblemas({})).toBe(1);
    expect(paginasDeProblemas({ problemas_total: 9, por_pagina: 0 })).toBe(1);
  });
});

describe('erroDaLeitura', () => {
  it.each([
    ['vazia', 'PLANILHA_VAZIA'],
    ['sem_contato', 'PLANILHA_SEM_CONTATO'],
    ['leitura', 'LEITURA_FALHOU'],
    ['inventado', 'LEITURA_FALHOU'],
    [undefined, 'LEITURA_FALHOU'],
  ])('leitura que falhou por %s vira %s', (erro, nome) => {
    const falha = erroDaLeitura({ id: 812, situacao: 'falhou', erro });
    expect(falha).toBeInstanceOf(Error);
    expect(falha.name).toBe(nome);
  });
});

describe('erroDoEnvio', () => {
  const recusa = (status, error) =>
    Object.assign(new Error(`Request failed with status code ${status}`), {
      response: { status, data: { error } },
    });

  it.each([
    ['tipo', 'PLANILHA_TIPO'],
    ['arquivo_grande', 'PLANILHA_GRANDE'],
  ])('422 %s vira %s e guarda a causa', (codigo, nome) => {
    const causa = recusa(422, codigo);
    const falha = erroDoEnvio(causa);
    expect(falha.name).toBe(nome);
    expect(falha.cause).toBe(causa);
  });

  it('o que não tem nome sobe como veio', () => {
    const semArquivo = recusa(422, 'arquivo_obrigatorio');
    const caiu = recusa(500);
    expect(erroDoEnvio(semArquivo)).toBe(semArquivo);
    expect(erroDoEnvio(caiu)).toBe(caiu);
  });
});

describe('colunaPeloIndice', () => {
  it('acha a coluna da leitura pelo índice dela na planilha', () => {
    expect(colunaPeloIndice(leituraDaTela(PRONTA), 6).nome).toBe('Situação');
  });

  it('nome repetido ou vazio não confunde: quem identifica é o índice', () => {
    const leitura = leituraDaTela({
      ...PRONTA,
      colunas: [
        { indice: 0, nome: 'Telefone', destino: 'telefone' },
        { indice: 3, nome: 'Telefone', destino: 'informacao' },
        { indice: 4, nome: '', destino: 'informacao' },
      ],
    });
    expect(colunaPeloIndice(leitura, 3).destino).toBe('informacao');
    expect(colunaPeloIndice(leitura, 4).nome).toBe('');
  });

  it('coluna que não existe dá erro nomeado', () => {
    expect(() => colunaPeloIndice(leituraDaTela(PRONTA), 9)).toThrow(
      expect.objectContaining({ name: 'COLUNA_NAO_ENCONTRADA' })
    );
    expect(() => colunaPeloIndice(leituraDaTela(PRONTA), 'Nome')).toThrow(
      expect.objectContaining({ name: 'COLUNA_NAO_ENCONTRADA' })
    );
  });
});

describe('corpoDoDestino', () => {
  it('manda só o destino', () => {
    expect(corpoDoDestino('nao_guardar')).toEqual({ destino: 'nao_guardar' });
  });
});

describe('leituraComColunas', () => {
  it('troca só as colunas e não mexe na leitura de antes', () => {
    const antes = leituraDaTela(PRONTA);
    const colunas = [{ indice: 0, nome: 'Nome', destino: 'nao_guardar' }];
    const depois = leituraComColunas(antes, colunas);
    expect(depois.colunas).toEqual(colunas);
    expect(depois.problemas).toEqual(antes.problemas);
    expect(antes.colunas).toHaveLength(3);
  });
});

describe('listaDaTela', () => {
  const DO_SERVIDOR = {
    id: 812,
    arquivo: 'Clientes 2025.xlsx',
    quando: '2026-11-08T14:03:00Z',
    quem: 'Marina Pavanelli',
    total: 195,
    situacao: 'pronto',
    porcentagem: 100,
    pode_tentar: false,
  };

  it('traduz a data para milissegundos e `pode_tentar` para `podeTentar`', () => {
    expect(listaDaTela(DO_SERVIDOR)).toEqual({
      id: 812,
      arquivo: 'Clientes 2025.xlsx',
      quando: Date.UTC(2026, 10, 8, 14, 3),
      quem: 'Marina Pavanelli',
      total: 195,
      situacao: 'pronto',
      porcentagem: 100,
      podeTentar: false,
    });
  });

  it.each([
    ['pronto', 'pronto'],
    ['trazendo', 'trazendo'],
    ['desfeito', 'desfeito'],
    ['falhou', 'falhou'],
    ['desfazendo', 'desfeito'],
  ])('situação %s chega à tela como %s', (doServidor, daTela) => {
    expect(listaDaTela({ ...DO_SERVIDOR, situacao: doServidor }).situacao).toBe(
      daTela
    );
  });

  it('lista que falhou e pode continuar diz `podeTentar`', () => {
    const lista = listaDaTela({
      ...DO_SERVIDOR,
      situacao: 'falhou',
      pode_tentar: true,
    });
    expect(lista).toMatchObject({ situacao: 'falhou', podeTentar: true });
  });

  it('lista de quem já saiu da conta chega sem o nome de quem trouxe', () => {
    expect(listaDaTela({ ...DO_SERVIDOR, quem: null }).quem).toBe('');
  });

  it('sem `pode_tentar` não pode tentar', () => {
    expect(listaDaTela({ id: 9, situacao: 'falhou' }).podeTentar).toBe(false);
  });
});

describe('andamentoDaTela', () => {
  it('entrega porcentagem, situação e os números', () => {
    expect(
      andamentoDaTela({
        porcentagem: 42,
        situacao: 'trazendo',
        total: 195,
        novas: 70,
        completadas: 12,
      })
    ).toEqual({
      porcentagem: 42,
      situacao: 'trazendo',
      total: 195,
      novas: 70,
      completadas: 12,
    });
  });

  it('`desfazendo` chega como `desfeito`', () => {
    expect(andamentoDaTela({ situacao: 'desfazendo' }).situacao).toBe(
      'desfeito'
    );
  });
});
