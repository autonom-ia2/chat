import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { trazerFonte } from '../../fonte/trazerFonte';

// A fonte real de "Trazer minha lista" (#2896). Fatia 1: ler a planilha, trocar
// o destino de uma coluna, o andamento, o histórico e o tentar de novo. Fatia 2:
// responder às perguntas, consertar a linha, deixar de fora, voltar atrás,
// trazer pela leitura e os destinos que faltavam (com o campo da informação
// nova). Fatia 3: a prévia do desfazer e o desfazer de uma lista trazida. Fala
// com o servidor pelo cliente de API (aqui simulado) e devolve o mesmo formato
// da demonstração. O contrato do servidor está em
// spec/requests/api/v1/accounts/relacionamentos_trazer_spec.rb.
// Responder e trocar a coluna devolvem a leitura inteira ou, quando o servidor
// vai ler a planilha de novo, o marcador `{ situacao: 'lendo', id }`: quem
// espera é a tela, com `retomar` (retomada.spec.js e releitura.spec.js).
const MARCADOR = { situacao: 'lendo', id: 812 };
vi.mock('dashboard/api/relacionamentosTrazer', () => ({
  default: {
    enviar: vi.fn(),
    leitura: vi.fn(),
    responder: vi.fn(),
    consertar: vi.fn(),
    deixarDeFora: vi.fn(),
    reabrir: vi.fn(),
    trocarColuna: vi.fn(),
    trazer: vi.fn(),
    listas: vi.fn(),
    andamento: vi.fn(),
    confirmar: vi.fn(),
    previaDoDesfazer: vi.fn(),
    desfazer: vi.fn(),
  },
}));

const INTERVALO = 1000;
const TETO = 5000;
const PLANILHA = { name: 'Clientes 2025.xlsx' };
const LENDO = { id: 812, situacao: 'lendo' };

const COLUNAS = [
  { indice: 0, nome: 'Nome', destino: 'nome' },
  { indice: 1, nome: 'Cel', destino: 'telefone' },
  { indice: 6, nome: 'Situação', destino: 'informacao' },
];
const problema = linha => ({
  linha,
  tipo: 'telefone',
  nome: `Pessoa ${linha}`,
  valor: '+55 11 9738-0014',
  estado: 'aberto',
});
const pronta = (extra = {}) => ({
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.xlsx',
  valores: 'inteiros',
  colunas: COLUNAS,
  perguntas: [],
  respostas: {},
  resumo: { total: 200, novas: 180, completadas: 15, comProblema: 1 },
  exemplos: [],
  problemas: [problema(14)],
  problemas_total: 1,
  pagina: 1,
  por_pagina: 200,
  ...extra,
});

const erroHttp = (status, error, extra = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error, ...extra } },
  });
const responde = (metodo, ...respostas) =>
  respostas.reduce(
    (mock, data) => mock.mockResolvedValueOnce({ data }),
    TrazerAPI[metodo]
  );

// A espera é de mentira: em vez de dormir, só anda o relógio.
const montar = () => {
  const relogio = { agora: 0 };
  const espera = vi.fn(async ms => {
    relogio.agora += ms;
  });
  const fonte = trazerFonte({
    demo: null,
    espera,
    intervaloDaConsulta: INTERVALO,
    tetoDaConsulta: TETO,
    agora: () => relogio.agora,
  });
  return { fonte, espera, relogio };
};

// Uma fonte que já leu a planilha (a leitura 812 está guardada nela).
const comLeitura = async (resposta = pronta()) => {
  const montada = montar();
  responde('enviar', LENDO);
  responde('leitura', resposta);
  const leitura = await montada.fonte.ler(PLANILHA);
  vi.clearAllMocks();
  return { ...montada, leitura };
};

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real', () => {
  it('não é a demonstração', () => {
    expect(montar().fonte.usaDemo).toBe(false);
  });

  // Fatia 3: a fonte diz que tem o desfazer, e a tela o mostra.
  it('diz que tem o desfazer', () => {
    expect(montar().fonte.temDesfazer).toBe(true);
  });

  it.each([
    ['responder', [{ clientes: 'sim_todas' }]],
    ['consertar', [14, 'x']],
    ['deixarDeFora', [14]],
    ['reabrir', [14]],
  ])(
    '%s numa leitura que a fonte não leu dá erro nomeado e não escreve',
    async (metodo, argumentos) => {
      await expect(
        montar().fonte[metodo](999, ...argumentos)
      ).rejects.toMatchObject({ name: 'LEITURA_NAO_ENCONTRADA' });
      Object.values(TrazerAPI).forEach(daApi =>
        expect(daApi).not.toHaveBeenCalled()
      );
    }
  );
});

