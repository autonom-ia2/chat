import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { trazerFonte } from '../../fonte/trazerFonte';
import { resumoDaTela } from '../../trazer/contagem';
// #2896 — a fonte real (fonte/trazerFonte.js) em cada escrita, com o cliente
// de API simulado e os corpos de spec/requests/api/v1/accounts/relacionamentos_trazer_linhas_spec.rb,
// relacionamentos_trazer_respostas_spec.rb e relacionamentos_trazer_trazer_spec.rb:
// ficar com uma linha repetida, o conserto que deixa outro problema, as recusas
// que ganham nome e a leitura inteira que volta das respostas.
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
  },
}));

vi.setConfig({ testTimeout: 30000 });

afterEach(() => {
  vi.resetAllMocks();
});

const erroHttp = (status, error, extra = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error, ...extra } },
  });

// As linhas como o servidor as devolve (a planilha `com_problemas` do spec).
const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
  estado: 'aberto',
};

const SEM_NOME = {
  linha: 6,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11987650005',
  estado: 'aberto',
};

const SEM_CONTATO = {
  linha: 7,
  tipo: 'sem_contato',
  nome: 'Elisa Esteveira',
  valor: '',
  estado: 'aberto',
};

const REPETIDA = {
  linha: 8,
  tipo: 'duplicada',
  nome: 'Ana Outra',
  valor: '11987650001',
  estado: 'aberto',
  outraLinha: 2,
  duplicadas: [
    { linha: 2, telefone: '11987650001', email: 'ana@exemplo.com.br' },
    { linha: 8, telefone: '11987650001', email: '' },
  ],
};

const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'telefone', duvidosa: true },
    {
      indice: 3,
      nome: 'Plano',
      destino: 'informacao',
      campo: { nome: 'Plano', para_que_serve: '' },
    },
  ],
  perguntas: [
    { id: 'clientes' },
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: {},
  resumo: {
    total: 7,
    novas: 2,
    completadas: 0,
    comProblema: 4,
    juntadas: 0,
    entram: 2,
  },
  exemplos: [],
  problemas: [TELEFONE, SEM_NOME, SEM_CONTATO, REPETIDA],
  problemas_total: 4,
  pagina: 1,
  por_pagina: 200,
};

const pronta = (extra = {}) => ({ ...PRONTA, ...extra });

// O telefone da linha 4 valeu, mas a linha também não tinha nome: o servidor
// guarda o telefone e devolve o problema que sobrou.
const SOBROU_O_NOME = {
  linha: 4,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '+5511987650004',
  estado: 'aberto',
};

const daLinha = (leitura, linha) =>
  leitura.problemas.find(problema => problema.linha === linha);

