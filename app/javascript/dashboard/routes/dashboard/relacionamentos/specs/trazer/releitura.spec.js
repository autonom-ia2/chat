import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { ETAPAS } from '../../trazer/etapas';
import { ERROS } from '../../trazer/useTrazerLista';
import {
  MARCADOR as MARCADOR_DA_TELA,
  PERGUNTAS as PERGUNTAS_DA_TELA,
  RESPONDIDAS,
  emVoo,
  erroDeNome,
  fonteDeMentira,
  lida,
  montarTela,
  noConferir,
} from './apoioDaTela';
import {
  COLUNAS,
  LENDO,
  RESUMO,
  erroHttp,
  fonteComLeitura,
  problema,
  pronta,
  responder,
} from './apoioDoServidor';

// #2896, Fatia 2 — responder a uma pergunta e trocar uma coluna. Quando a
// planilha não precisa ser lida de novo, o servidor devolve a leitura inteira e
// a fonte a usa inteira. Quando precisa, ele responde `lendo` e a fonte devolve
// só o marcador, sem esperar: quem espera é a tela (`retomar`), que assim sabe
// que a mudança já está salva mesmo que a espera falhe.
vi.mock('dashboard/api/relacionamentosTrazer', async () => ({
  default: (await import('./apiDeMentira')).apiDeMentira(),
}));

const responde = responder(TrazerAPI);
const MARCADOR = { situacao: 'lendo', id: 812 };
const PERGUNTAS = [
  { id: 'clientes' },
  { id: 'telefone', coluna: 'Cel', indice: 1 },
];
const SEM_SITUACAO = COLUNAS.map(coluna =>
  coluna.indice === 6 ? { ...coluna, destino: 'nao_guardar' } : coluna
);
// A leitura inteira que volta de uma escrita: tudo diferente do que a fonte tinha.
const INTEIRA = pronta({
  colunas: SEM_SITUACAO,
  tem_empresa: false,
  perguntas: PERGUNTAS,
  respostas: { clientes: 'algumas', coluna_cliente: 6, telefone: 'da_pessoa' },
  resumo: { ...RESUMO, novas: 170, entram: 185 },
  exemplos: [{ nome: 'Ana', telefone: '+5511987650001' }],
  problemas: [problema(14, { estado: 'deixado' }), problema(37)],
  problemas_total: 300,
});
const DA_TELA = {
  id: 812,
  arquivo: 'Clientes 2025.xlsx',
  valores: 'inteiros',
  temEmpresa: false,
  colunas: SEM_SITUACAO,
  perguntas: PERGUNTAS,
  respostas: { clientes: 'algumas', colunaCliente: 6, telefone: 'da_pessoa' },
  resumo: { ...RESUMO, novas: 170, entram: 185 },
  exemplos: [{ nome: 'Ana', telefone: '+55 11 98765-0001' }],
  problemas: [problema(14, { estado: 'deixado' }), problema(37)],
  problemasTotal: 300,
};

afterEach(() => {
  vi.resetAllMocks();
});

describe('fonte real: a escrita que devolve a leitura inteira', () => {
  it('responder usa a leitura que voltou, inteira, sem pedir de novo', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('responder', INTEIRA);
    const nova = await fonte.responder(812, {
      clientes: 'algumas',
      colunaCliente: 6,
      telefone: 'da_pessoa',
    });
    expect(nova).toEqual(DA_TELA);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });

  it('trocar a coluna usa a leitura que voltou, inteira, sem pedir de novo', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('trocarColuna', INTEIRA);
    const nova = await fonte.trocarDestino(812, 6, 'nao_guardar');
    expect(TrazerAPI.trocarColuna).toHaveBeenCalledWith(812, 6, {
      destino: 'nao_guardar',
    });
    expect(nova).toEqual(DA_TELA);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
  });

  it('guarda o aviso de que a mudança foi desfeita, e só quando ele vem', async () => {
    const { fonte, leitura } = await fonteComLeitura(TrazerAPI);
    expect(leitura).not.toHaveProperty('aviso');
    responde('trocarColuna', pronta({ aviso: 'mudanca_desfeita' }));
    const desfeita = await fonte.trocarDestino(812, 6, 'nao_guardar');
    expect(desfeita.aviso).toBe('mudanca_desfeita');
    responde('trocarColuna', pronta());
    const seguinte = await fonte.trocarDestino(812, 6, 'cidade');
    expect(seguinte).not.toHaveProperty('aviso');
  });

  it('a escrita numa linha que dá certo também tira o aviso', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('trocarColuna', pronta({ aviso: 'mudanca_desfeita' }));
    await fonte.trocarDestino(812, 6, 'nao_guardar');
    responde('deixarDeFora', {
      problema: problema(14, { estado: 'deixado' }),
      entram: 194,
    });
    const depois = await fonte.deixarDeFora(812, 14);
    expect(depois).not.toHaveProperty('aviso');
    expect(depois.resumo.entram).toBe(194);
  });

  it('a escrita seguinte parte da leitura que voltou', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    responde('responder', INTEIRA);
    await fonte.responder(812, { clientes: 'sim_todas' });
    responde('reabrir', { problema: problema(14), entram: 186 });
    const reaberta = await fonte.reabrir(812, 14);
    expect(reaberta.colunas).toEqual(SEM_SITUACAO);
    expect(reaberta.problemas).toEqual([problema(14), problema(37)]);
    expect(reaberta.resumo.entram).toBe(186);
  });
});

