import { effectScope } from 'vue';
import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { trazerFonte } from '../../fonte/trazerFonte';
import { resumoDaTela } from '../../trazer/contagem';
import { ETAPAS } from '../../trazer/etapas';
import {
  INTERVALO_DO_ANDAMENTO_MS,
  useTrazerLista,
} from '../../trazer/useTrazerLista';
// #2896 — a fonte real (fonte/trazerFonte.js) com o que a leitura do servidor
// traz, com o cliente de API simulado: `tem_empresa`, o `motivo` do problema
// aberto, a linha de fórmula, o conserto parcial, as perguntas e as respostas
// que mudam com a troca de coluna, e o trazer pelo id que o servidor devolve.
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

const TELEFONE = {
  linha: 4,
  tipo: 'telefone',
  nome: 'Carla Carvalhedo',
  valor: '(11) 2345-678',
  estado: 'aberto',
};

const EMAIL = {
  linha: 5,
  tipo: 'email',
  nome: 'Davi Dornelino',
  valor: 'davi.exemplo.com.br',
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

// A linha com uma fórmula na empresa: a tela não conserta.
const COM_FORMULA = {
  linha: 9,
  tipo: 'formula',
  campo: 'empresa',
  nome: 'Caio Camargo',
  estado: 'aberto',
};

// O conserto parcial, como o servidor responde: o telefone valeu e sobrou o nome.
const SOBROU_O_NOME = {
  linha: 3,
  tipo: 'nome',
  nome: '',
  valor: '',
  contato: '11987650003',
  estado: 'aberto',
};

const PRONTA = {
  id: 812,
  situacao: 'pronta',
  arquivo: 'Clientes 2025.csv',
  valores: 'inteiros',
  tem_empresa: true,
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'telefone', duvidosa: true },
    { indice: 5, nome: 'Situação', destino: 'cliente' },
    { indice: 6, nome: 'Fone 2', destino: 'informacao' },
  ],
  perguntas: [
    { id: 'clientes' },
    { id: 'telefone', coluna: 'Celular', indice: 1 },
  ],
  respostas: {
    clientes: 'algumas',
    coluna_cliente: 5,
    telefone: 'da_pessoa',
  },
  resumo: { total: 7, novas: 2, completadas: 0, comProblema: 4, juntadas: 0 },
  exemplos: [],
  problemas: [TELEFONE, EMAIL, SEM_NOME, SEM_CONTATO],
  problemas_total: 4,
  pagina: 1,
  por_pagina: 200,
};

// Depois de a pessoa mandar o telefone para outra coluna: a pergunta do
// telefone sai e a resposta dela deixa de valer.
const SEM_A_PERGUNTA_DO_TELEFONE = {
  ...PRONTA,
  colunas: [
    { indice: 0, nome: 'Nome', destino: 'nome' },
    { indice: 1, nome: 'Celular', destino: 'informacao' },
    { indice: 5, nome: 'Situação', destino: 'cliente' },
    { indice: 6, nome: 'Fone 2', destino: 'telefone' },
  ],
  perguntas: [{ id: 'clientes' }],
  respostas: { clientes: 'algumas', coluna_cliente: 5 },
};

const daLinha = (leitura, linha) =>
  leitura.problemas.find(problema => problema.linha === linha);

const erroHttp = (status, error, extra = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data: { error, ...extra } },
  });