describe('ler', () => {
  it('envia a planilha e pergunta de novo até sair de "lendo"', async () => {
    const { fonte, espera } = montar();
    responde('enviar', LENDO);
    responde('leitura', LENDO, LENDO, pronta());
    const leitura = await fonte.ler(PLANILHA);
    expect(TrazerAPI.enviar).toHaveBeenCalledWith(PLANILHA);
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(3);
    expect(TrazerAPI.leitura).toHaveBeenCalledWith(812, 1);
    expect(espera.mock.calls).toEqual([[INTERVALO], [INTERVALO]]);
    expect(leitura).toEqual({
      id: 812,
      arquivo: 'Clientes 2025.xlsx',
      valores: 'inteiros',
      temEmpresa: true,
      colunas: COLUNAS,
      perguntas: [],
      respostas: {},
      resumo: { total: 200, novas: 180, completadas: 15, comProblema: 1 },
      exemplos: [],
      problemas: [problema(14)],
      problemasTotal: 1,
    });
  });

  // As outras páginas vêm a pedido ("Mostrar mais": paginasDeProblemas.spec.js).
  it('traz só a primeira página dos problemas e diz quantos há ao todo', async () => {
    const { fonte } = montar();
    responde('enviar', LENDO);
    responde(
      'leitura',
      pronta({
        problemas: [14, 37].map(problema),
        problemas_total: 5,
        por_pagina: 2,
      })
    );
    const leitura = await fonte.ler(PLANILHA);
    expect(TrazerAPI.leitura.mock.calls).toEqual([[812, 1]]);
    expect(leitura.problemas.map(p => p.linha)).toEqual([14, 37]);
    expect(leitura.problemasTotal).toBe(5);
  });

  it.each([
    ['vazia', 'PLANILHA_VAZIA'],
    ['sem_contato', 'PLANILHA_SEM_CONTATO'],
    ['leitura', 'LEITURA_FALHOU'],
  ])('leitura que falhou por %s vira o erro %s', async (erro, nome) => {
    const { fonte } = montar();
    responde('enviar', LENDO);
    responde('leitura', LENDO, { id: 812, situacao: 'falhou', erro });
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({ name: nome });
  });

  it.each([
    ['tipo', 'PLANILHA_TIPO'],
    ['arquivo_grande', 'PLANILHA_GRANDE'],
  ])('envio recusado por %s vira o erro %s', async (codigo, nome) => {
    const { fonte } = montar();
    TrazerAPI.enviar.mockRejectedValue(erroHttp(422, codigo));
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({ name: nome });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });

  // A planilha continua no servidor: o erro leva o id, para a tela perguntar
  // por ela depois sem enviar o arquivo de novo.
  it('para de perguntar no teto de tempo e diz que a leitura ficou pendente', async () => {
    const { fonte, relogio } = montar();
    responde('enviar', LENDO);
    TrazerAPI.leitura.mockResolvedValue({ data: LENDO });
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({
      name: 'LEITURA_PENDENTE',
      leituraId: 812,
    });
    expect(TrazerAPI.enviar).toHaveBeenCalledTimes(1);
    expect(relogio.agora).toBe(TETO);
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(TETO / INTERVALO + 1);
  });

  it('para de perguntar quando a tela sai', async () => {
    const { fonte, espera } = montar();
    responde('enviar', LENDO);
    TrazerAPI.leitura.mockResolvedValue({ data: LENDO });
    espera.mockImplementationOnce(async () => fonte.encerrar());
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({
      name: 'LEITURA_INTERROMPIDA',
    });
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(1);
  });

  it.each([401, 403])(
    '%s no envio ou na leitura vira SEM_ACESSO',
    async status => {
      const noEnvio = montar().fonte;
      TrazerAPI.enviar.mockRejectedValueOnce(erroHttp(status));
      await expect(noEnvio.ler(PLANILHA)).rejects.toMatchObject({
        name: 'SEM_ACESSO',
      });

      const naLeitura = montar().fonte;
      responde('enviar', LENDO);
      TrazerAPI.leitura.mockRejectedValueOnce(erroHttp(status));
      await expect(naLeitura.ler(PLANILHA)).rejects.toMatchObject({
        name: 'SEM_ACESSO',
      });
    }
  );

  it('outro erro do servidor sobe como veio', async () => {
    const { fonte } = montar();
    const caiu = erroHttp(500);
    TrazerAPI.enviar.mockRejectedValue(caiu);
    await expect(fonte.ler(PLANILHA)).rejects.toBe(caiu);
  });

  it('leitura que o servidor não acha (404) vira erro nomeado, sem perguntar de novo', async () => {
    const { fonte, espera } = montar();
    responde('enviar', LENDO);
    TrazerAPI.leitura.mockRejectedValue(erroHttp(404));
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({
      name: 'LEITURA_NAO_ENCONTRADA',
    });
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(1);
    expect(espera).not.toHaveBeenCalled();
  });

  it('o telefone dos exemplos sai formatado', async () => {
    const { fonte } = montar();
    responde('enviar', LENDO);
    responde(
      'leitura',
      pronta({ exemplos: [{ nome: 'Ana', telefone: '+5511987650001' }] })
    );
    const leitura = await fonte.ler(PLANILHA);
    expect(leitura.exemplos[0].telefone).toBe('+55 11 98765-0001');
  });
});