describe('fonte real: a escrita que faz a planilha ser lida de novo', () => {
  it('responder devolve o marcador `lendo` sem esperar nem perguntar', async () => {
    const { fonte, espera } = await fonteComLeitura(TrazerAPI);
    responde('responder', LENDO);
    expect(await fonte.responder(812, { telefone: 'nao_usar' })).toEqual(
      MARCADOR
    );
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(espera).not.toHaveBeenCalled();
  });

  it('trocar a coluna devolve o marcador `lendo` sem esperar nem perguntar', async () => {
    const { fonte, espera } = await fonteComLeitura(TrazerAPI);
    responde('trocarColuna', LENDO);
    expect(await fonte.trocarDestino(812, 1, 'nao_guardar')).toEqual(MARCADOR);
    expect(TrazerAPI.leitura).not.toHaveBeenCalled();
    expect(espera).not.toHaveBeenCalled();
  });

  it('quem espera é o `retomar`, que devolve a leitura nova', async () => {
    const { fonte, espera } = await fonteComLeitura(TrazerAPI);
    responde('trocarColuna', LENDO);
    await fonte.trocarDestino(812, 1, 'nao_guardar');
    responde('leitura', LENDO, INTEIRA);
    expect(await fonte.retomar(812)).toEqual(DA_TELA);
    expect(TrazerAPI.leitura.mock.calls).toEqual([
      [812, 1],
      [812, 1],
    ]);
    expect(espera).toHaveBeenCalledTimes(1);
  });
});

describe('fonte real: o pedido que o servidor já não conhece', () => {
  // 404 em qualquer escrita: a leitura já foi trazida (por outra aba, por outra
  // pessoa da conta).
  it.each([
    ['responder', 'responder', [{ clientes: 'sim_todas' }]],
    ['trocarDestino', 'trocarColuna', [6, 'nao_guardar']],
    ['consertar', 'consertar', [14, '11973800014']],
    ['deixarDeFora', 'deixarDeFora', [14]],
    ['reabrir', 'reabrir', [14]],
    ['trazer', 'trazer', []],
  ])('404 em %s vira TELA_DESATUALIZADA', async (metodo, daApi, argumentos) => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    TrazerAPI[daApi].mockRejectedValueOnce(erroHttp(404));
    await expect(fonte[metodo](812, ...argumentos)).rejects.toMatchObject({
      name: 'TELA_DESATUALIZADA',
    });
  });

  it.each([
    'leitura_nao_pronta',
    'linha_desconhecida',
    'coluna_desconhecida',
    'destino_desconhecido',
    'resposta_desconhecida',
    'pergunta_desconhecida',
  ])('422 `%s` vira TELA_DESATUALIZADA', async codigo => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    TrazerAPI.trocarColuna.mockRejectedValueOnce(erroHttp(422, codigo));
    await expect(
      fonte.trocarDestino(812, 6, 'nao_guardar')
    ).rejects.toMatchObject({ name: 'TELA_DESATUALIZADA' });
  });

  it('a linha repetida que o servidor não conhece (`valor_invalido` com `linha_desconhecida`) também', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    TrazerAPI.consertar.mockRejectedValueOnce(
      erroHttp(422, 'valor_invalido', { motivo: 'linha_desconhecida' })
    );
    await expect(fonte.consertar(812, 14, 88)).rejects.toMatchObject({
      name: 'TELA_DESATUALIZADA',
    });
  });

  it('o valor que não vale continua sendo VALOR_INVALIDO, com o motivo', async () => {
    const { fonte } = await fonteComLeitura(TrazerAPI);
    TrazerAPI.consertar.mockRejectedValueOnce(
      erroHttp(422, 'valor_invalido', { motivo: 'invalid_email' })
    );
    await expect(fonte.consertar(812, 14, 'x')).rejects.toMatchObject({
      name: 'VALOR_INVALIDO',
      motivo: 'invalid_email',
    });
  });
});

// ---- a tela ------------------------------------------------------------------

const PENDENTE = erroDeNome('LEITURA_PENDENTE', { leituraId: 'l1' });
const SEM_CEL = lida({
  colunas: [{ indice: 1, nome: 'Cel', destino: 'nao_guardar' }],
  resumo: { total: 200, novas: 150, completadas: 10, entram: 160 },
});