describe('fonte real: o que a leitura do servidor traz', () => {
  const responde = (metodo, data) =>
    TrazerAPI[metodo].mockResolvedValueOnce({ data });
  const recusa = (metodo, falha) =>
    TrazerAPI[metodo].mockRejectedValueOnce(falha);
  const comLeitura = async (pronta = PRONTA) => {
    const fonte = trazerFonte({ demo: null, espera: async () => {} });
    responde('enviar', { id: 812, situacao: 'lendo' });
    responde('leitura', pronta);
    const leitura = await fonte.ler({ name: 'Clientes 2025.csv' });
    vi.clearAllMocks();
    return { fonte, leitura };
  };

  it.each([
    [true, true],
    [false, false],
  ])('`tem_empresa: %s` vira `temEmpresa: %s`', async (doServidor, daTela) => {
    const { leitura } = await comLeitura({
      ...PRONTA,
      tem_empresa: doServidor,
    });
    expect(leitura.temEmpresa).toBe(daTela);
  });

  it('o `motivo` do problema aberto e a linha de fórmula chegam inteiros à tela', async () => {
    const comMotivo = { ...SEM_NOME, motivo: 'formula_detected' };
    const { leitura } = await comLeitura({
      ...PRONTA,
      problemas: [comMotivo, COM_FORMULA],
      problemas_total: 2,
    });
    expect(leitura.problemas).toEqual([comMotivo, COM_FORMULA]);
    expect(resumoDaTela(leitura).precisamDeVoce).toBe(2);
  });

  it('o conserto parcial (200) troca a linha pelo problema que sobrou', async () => {
    const { fonte } = await comLeitura({
      ...PRONTA,
      problemas: [{ ...TELEFONE, linha: 3, nome: '' }],
    });
    responde('consertar', { problema: SOBROU_O_NOME });
    const nova = await fonte.consertar(812, 3, '11987650003');
    expect(TrazerAPI.consertar).toHaveBeenCalledWith(812, 3, {
      valor: '11987650003',
    });
    expect(daLinha(nova, 3)).toEqual(SOBROU_O_NOME);
  });

  it('a linha sem contato manda o que a pessoa escreveu em `valor`, telefone ou e-mail', async () => {
    const { fonte } = await comLeitura();
    responde('consertar', {
      problema: {
        ...SEM_CONTATO,
        estado: 'guardado',
        corrigido: 'elisa@exemplo.com.br',
      },
    });
    const nova = await fonte.consertar(812, 7, 'elisa@exemplo.com.br');
    expect(TrazerAPI.consertar).toHaveBeenCalledWith(812, 7, {
      valor: 'elisa@exemplo.com.br',
    });
    expect(daLinha(nova, 7).corrigido).toBe('elisa@exemplo.com.br');
  });

  it('a linha de fórmula pode ficar de fora e voltar', async () => {
    const { fonte } = await comLeitura({ ...PRONTA, problemas: [COM_FORMULA] });
    responde('deixarDeFora', {
      problema: { ...COM_FORMULA, estado: 'deixado' },
    });
    const deixada = await fonte.deixarDeFora(812, 9);
    expect(daLinha(deixada, 9)).toEqual({ ...COM_FORMULA, estado: 'deixado' });
    responde('reabrir', { problema: COM_FORMULA });
    expect(daLinha(await fonte.reabrir(812, 9), 9)).toEqual(COM_FORMULA);
  });

  it.each([
    ['nome', { nome: 'n'.repeat(256) }],
    ['para que serve', { nome: 'Plano', para_que_serve: 'p'.repeat(1001) }],
  ])(
    'o %s longo demais na coluna (422 com `motivo`) ganha nome e leva o motivo',
    async (_qual, campo) => {
      const { fonte } = await comLeitura();
      recusa(
        'trocarColuna',
        erroHttp(422, 'valor_invalido', { motivo: 'muito_longo' })
      );
      await expect(
        fonte.trocarDestino(812, 6, 'informacao', campo)
      ).rejects.toMatchObject({
        name: 'VALOR_INVALIDO',
        motivo: 'muito_longo',
      });
    }
  );

  it('a troca que faz o servidor ler de novo: a leitura retomada traz as perguntas e as respostas de agora', async () => {
    const { fonte } = await comLeitura();
    responde('trocarColuna', { id: 812, situacao: 'lendo' });
    expect(await fonte.trocarDestino(812, 6, 'telefone')).toEqual({
      situacao: 'lendo',
      id: 812,
    });
    responde('leitura', SEM_A_PERGUNTA_DO_TELEFONE);
    const nova = await fonte.retomar(812);
    expect(nova.perguntas).toEqual([{ id: 'clientes' }]);
    expect(nova.respostas).toEqual({ clientes: 'algumas', colunaCliente: 5 });
  });

  it('a troca na hora que devolve perguntas e respostas: a leitura fica com elas', async () => {
    const { fonte } = await comLeitura();
    // O servidor responde a leitura inteira, como o GET.
    responde('trocarColuna', {
      ...PRONTA,
      colunas: SEM_A_PERGUNTA_DO_TELEFONE.colunas,
      perguntas: [{ id: 'clientes' }],
      respostas: {},
    });
    const nova = await fonte.trocarDestino(812, 5, 'informacao');
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(nova.perguntas).toEqual([{ id: 'clientes' }]);
    expect(nova.respostas).toEqual({});
    expect(nova.problemas).toHaveLength(PRONTA.problemas.length);
  });

  it('trazer: a tela acompanha a lista pelo id que o servidor devolve, segue "Trazendo" com as contas zeradas e termina com as contas dele', async () => {
    vi.useFakeTimers();
    const fonte = trazerFonte({ demo: null, espera: async () => {} });
    const escopo = effectScope();
    const tela = escopo.run(() => useTrazerLista({ fonte }));
    responde('enviar', { id: 812, situacao: 'lendo' });
    responde('leitura', { ...PRONTA, perguntas: [] });
    await tela.escolherArquivo({ name: 'Clientes 2025.csv' });
    responde('trazer', { trazidaId: 813 });
    responde('andamento', {
      situacao: 'trazendo',
      porcentagem: 0,
      total: 0,
      novas: 0,
      completadas: 0,
    });
    await tela.trazer();
    expect(TrazerAPI.trazer).toHaveBeenCalledWith(812);
    expect(TrazerAPI.andamento).toHaveBeenCalledWith(813);
    expect(tela.etapa.value).toBe(ETAPAS.TRAZENDO);
    expect(tela.porcentagem.value).toBe(0);
    expect(tela.novasTrazidas.value).toBe(0);
    responde('andamento', {
      situacao: 'pronto',
      porcentagem: 100,
      total: 4,
      novas: 3,
      completadas: 1,
    });
    await vi.advanceTimersByTimeAsync(INTERVALO_DO_ANDAMENTO_MS);
    expect(tela.etapa.value).toBe(ETAPAS.PRONTO);
    expect(tela.novasTrazidas.value).toBe(3);
    expect(tela.completadasTrazidas.value).toBe(1);
    escopo.stop();
    vi.useRealTimers();
  });
});