describe('trocarDestino', () => {
  const COM_SITUACAO_FORA = COLUNAS.map(coluna =>
    coluna.nome === 'Situação' ? { ...coluna, destino: 'nao_guardar' } : coluna
  );

  it('troca a coluna do índice pedido e usa a leitura inteira que volta', async () => {
    const { fonte, leitura } = await comLeitura();
    responde('trocarColuna', pronta({ colunas: COM_SITUACAO_FORA }));
    const nova = await fonte.trocarDestino(812, 6, 'nao_guardar');
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 6, {
      destino: 'nao_guardar',
    });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(nova).toEqual({ ...leitura, colunas: COM_SITUACAO_FORA });
  });

  it('quando o servidor confere de novo, devolve o marcador sem esperar; quem retoma pergunta até sair de "lendo"', async () => {
    const { fonte, espera } = await comLeitura();
    const conferida = pronta({
      colunas: COM_SITUACAO_FORA,
      resumo: { total: 200, novas: 170, completadas: 15, comProblema: 15 },
    });
    responde('trocarColuna', LENDO);
    expect(await fonte.trocarDestino(812, 1, 'nao_guardar')).toEqual(MARCADOR);
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 1, {
      destino: 'nao_guardar',
    });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    responde('leitura', LENDO, conferida);
    const nova = await fonte.retomar(812);
    // Igual ao `ler`: pergunta na hora e só espera entre uma pergunta e outra.
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(2);
    expect(espera.mock.calls).toEqual([[INTERVALO]]);
    expect(nova.resumo.novas).toBe(170);
    expect(nova.colunas).toEqual(COM_SITUACAO_FORA);
  });

  it('a leitura devolvida é cópia: mexer nela não muda a que a escrita seguinte usa', async () => {
    const { fonte } = await comLeitura();
    responde('trocarColuna', pronta({ colunas: COM_SITUACAO_FORA }));
    const primeira = await fonte.trocarDestino(812, 6, 'nao_guardar');
    primeira.problemas[0].nome = 'outro nome';
    primeira.colunas[2].destino = 'cidade';
    responde('deixarDeFora', {
      problema: { ...problema(14), estado: 'deixado' },
      entram: 195,
    });
    const segunda = await fonte.deixarDeFora(812, 14);
    expect(segunda.colunas).toEqual(COM_SITUACAO_FORA);
    expect(segunda.problemas).toEqual([{ ...problema(14), estado: 'deixado' }]);
  });

  it('nome de coluna repetido: a troca vai para o índice pedido', async () => {
    const repetidas = [
      { indice: 0, nome: 'Telefone', destino: 'telefone' },
      { indice: 3, nome: 'Telefone', destino: 'informacao' },
    ];
    const { fonte } = await comLeitura(pronta({ colunas: repetidas }));
    responde('trocarColuna', {
      id: 812,
      situacao: 'pronta',
      colunas: repetidas,
    });
    await fonte.trocarDestino(812, 3, 'nao_guardar');
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 3, {
      destino: 'nao_guardar',
    });
  });

  it('coluna que a leitura não tem dá erro nomeado e não escreve', async () => {
    const { fonte } = await comLeitura();
    await expect(
      fonte.trocarDestino(812, 9, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'COLUNA_NAO_ENCONTRADA' });
    await expect(
      fonte.trocarDestino(812, 'Cel', 'nao_guardar')
    ).rejects.toMatchObject({ name: 'COLUNA_NAO_ENCONTRADA' });
    expect(TrazerAPI.trocarColuna).not.toHaveBeenCalled();
  });

  // Cidade, telefone da empresa e "se é cliente" entraram na Fatia 2.
  it.each([
    'nome',
    'telefone',
    'email',
    'empresa',
    'cidade',
    'telefone_da_empresa',
    'cliente',
    'informacao',
    'nao_guardar',
  ])('destino %s vai para o servidor', async destino => {
    const { fonte } = await comLeitura();
    responde('trocarColuna', { id: 812, situacao: 'pronta', colunas: COLUNAS });
    await fonte.trocarDestino(812, 6, destino);
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 6, { destino });
  });

  it('informação nova leva o nome do campo e o para que serve, e a coluna volta com eles', async () => {
    const { fonte } = await comLeitura();
    const campo = {
      nome: 'Vencimento',
      para_que_serve: 'mês em que o seguro vence',
    };
    const comCampo = COLUNAS.map(coluna =>
      coluna.indice === 6 ? { ...coluna, campo } : coluna
    );
    responde('trocarColuna', { situacao: 'pronta', colunas: comCampo });
    const nova = await fonte.trocarDestino(812, 6, 'informacao', campo);
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 6, {
      destino: 'informacao',
      ...campo,
    });
    expect(nova.colunas[2].campo).toEqual(campo);
  });

  it('tirar a última coluna de contato (422 `sem_contato`) ganha nome', async () => {
    const { fonte } = await comLeitura();
    TrazerAPI.trocarColuna.mockRejectedValueOnce(erroHttp(422, 'sem_contato'));
    await expect(
      fonte.trocarDestino(812, 1, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'TROCA_SEM_CONTATO' });
  });

  it('leitura que a fonte não leu dá erro nomeado e não escreve', async () => {
    const { fonte } = montar();
    await expect(
      fonte.trocarDestino(999, 1, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'LEITURA_NAO_ENCONTRADA' });
    expect(TrazerAPI.trocarColuna).not.toHaveBeenCalled();
  });

  it('o que o servidor não nomeia sobe como veio; sem acesso ganha nome', async () => {
    const { fonte } = await comLeitura();
    const caiu = erroHttp(500);
    TrazerAPI.trocarColuna.mockRejectedValueOnce(caiu);
    await expect(fonte.trocarDestino(812, 1, 'nao_guardar')).rejects.toBe(caiu);
    TrazerAPI.trocarColuna.mockRejectedValueOnce(erroHttp(401));
    await expect(
      fonte.trocarDestino(812, 1, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'SEM_ACESSO' });
  });
});