describe('a tela espera a leitura de novo depois da escrita', () => {
  it('fica "relendo" enquanto espera e usa a leitura que o `retomar` devolve', async () => {
    const espera = emVoo();
    const { tela, fonte } = await noConferir(lida(), {
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
      retomar: vi.fn(() => espera.promessa),
    });
    const troca = tela.trocarDestino(1, 'nao_guardar');
    await vi.waitFor(() => expect(tela.relendo.value).toBe(true));
    expect(tela.ocupado.value).toBe(true);
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
    espera.resolver(SEM_CEL);
    expect(await troca).toBe(true);
    expect(tela.relendo.value).toBe(false);
    expect(tela.ocupado.value).toBe(false);
    expect(tela.leitura.value).toEqual(SEM_CEL);
    expect(tela.entram.value).toBe(160);
  });

  // O servidor já trocou a coluna: "não consegui salvar" seria mentira.
  it.each([
    ['o teto de tempo passou', PENDENTE],
    ['a rede caiu', erroDeNome('LEITURA_PENDENTE', { leituraId: 'l1' })],
  ])(
    'a espera falha (%s): fica "releitura parada", sem dizer que não salvou',
    async (_caso, falha) => {
      const { tela, avisar } = await noConferir(lida(), {
        trocarDestino: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
        retomar: vi.fn().mockRejectedValue(falha),
      });
      await tela.trocarDestino(1, 'nao_guardar');
      expect(tela.releituraParada.value).toBe(true);
      expect(tela.relendo.value).toBe(false);
      expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
      expect(avisar).not.toHaveBeenCalled();
      expect(tela.recusaDaColuna.value).toBeNull();
    }
  );

  it('"Tentar de novo" só pergunta de novo pela mesma leitura: não repete a troca', async () => {
    const { tela, fonte } = await noConferir(lida(), {
      trocarDestino: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
      retomar: vi
        .fn()
        .mockRejectedValueOnce(PENDENTE)
        .mockResolvedValueOnce(SEM_CEL),
    });
    await tela.trocarDestino(1, 'nao_guardar');
    await tela.tentarDeNovo();
    expect(fonte.trocarDestino).toHaveBeenCalledTimes(1);
    expect(fonte.retomar.mock.calls).toEqual([['l1'], ['l1']]);
    expect(tela.releituraParada.value).toBe(false);
    expect(tela.leitura.value).toEqual(SEM_CEL);
  });

  // "Ficar com esta" numa linha repetida: o conserto está salvo, mas a fonte não
  // conseguiu ler de novo como ficaram as outras linhas e devolve o marcador.
  it('"ficar com esta" sem a leitura de novo: fica "releitura parada", sem dizer que não salvou nem mostrar a lista velha', async () => {
    const { tela, fonte, avisar } = await noConferir(lida(), {
      consertar: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
      retomar: vi
        .fn()
        .mockRejectedValueOnce(PENDENTE)
        .mockResolvedValueOnce(SEM_CEL),
    });
    await tela.guardar(143, 143);
    expect(fonte.retomar).toHaveBeenCalledWith('l1');
    expect(tela.releituraParada.value).toBe(true);
    expect(tela.recusaDoConserto.value).toBeNull();
    expect(avisar).not.toHaveBeenCalled();
    await tela.tentarDeNovo();
    expect(fonte.consertar).toHaveBeenCalledTimes(1);
    expect(tela.releituraParada.value).toBe(false);
    expect(tela.leitura.value).toEqual(SEM_CEL);
  });

  it('a resposta que faz ler de novo: a espera falha e, ao tentar de novo, a tela segue para o Conferir', async () => {
    const comPerguntas = lida({ perguntas: PERGUNTAS_DA_TELA });
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(comPerguntas),
      responder: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
      retomar: vi
        .fn()
        .mockRejectedValueOnce(PENDENTE)
        .mockResolvedValueOnce({ ...comPerguntas, respostas: RESPONDIDAS }),
    });
    const { tela, avisar } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.releituraParada.value).toBe(true);
    expect(avisar).not.toHaveBeenCalled();
    await tela.tentarDeNovo();
    expect(fonte.responder).toHaveBeenCalledTimes(1);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('a resposta que o servidor desfaz devolve a pessoa à pergunta, sem pular para o Conferir', async () => {
    const comPerguntas = lida({ perguntas: PERGUNTAS_DA_TELA });
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(comPerguntas),
      responder: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
      retomar: vi.fn().mockResolvedValue({
        ...comPerguntas,
        respostas: { clientes: 'sim_todas' },
        aviso: 'mudanca_desfeita',
      }),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'nao_usar');
    await tela.continuar();
    expect(tela.etapa.value).toBe(ETAPAS.PERGUNTAS);
    expect(tela.perguntaAtual.value.id).toBe('telefone');
    expect(tela.leitura.value.aviso).toBe('mudanca_desfeita');
  });
});

