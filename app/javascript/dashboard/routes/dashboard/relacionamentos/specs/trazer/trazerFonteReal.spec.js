import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { trazerFonte } from '../../fonte/trazerFonte';

// A fonte real de "Trazer minha lista" (#2896), Fatia 1: ler a planilha, trocar
// o destino de uma coluna, trazer, o andamento, o histórico e o tentar de novo.
// Fala com o servidor pelo cliente de API (aqui simulado) e devolve o mesmo
// formato da demonstração. O contrato do servidor está em
// spec/requests/api/v1/accounts/relacionamentos_trazer_spec.rb.
vi.mock('dashboard/api/relacionamentosTrazer', () => ({
  default: {
    enviar: vi.fn(),
    leitura: vi.fn(),
    trocarColuna: vi.fn(),
    listas: vi.fn(),
    andamento: vi.fn(),
    confirmar: vi.fn(),
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

const erroHttp = (status, error) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error } },
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

  it.each([
    'responder',
    'consertar',
    'deixarDeFora',
    'reabrir',
    'previaDoDesfazer',
    'desfazer',
  ])('%s fica para as próximas fatias: FONTE_REAL_PENDENTE', async metodo => {
    await expect(montar().fonte[metodo](812)).rejects.toMatchObject({
      name: 'FONTE_REAL_PENDENTE',
    });
    Object.values(TrazerAPI).forEach(daApi =>
      expect(daApi).not.toHaveBeenCalled()
    );
  });
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
      colunas: COLUNAS,
      perguntas: [],
      resumo: { total: 200, novas: 180, completadas: 15, comProblema: 1 },
      exemplos: [],
      problemas: [problema(14)],
    });
  });

  it('busca todas as páginas dos problemas', async () => {
    const { fonte } = montar();
    const pagina = (numero, linhas) =>
      pronta({
        problemas: linhas.map(problema),
        problemas_total: 5,
        pagina: numero,
        por_pagina: 2,
      });
    responde('enviar', LENDO);
    responde(
      'leitura',
      pagina(1, [14, 37]),
      pagina(2, [62, 143]),
      pagina(3, [171])
    );
    const leitura = await fonte.ler(PLANILHA);
    expect(TrazerAPI.leitura.mock.calls).toEqual([
      [812, 1],
      [812, 2],
      [812, 3],
    ]);
    expect(leitura.problemas.map(p => p.linha)).toEqual([14, 37, 62, 143, 171]);
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

  it('para de perguntar no teto de tempo e vira erro de leitura', async () => {
    const { fonte, relogio } = montar();
    responde('enviar', LENDO);
    TrazerAPI.leitura.mockResolvedValue({ data: LENDO });
    await expect(fonte.ler(PLANILHA)).rejects.toMatchObject({
      name: 'LEITURA_DEMOROU',
    });
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

  it('troca a coluna do índice pedido e encaixa as colunas que voltam', async () => {
    const { fonte, leitura } = await comLeitura();
    responde('trocarColuna', {
      situacao: 'pronta',
      colunas: COM_SITUACAO_FORA,
    });
    const nova = await fonte.trocarDestino(812, 6, 'nao_guardar');
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 6, {
      destino: 'nao_guardar',
    });
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(nova).toEqual({ ...leitura, colunas: COM_SITUACAO_FORA });
  });

  it('quando o servidor confere de novo, pergunta até sair de "lendo"', async () => {
    const { fonte, espera } = await comLeitura();
    const conferida = pronta({
      colunas: COM_SITUACAO_FORA,
      resumo: { total: 200, novas: 170, completadas: 15, comProblema: 15 },
    });
    responde('trocarColuna', LENDO);
    responde('leitura', LENDO, conferida);
    const nova = await fonte.trocarDestino(812, 1, 'nao_guardar');
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 1, {
      destino: 'nao_guardar',
    });
    // Igual ao `ler`: pergunta na hora e só espera entre uma pergunta e outra.
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(2);
    expect(espera.mock.calls).toEqual([[INTERVALO]]);
    expect(nova.resumo.novas).toBe(170);
    expect(nova.colunas).toEqual(COM_SITUACAO_FORA);
  });

  it('a troca seguinte parte da leitura que a anterior deixou', async () => {
    const { fonte } = await comLeitura();
    responde('trocarColuna', {
      situacao: 'pronta',
      colunas: COM_SITUACAO_FORA,
    });
    const primeira = await fonte.trocarDestino(812, 6, 'nao_guardar');
    primeira.problemas[0].estado = 'deixado';
    const semCel = COM_SITUACAO_FORA.map(coluna =>
      coluna.nome === 'Cel' ? { ...coluna, destino: 'nao_guardar' } : coluna
    );
    responde('trocarColuna', { situacao: 'pronta', colunas: semCel });
    const segunda = await fonte.trocarDestino(812, 1, 'nao_guardar');
    expect(segunda.colunas).toEqual(semCel);
    expect(segunda.problemas[0].estado).toBe('aberto');
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

  // Estes três destinos o servidor só conhece na Fatia 2.
  it.each(['cidade', 'telefone_da_empresa', 'cliente'])(
    'destino %s fica para a Fatia 2: FONTE_REAL_PENDENTE, sem falar com o servidor',
    async destino => {
      const { fonte } = await comLeitura();
      await expect(fonte.trocarDestino(812, 1, destino)).rejects.toMatchObject({
        name: 'FONTE_REAL_PENDENTE',
      });
      expect(TrazerAPI.trocarColuna).not.toHaveBeenCalled();
    }
  );

  it.each([
    'nome',
    'telefone',
    'email',
    'empresa',
    'informacao',
    'nao_guardar',
  ])('destino %s vai para o servidor', async destino => {
    const { fonte } = await comLeitura();
    responde('trocarColuna', { id: 812, situacao: 'pronta', colunas: COLUNAS });
    await fonte.trocarDestino(812, 6, destino);
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 6, { destino });
  });

  it('leitura que some no meio da conferência (404) vira erro nomeado, sem perguntar de novo', async () => {
    const { fonte, espera } = await comLeitura();
    responde('trocarColuna', LENDO);
    TrazerAPI.leitura.mockRejectedValue(erroHttp(404));
    await expect(
      fonte.trocarDestino(812, 1, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'LEITURA_NAO_ENCONTRADA' });
    expect(TrazerAPI.leitura).toHaveBeenCalledTimes(1);
    expect(espera).not.toHaveBeenCalled();
  });

  it('leitura que a fonte não leu dá erro nomeado e não escreve', async () => {
    const { fonte } = montar();
    await expect(
      fonte.trocarDestino(999, 1, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'LEITURA_NAO_ENCONTRADA' });
    expect(TrazerAPI.trocarColuna).not.toHaveBeenCalled();
  });

  it('recusa do servidor sobe como veio; sem acesso ganha nome', async () => {
    const { fonte } = await comLeitura();
    const recusado = erroHttp(422, 'sem_contato');
    TrazerAPI.trocarColuna.mockRejectedValueOnce(recusado);
    await expect(fonte.trocarDestino(812, 1, 'nao_guardar')).rejects.toBe(
      recusado
    );
    TrazerAPI.trocarColuna.mockRejectedValueOnce(erroHttp(403));
    await expect(
      fonte.trocarDestino(812, 1, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'SEM_ACESSO' });
  });
});

describe('trazer e tentar de novo', () => {
  it.each(['trazer', 'tentarDeNovo'])(
    '%s confirma a importação e devolve o id da lista',
    async metodo => {
      const { fonte } = montar();
      responde('confirmar', { id: 812, status: 'confirmed' });
      expect(await fonte[metodo](812)).toEqual({ trazidaId: 812 });
      expect(TrazerAPI.confirmar).toHaveBeenCalledWith(812);
    }
  );

  it.each(['trazer', 'tentarDeNovo'])(
    '%s recusado por falta de acesso vira SEM_ACESSO',
    async metodo => {
      const { fonte } = montar();
      TrazerAPI.confirmar.mockRejectedValue(erroHttp(401));
      await expect(fonte[metodo](812)).rejects.toMatchObject({
        name: 'SEM_ACESSO',
      });
    }
  );
});

describe('andamento', () => {
  it('devolve a porcentagem, a situação e os números da lista', async () => {
    const { fonte } = montar();
    const andamento = {
      porcentagem: 42,
      situacao: 'trazendo',
      total: 195,
      novas: 70,
      completadas: 12,
    };
    responde('andamento', andamento);
    expect(await fonte.andamento(812)).toEqual(andamento);
    expect(TrazerAPI.andamento).toHaveBeenCalledWith(812);
  });
});

describe('historico', () => {
  it('traduz cada lista: data em milissegundos, "desfazendo" como desfeito e o tentar', async () => {
    const { fonte } = montar();
    const lista = (id, situacao, podeTentar = false) => ({
      id,
      arquivo: `${id}.xlsx`,
      quando: '2026-11-08T14:03:00Z',
      quem: 'Marina Pavanelli',
      total: 195,
      situacao,
      porcentagem: 100,
      pode_tentar: podeTentar,
    });
    responde('listas', [
      lista(1, 'pronto'),
      lista(2, 'desfazendo'),
      lista(3, 'falhou', true),
    ]);
    const listas = await fonte.historico();
    expect(listas.map(l => [l.id, l.situacao, l.podeTentar])).toEqual([
      [1, 'pronto', false],
      [2, 'desfeito', false],
      [3, 'falhou', true],
    ]);
    expect(listas[0].quando).toBe(Date.UTC(2026, 10, 8, 14, 3));
  });

  it('sem acesso ganha nome; outro erro sobe como veio', async () => {
    const { fonte } = montar();
    TrazerAPI.listas.mockRejectedValueOnce(erroHttp(403));
    await expect(fonte.historico()).rejects.toMatchObject({
      name: 'SEM_ACESSO',
    });
    const caiu = erroHttp(500);
    TrazerAPI.listas.mockRejectedValueOnce(caiu);
    await expect(fonte.historico()).rejects.toBe(caiu);
  });
});