describe('responder', () => {
  const PERGUNTAS = [{ id: 'clientes' }, { id: 'telefone', coluna: 'Cel' }];
  const comPerguntas = (extra = {}) =>
    pronta({ perguntas: PERGUNTAS, ...extra });
  const COM_CLIENTE = COLUNAS.map(coluna =>
    coluna.indice === 6 ? { ...coluna, destino: 'cliente' } : coluna
  );

  it('manda as respostas com os nomes do servidor e usa a leitura que volta', async () => {
    const { fonte } = await comLeitura(comPerguntas());
    responde(
      'responder',
      comPerguntas({
        colunas: COM_CLIENTE,
        respostas: {
          clientes: 'algumas',
          coluna_cliente: 6,
          telefone: 'da_pessoa',
        },
      })
    );
    const nova = await fonte.responder(812, {
      clientes: 'algumas',
      colunaCliente: 6,
      telefone: 'da_pessoa',
    });
    expect(TrazerAPI.responder).toHaveBeenCalledWith(812, {
      clientes: 'algumas',
      coluna_cliente: 6,
      telefone: 'da_pessoa',
    });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(nova.colunas).toEqual(COM_CLIENTE);
    expect(nova.respostas).toEqual({
      clientes: 'algumas',
      colunaCliente: 6,
      telefone: 'da_pessoa',
    });
    expect(nova.perguntas).toEqual(PERGUNTAS);
  });

  it('quando o servidor confere de novo, devolve o marcador sem esperar; quem retoma pergunta até sair de "lendo"', async () => {
    const { fonte, espera } = await comLeitura(comPerguntas());
    responde('responder', LENDO);
    expect(
      await fonte.responder(812, {
        clientes: 'ainda_nao',
        telefone: 'nao_usar',
      })
    ).toEqual(MARCADOR);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    responde(
      'leitura',
      LENDO,
      comPerguntas({
        respostas: { clientes: 'ainda_nao', telefone: 'nao_usar' },
        resumo: { total: 200, novas: 170, completadas: 15, comProblema: 15 },
      })
    );
    const nova = await fonte.retomar(812);
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(2);
    expect(espera.mock.calls).toEqual([[INTERVALO]]);
    expect(nova.resumo.novas).toBe(170);
    expect(nova.respostas).toEqual({
      clientes: 'ainda_nao',
      telefone: 'nao_usar',
    });
  });

  // Quem volta do Conferir às perguntas e responde de novo não perde o que já
  // consertou: o servidor devolve a leitura inteira, com o estado de cada linha.
  it('não perde o conserto já feito quando o servidor devolve os problemas', async () => {
    const { fonte } = await comLeitura(comPerguntas());
    const guardado = {
      ...problema(14),
      estado: 'guardado',
      corrigido: '+55 11 97380-0014',
    };
    responde('consertar', { problema: guardado });
    await fonte.consertar(812, 14, '+5511973800014');
    responde(
      'responder',
      comPerguntas({
        respostas: { clientes: 'sim_todas' },
        problemas: [{ ...problema(14), ...guardado }],
      })
    );
    const nova = await fonte.responder(812, { clientes: 'sim_todas' });
    expect(nova.problemas).toEqual([{ ...problema(14), ...guardado }]);
  });

  it('a escrita seguinte parte da leitura que as respostas devolveram', async () => {
    const { fonte } = await comLeitura(comPerguntas());
    responde('deixarDeFora', {
      problema: { ...problema(14), estado: 'deixado' },
    });
    await fonte.deixarDeFora(812, 14);
    responde(
      'responder',
      comPerguntas({
        colunas: COM_CLIENTE,
        respostas: { clientes: 'sim_todas' },
        problemas: [{ ...problema(14), estado: 'deixado' }],
      })
    );
    const nova = await fonte.responder(812, { clientes: 'sim_todas' });
    expect(nova.problemas).toEqual([{ ...problema(14), estado: 'deixado' }]);
    expect(nova.colunas).toEqual(COM_CLIENTE);
    expect(nova.resumo.total).toBe(200);
    // E a escrita seguinte parte dessa leitura.
    responde('reabrir', { problema: problema(14) });
    const reaberta = await fonte.reabrir(812, 14);
    expect(reaberta.problemas).toEqual([problema(14)]);
    expect(reaberta.colunas).toEqual(COM_CLIENTE);
  });

  it('a resposta traz a primeira página dos problemas; as outras vêm a pedido', async () => {
    const { fonte } = await comLeitura(comPerguntas());
    const pagina = (numero, linhas) =>
      comPerguntas({
        problemas: linhas.map(problema),
        problemas_total: 3,
        pagina: numero,
        por_pagina: 2,
      });
    responde('responder', pagina(1, [14, 37]));
    const nova = await fonte.responder(812, { clientes: 'sim_todas' });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(nova.problemas.map(p => p.linha)).toEqual([14, 37]);
    expect(nova.problemasTotal).toBe(3);
    responde('leitura', pagina(2, [62]));
    const comMais = await fonte.maisProblemas(812);
    expect(TrazerAPI.leitura.mock.calls).toEqual([[812, 2]]);
    expect(comMais.problemas.map(p => p.linha)).toEqual([14, 37, 62]);
  });

  it('"não usar" no único telefone da planilha (422 `sem_contato`) ganha nome', async () => {
    const { fonte } = await comLeitura(comPerguntas());
    TrazerAPI.responder.mockRejectedValueOnce(erroHttp(422, 'sem_contato'));
    await expect(
      fonte.responder(812, { telefone: 'nao_usar' })
    ).rejects.toMatchObject({ name: 'TROCA_SEM_CONTATO' });
  });

  it('sem acesso ganha nome; outro erro sobe como veio', async () => {
    const { fonte } = await comLeitura(comPerguntas());
    TrazerAPI.responder.mockRejectedValueOnce(erroHttp(401));
    await expect(
      fonte.responder(812, { clientes: 'sim_todas' })
    ).rejects.toMatchObject({ name: 'SEM_ACESSO' });
    const caiu = erroHttp(500);
    TrazerAPI.responder.mockRejectedValueOnce(caiu);
    await expect(fonte.responder(812, { clientes: 'sim_todas' })).rejects.toBe(
      caiu
    );
  });
});