describe('a leitura de novo termina sem ninguém', () => {
  it.each(['PLANILHA_SEM_CONTATO', 'PLANILHA_VAZIA', 'LEITURA_FALHOU'])(
    'a releitura que falha (%s) volta ao Enviar com a frase da mudança',
    async nome => {
      const { tela, avisar } = await noConferir(lida(), {
        trocarDestino: vi.fn().mockResolvedValue(MARCADOR_DA_TELA),
        retomar: vi.fn().mockRejectedValue(erroDeNome(nome)),
      });
      await tela.trocarDestino(1, 'nao_guardar');
      expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
      expect(tela.erro.value).toBe(ERROS.SEM_NINGUEM);
      expect(tela.leitura.value).toBeNull();
      expect(tela.ocupado.value).toBe(false);
      expect(avisar).not.toHaveBeenCalled();
    }
  );
});

describe('a tela desatualizada lê de novo sozinha', () => {
  const DESATUALIZADA = erroDeNome('TELA_DESATUALIZADA');
  const COMO_ESTA = lida({
    problemas: [],
    problemasTotal: 0,
    resumo: { total: 200, novas: 181, completadas: 15, entram: 196 },
  });
  const escritas = [
    [
      'trocar a coluna',
      'trocarDestino',
      tela => tela.trocarDestino(6, 'cidade'),
    ],
    ['consertar', 'consertar', tela => tela.guardar(14, 'x')],
    ['deixar de fora', 'deixarDeFora', tela => tela.deixarDeFora(14)],
    ['voltar atrás', 'reabrir', tela => tela.reabrir(14)],
    ['trazer', 'trazer', tela => tela.trazer()],
  ];

  it.each(escritas)(
    '%s recusado: pede a leitura de novo e diz que a lista mudou',
    async (_nome, metodo, agir) => {
      const { tela, fonte, avisar } = await noConferir(lida(), {
        [metodo]: vi.fn().mockRejectedValue(DESATUALIZADA),
        retomar: vi.fn().mockResolvedValue(COMO_ESTA),
      });
      expect(tela.mudou.value).toBe(false);
      await agir(tela);
      expect(fonte.retomar).toHaveBeenCalledWith('l1');
      expect(tela.leitura.value).toEqual(COMO_ESTA);
      expect(tela.mudou.value).toBe(true);
      expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
      expect(tela.erro.value).toBe(ERROS.NENHUM);
      expect(tela.ocupado.value).toBe(false);
      expect(avisar).not.toHaveBeenCalled();
    }
  );

  it('responder recusado na última pergunta: lê de novo e vai para onde a leitura pede', async () => {
    const comPerguntas = lida({ perguntas: PERGUNTAS_DA_TELA });
    const fonte = fonteDeMentira({
      ler: vi.fn().mockResolvedValue(comPerguntas),
      responder: vi.fn().mockRejectedValue(DESATUALIZADA),
      retomar: vi
        .fn()
        .mockResolvedValue({ ...comPerguntas, respostas: RESPONDIDAS }),
    });
    const { tela } = montarTela(fonte);
    await tela.escolherArquivo({ name: 'a.csv' });
    tela.responder('clientes', 'sim_todas');
    await tela.continuar();
    tela.responder('telefone', 'da_pessoa');
    await tela.continuar();
    expect(tela.mudou.value).toBe(true);
    expect(tela.etapa.value).toBe(ETAPAS.CONFERIR);
  });

  it('o aviso de que a lista mudou some na escrita seguinte que dá certo', async () => {
    const { tela } = await noConferir(lida(), {
      deixarDeFora: vi
        .fn()
        .mockRejectedValueOnce(DESATUALIZADA)
        .mockResolvedValueOnce(lida()),
      retomar: vi.fn().mockResolvedValue(lida()),
    });
    await tela.deixarDeFora(14);
    expect(tela.mudou.value).toBe(true);
    await tela.deixarDeFora(14);
    expect(tela.mudou.value).toBe(false);
  });

  it('a leitura já foi trazida (o `retomar` não a acha): volta ao Enviar e diz isso', async () => {
    const { tela } = await noConferir(lida(), {
      trazer: vi.fn().mockRejectedValue(DESATUALIZADA),
      retomar: vi.fn().mockRejectedValue(erroDeNome('LEITURA_NAO_ENCONTRADA')),
    });
    await tela.trazer();
    expect(tela.etapa.value).toBe(ETAPAS.ENVIAR);
    expect(tela.erro.value).toBe(ERROS.JA_TRAZIDA);
    expect(tela.leitura.value).toBeNull();
    expect(tela.mudou.value).toBe(false);
  });
});