describe('fonte real: o que o servidor responde a cada escrita', () => {
  const responde = (metodo, data) =>
    TrazerAPI[metodo].mockResolvedValueOnce({ data });
  const recusa = (metodo, falha) =>
    TrazerAPI[metodo].mockRejectedValueOnce(falha);
  const comLeitura = async () => {
    const fonte = trazerFonte({ demo: null, espera: async () => {} });
    responde('enviar', { id: 812, situacao: 'lendo' });
    responde('leitura', PRONTA);
    await fonte.ler({ name: 'Clientes 2025.csv' });
    vi.clearAllMocks();
    return fonte;
  };

  it('ficar com a outra linha manda `ficar_com` e a linha volta deixada de fora', async () => {
    const fonte = await comLeitura();
    responde('consertar', { problema: { ...REPETIDA, estado: 'deixado' } });
    const nova = await fonte.consertar(812, 8, 2);
    expect(TrazerAPI.consertar).toHaveBeenCalledWith(812, 8, { ficar_com: 2 });
    expect(daLinha(nova, 8)).toEqual({ ...REPETIDA, estado: 'deixado' });
  });

  it('ficar com esta guarda `ficar_com`; voltar atrás tira', async () => {
    const fonte = await comLeitura();
    responde('consertar', {
      problema: { ...REPETIDA, estado: 'guardado', ficar_com: 8 },
    });
    const guardada = await fonte.consertar(812, 8, 8);
    expect(daLinha(guardada, 8).ficar_com).toBe(8);
    responde('reabrir', { problema: REPETIDA });
    const reaberta = await fonte.reabrir(812, 8);
    expect(daLinha(reaberta, 8)).toEqual(REPETIDA);
  });

  it('deixar de fora a linha consertada tira o valor corrigido', async () => {
    const fonte = await comLeitura();
    responde('consertar', {
      problema: {
        ...TELEFONE,
        estado: 'guardado',
        corrigido: '+5511987650004',
      },
    });
    await fonte.consertar(812, 4, '11987650004');
    responde('deixarDeFora', { problema: { ...TELEFONE, estado: 'deixado' } });
    const deixada = await fonte.deixarDeFora(812, 4);
    expect(daLinha(deixada, 4)).toEqual({ ...TELEFONE, estado: 'deixado' });
  });

  it('o valor valeu e a linha ainda tem outro problema (200): o problema que sobrou toma o lugar, sem erro', async () => {
    const fonte = await comLeitura();
    responde('consertar', { problema: SOBROU_O_NOME, entram: 2 });
    const nova = await fonte.consertar(812, 4, '11987650004');
    expect(daLinha(nova, 4)).toEqual(SOBROU_O_NOME);
    expect(resumoDaTela(nova).precisamDeVoce).toBe(4);
    // O conserto seguinte da mesma linha já vai como nome.
    responde('consertar', {
      problema: {
        ...SOBROU_O_NOME,
        estado: 'guardado',
        corrigido: 'Carla Carvalhedo',
      },
    });
    const guardada = await fonte.consertar(812, 4, 'Carla Carvalhedo');
    expect(TrazerAPI.consertar).toHaveBeenLastCalledWith(812, 4, {
      valor: 'Carla Carvalhedo',
    });
    expect(daLinha(guardada, 4).estado).toBe('guardado');
  });

  it.each([
    ['trocarDestino', 'trocarColuna', [3, 'telefone_da_empresa']],
    ['responder', 'responder', [{ telefone: 'da_empresa' }]],
  ])(
    '%s sem coluna de empresa (422 `sem_empresa`) ganha nome',
    async (metodo, daApi, argumentos) => {
      const fonte = await comLeitura();
      recusa(daApi, erroHttp(422, 'sem_empresa'));
      await expect(fonte[metodo](812, ...argumentos)).rejects.toMatchObject({
        name: 'SEM_EMPRESA',
      });
    }
  );

  it('o nome do campo longo demais (422 `valor_invalido` na coluna) leva o motivo', async () => {
    const fonte = await comLeitura();
    recusa(
      'trocarColuna',
      erroHttp(422, 'valor_invalido', { motivo: 'muito_longo' })
    );
    await expect(
      fonte.trocarDestino(812, 3, 'informacao', { nome: 'x' })
    ).rejects.toMatchObject({ name: 'VALOR_INVALIDO', motivo: 'muito_longo' });
  });

  it('a leitura diz à tela se o telefone da empresa existe', async () => {
    const fonte = trazerFonte({ demo: null, espera: async () => {} });
    responde('enviar', { id: 812, situacao: 'lendo' });
    responde('leitura', pronta({ tem_empresa: false }));
    expect((await fonte.ler({ name: 'a.csv' })).temEmpresa).toBe(false);
  });

  it('consertar depois que a planilha foi apagada (422 `planilha_apagada`) ganha nome', async () => {
    const fonte = await comLeitura();
    recusa('consertar', erroHttp(422, 'planilha_apagada'));
    await expect(fonte.consertar(812, 4, 'x')).rejects.toMatchObject({
      name: 'PLANILHA_APAGADA',
    });
  });

  it.each([
    ['consertar', 'leitura_nao_pronta', 'consertar', [4, 'x']],
    ['consertar', 'linha_desconhecida', 'consertar', [4, 'x']],
    ['deixarDeFora', 'leitura_nao_pronta', 'deixarDeFora', [4]],
    ['deixarDeFora', 'linha_desconhecida', 'deixarDeFora', [4]],
    ['reabrir', 'leitura_nao_pronta', 'reabrir', [4]],
    [
      'responder',
      'leitura_nao_pronta',
      'responder',
      [{ clientes: 'sim_todas' }],
    ],
    [
      'responder',
      'resposta_desconhecida',
      'responder',
      [{ clientes: 'sim_todas' }],
    ],
    [
      'responder',
      'pergunta_desconhecida',
      'responder',
      [{ telefone: 'da_pessoa' }],
    ],
    [
      'responder',
      'coluna_desconhecida',
      'responder',
      [{ clientes: 'algumas', colunaCliente: 3 }],
    ],
    ['trocarDestino', 'leitura_nao_pronta', 'trocarColuna', [3, 'cidade']],
    ['trazer', 'leitura_nao_pronta', 'trazer', []],
  ])(
    '%s recusado com 422 `%s` vira TELA_DESATUALIZADA',
    async (metodo, codigo, daApi, argumentos) => {
      const fonte = await comLeitura();
      recusa(daApi, erroHttp(422, codigo));
      await expect(fonte[metodo](812, ...argumentos)).rejects.toMatchObject({
        name: 'TELA_DESATUALIZADA',
      });
    }
  );

  it('trazer sem ninguém para entrar (422 `nada_para_trazer`) ganha nome', async () => {
    const fonte = await comLeitura();
    recusa('trazer', erroHttp(422, 'nada_para_trazer'));
    await expect(fonte.trazer(812)).rejects.toMatchObject({
      name: 'NADA_PARA_TRAZER',
    });
  });

  it('a leitura inteira que volta das respostas traz o estado e o valor guardado de cada linha', async () => {
    const fonte = await comLeitura();
    responde(
      'responder',
      pronta({
        respostas: { clientes: 'algumas', coluna_cliente: 3 },
        problemas: [
          { ...TELEFONE, estado: 'guardado', corrigido: '+5511987650004' },
          { ...SEM_NOME, estado: 'deixado' },
          SEM_CONTATO,
          { ...REPETIDA, estado: 'guardado', ficar_com: 8 },
        ],
      })
    );
    const nova = await fonte.responder(812, {
      clientes: 'algumas',
      colunaCliente: 3,
    });
    expect(TrazerAPI.responder).toHaveBeenCalledWith(812, {
      clientes: 'algumas',
      coluna_cliente: 3,
    });
    expect(nova.respostas).toEqual({ clientes: 'algumas', colunaCliente: 3 });
    expect(nova.problemas.map(problema => problema.estado)).toEqual([
      'guardado',
      'deixado',
      'aberto',
      'guardado',
    ]);
    expect(daLinha(nova, 4).corrigido).toBe('+5511987650004');
    expect(daLinha(nova, 8).ficar_com).toBe(8);
  });
});