describe('consertar, deixar de fora e voltar atrás', () => {
  const REPETIDA = {
    linha: 143,
    tipo: 'duplicada',
    nome: 'Paulo Hortêncio',
    valor: 'Paulo Hortêncio',
    outraLinha: 88,
    estado: 'aberto',
  };
  const comDois = () =>
    comLeitura(pronta({ problemas: [problema(14), REPETIDA] }));

  // O servidor devolve a linha inteira, como a tela a mostra agora.
  it('consertar manda o valor e encaixa a linha que volta, sem reler a planilha', async () => {
    const { fonte } = await comDois();
    responde('consertar', {
      problema: {
        ...problema(14),
        estado: 'guardado',
        corrigido: '+55 11 97380-0014',
      },
    });
    const nova = await fonte.consertar(812, 14, '+5511973800014');
    expect(TrazerAPI.consertar).toHaveBeenCalledWith(812, 14, {
      valor: '+5511973800014',
    });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(nova.problemas).toEqual([
      { ...problema(14), estado: 'guardado', corrigido: '+55 11 97380-0014' },
      REPETIDA,
    ]);
  });

  it('linha repetida: manda com qual das duas linhas fica', async () => {
    const { fonte } = await comDois();
    // Ficar com a outra linha deixa esta de fora, e a leitura é pedida de novo.
    responde('consertar', { problema: { ...REPETIDA, estado: 'deixado' } });
    responde(
      'leitura',
      pronta({
        problemas: [problema(14), { ...REPETIDA, estado: 'deixado' }],
        problemas_total: 2,
      })
    );
    const nova = await fonte.consertar(812, 143, 88);
    expect(TrazerAPI.consertar).toHaveBeenCalledWith(812, 143, {
      ficar_com: 88,
    });
    expect(nova.problemas[1]).toEqual({ ...REPETIDA, estado: 'deixado' });
  });

  it('o servidor recusa o valor (422 `valor_invalido`): erro nomeado com o motivo, e nada muda', async () => {
    const { fonte } = await comDois();
    TrazerAPI.consertar.mockRejectedValueOnce(
      erroHttp(422, 'valor_invalido', {
        motivo: 'invalid_brazilian_mobile_number',
      })
    );
    await expect(fonte.consertar(812, 14, '+551199')).rejects.toMatchObject({
      name: 'VALOR_INVALIDO',
      motivo: 'invalid_brazilian_mobile_number',
    });
    // A escrita seguinte parte da leitura como estava: a linha 14 ainda aberta.
    responde('deixarDeFora', { problema: { ...REPETIDA, estado: 'deixado' } });
    const nova = await fonte.deixarDeFora(812, 143);
    expect(nova.problemas[0]).toEqual(problema(14));
  });

  it('deixar de fora e voltar atrás escrevem na linha e encaixam o que volta', async () => {
    const { fonte } = await comDois();
    responde('deixarDeFora', {
      problema: { ...problema(14), estado: 'deixado' },
    });
    const deixada = await fonte.deixarDeFora(812, 14);
    expect(TrazerAPI.deixarDeFora).toHaveBeenCalledWith(812, 14);
    expect(deixada.problemas[0].estado).toBe('deixado');
    responde('reabrir', { problema: { ...problema(14), estado: 'aberto' } });
    const reaberta = await fonte.reabrir(812, 14);
    expect(TrazerAPI.reabrir).toHaveBeenCalledWith(812, 14);
    expect(reaberta.problemas).toEqual([problema(14), REPETIDA]);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });

  it('voltar atrás numa linha consertada tira o valor corrigido', async () => {
    const { fonte } = await comDois();
    responde('consertar', {
      problema: {
        ...problema(14),
        estado: 'guardado',
        corrigido: '+55 11 97380-0014',
      },
    });
    await fonte.consertar(812, 14, '+5511973800014');
    responde('reabrir', { problema: problema(14) });
    const reaberta = await fonte.reabrir(812, 14);
    expect(reaberta.problemas[0]).toEqual(problema(14));
  });

  it.each([
    ['consertar', ['x']],
    ['deixarDeFora', []],
    ['reabrir', []],
  ])(
    '%s numa linha que a leitura não tem dá erro nomeado e não escreve',
    async (metodo, argumentos) => {
      const { fonte } = await comDois();
      await expect(
        fonte[metodo](812, 999, ...argumentos)
      ).rejects.toMatchObject({ name: 'LINHA_NAO_ENCONTRADA' });
      expect(TrazerAPI[metodo]).not.toHaveBeenCalled();
    }
  );

  it.each(['consertar', 'deixarDeFora', 'reabrir'])(
    '%s: sem acesso ganha nome; outro erro sobe como veio',
    async metodo => {
      const { fonte } = await comDois();
      TrazerAPI[metodo].mockRejectedValueOnce(erroHttp(401));
      await expect(fonte[metodo](812, 14, 'x')).rejects.toMatchObject({
        name: 'SEM_ACESSO',
      });
      const caiu = erroHttp(500);
      TrazerAPI[metodo].mockRejectedValueOnce(caiu);
      await expect(fonte[metodo](812, 14, 'x')).rejects.toBe(caiu);
    }
  );
});

describe('trazer e tentar de novo', () => {
  it('trazer fecha a conferência pela rota da leitura, e a lista é a que o servidor diz (não a leitura que a tela mandou)', async () => {
    const { fonte } = montar();
    responde('trazer', { trazidaId: 813 });
    expect(await fonte.trazer(812)).toEqual({ trazidaId: 813 });
    expect(TrazerAPI.trazer).toHaveBeenCalledWith(812);
    expect(TrazerAPI.confirmar).not.toHaveBeenCalled();
  });

  it('tentar de novo continua pelo confirmar da importação, que já existia', async () => {
    const { fonte } = montar();
    responde('confirmar', { id: 812, status: 'queued' });
    expect(await fonte.tentarDeNovo(812)).toEqual({ trazidaId: 812 });
    expect(TrazerAPI.confirmar).toHaveBeenCalledWith(812);
    expect(TrazerAPI.trazer).not.toHaveBeenCalled();
  });

  it('tentar de novo enquanto a conta desfaz uma lista (422 `desfazer_em_curso`) ganha nome', async () => {
    const { fonte } = montar();
    TrazerAPI.confirmar.mockRejectedValue(erroHttp(422, 'desfazer_em_curso'));
    await expect(fonte.tentarDeNovo(812)).rejects.toMatchObject({
      name: 'DESFAZER_EM_CURSO',
    });
  });

  it.each([
    ['trazer', 'trazer'],
    ['tentarDeNovo', 'confirmar'],
  ])(
    '%s recusado por falta de acesso vira SEM_ACESSO',
    async (metodo, daApi) => {
      const { fonte } = montar();
      TrazerAPI[daApi].mockRejectedValue(erroHttp(401));
      await expect(fonte[metodo](812)).rejects.toMatchObject({
        name: 'SEM_ACESSO',
      });
    }
  );
});

describe('andamento', () => {
  it('entrega só o que a tela usa, e a lista que está sendo desfeita chega como `desfazendo`', async () => {
    const { fonte } = montar();
    responde('andamento', {
      id: 812,
      porcentagem: 42,
      situacao: 'desfazendo',
      total: 195,
      novas: 70,
      completadas: 12,
      pode_tentar: false,
    });
    expect(await fonte.andamento(812)).toEqual({
      porcentagem: 42,
      situacao: 'desfazendo',
      total: 195,
      novas: 70,
      completadas: 12,
    });
    expect(TrazerAPI.andamento).toHaveBeenCalledWith(812);
  });
});

describe('historico', () => {
  it('traduz cada lista: data em milissegundos, a situação como o servidor diz, o tentar e o desfazer', async () => {
    const { fonte } = montar();
    const lista = (id, situacao, podeTentar, podeDesfazer) => ({
      id,
      arquivo: `${id}.xlsx`,
      quando: '2026-11-08T14:03:00Z',
      quem: 'Marina Pavanelli',
      total: 195,
      situacao,
      porcentagem: 100,
      pode_tentar: podeTentar,
      pode_desfazer: podeDesfazer,
    });
    responde('listas', [
      lista(1, 'pronto', false, true),
      lista(2, 'desfazendo', false, false),
      lista(3, 'falhou', true, true),
    ]);
    const listas = await fonte.historico();
    expect(
      listas.map(l => [l.id, l.situacao, l.podeTentar, l.podeDesfazer])
    ).toEqual([
      [1, 'pronto', false, true],
      [2, 'desfazendo', false, false],
      [3, 'falhou', true, true],
    ]);
    expect(listas[0].quando).toBe(Date.UTC(2026, 10, 8, 14, 3));
  });

  it('sem acesso ganha nome; outro erro sobe como veio', async () => {
    const { fonte } = montar();
    TrazerAPI.listas.mockRejectedValueOnce(erroHttp(401));
    await expect(fonte.historico()).rejects.toMatchObject({
      name: 'SEM_ACESSO',
    });
    const caiu = erroHttp(500);
    TrazerAPI.listas.mockRejectedValueOnce(caiu);
    await expect(fonte.historico()).rejects.toBe(caiu);
  });
});

// Fatia 3 — o desfazer de uma lista trazida. O servidor só marca a lista como
// `desfazendo` e responde na hora (202); quem acompanha até `desfeito` é a tela,
// pelo histórico.
describe('desfazer', () => {
  it('a prévia pergunta ao servidor e entrega só os três números', async () => {
    const { fonte } = montar();
    responde('previaDoDesfazer', {
      id: 812,
      tira: 162,
      ficam: 18,
      devolve: 15,
    });
    expect(await fonte.previaDoDesfazer(812)).toEqual({
      tira: 162,
      ficam: 18,
      devolve: 15,
    });
    expect(TrazerAPI.previaDoDesfazer).toHaveBeenCalledWith(812);
    expect(TrazerAPI.desfazer).not.toHaveBeenCalled();
  });

  it.each(['desfazendo', 'desfeito'])(
    'desfazer pede ao servidor e devolve a lista com a situação de agora (%s)',
    async situacao => {
      const { fonte } = montar();
      responde('desfazer', { id: 812, situacao });
      expect(await fonte.desfazer(812)).toEqual({ id: 812, situacao });
      expect(TrazerAPI.desfazer).toHaveBeenCalledWith(812);
    }
  );

  it.each(['previaDoDesfazer', 'desfazer'])(
    '%s: a lista que ainda não foi trazida até o fim (422) vira NAO_PODE_DESFAZER',
    async metodo => {
      const { fonte } = montar();
      const recusa = erroHttp(422, 'nao_pode_desfazer');
      TrazerAPI[metodo].mockRejectedValueOnce(recusa);
      const falha = await fonte[metodo](812).catch(erro => erro);
      expect(falha).toBeInstanceOf(Error);
      expect(falha.name).toBe('NAO_PODE_DESFAZER');
      expect(falha.cause).toBe(recusa);
    }
  );

  it.each(['previaDoDesfazer', 'desfazer'])(
    '%s: sem acesso ganha nome; outro erro sobe como veio',
    async metodo => {
      const { fonte } = montar();
      TrazerAPI[metodo].mockRejectedValueOnce(erroHttp(401));
      await expect(fonte[metodo](812)).rejects.toMatchObject({
        name: 'SEM_ACESSO',
      });
      const caiu = erroHttp(500);
      TrazerAPI[metodo].mockRejectedValueOnce(caiu);
      await expect(fonte[metodo](812)).rejects.toBe(caiu);
    }
  );
});
