import { useAutonomiaGuideStore } from 'dashboard/store/modules/autonomiaGuide';

// #895 — anexos que vão com a mensagem e a mensagem de voz.
describe('autonomiaGuide store — anexos e voz', () => {
  const store = useAutonomiaGuideStore();

  beforeEach(() => {
    URL.revokeObjectURL = vi.fn();
  });

  afterEach(() => {
    store.reset();
  });

  const anexoPronto = (nome, opcoes) => {
    const id = store.addArquivo(nome, opcoes);
    store.marcarArquivo(id, 'pronto', `assinado-${nome}`);
    return id;
  };

  it('o envio leva os anexos prontos para o balão e os tira do campo', () => {
    anexoPronto('print.png', { tipo: 'imagem', previa: 'blob:print' });
    const subindo = store.addArquivo('lento.pdf');

    const mensagem = store.addUserMessage('Lê isso');

    expect(mensagem.anexos).toEqual([
      expect.objectContaining({
        nome: 'print.png',
        tipo: 'imagem',
        previa: 'blob:print',
      }),
    ]);
    expect(store.arquivosPendentes().map(item => item.id)).toEqual([subindo]);
  });

  it('os anexos enviados continuam indo ao Guia em toda pergunta', () => {
    anexoPronto('apolice.pdf');
    store.addUserMessage('Resume');
    store.addUserMessage('E o vencimento?');

    expect(store.arquivosProntos()).toEqual(['assinado-apolice.pdf']);
  });

  it('só anexos: o balão fica sem texto, o histórico leva a frase padrão', () => {
    anexoPronto('a.pdf');

    const mensagem = store.addUserMessage('Veja o que enviei.', { texto: '' });

    expect(mensagem.texto).toBe('');
    expect(store.toHistory()).toEqual([
      { role: 'user', content: 'Veja o que enviei.' },
    ]);
  });

  it('a voz entra no histórico só depois de virar texto', () => {
    const audio = new Blob(['ogg'], { type: 'audio/ogg' });
    const mensagem = store.addUserMessage('', {
      voz: { audio, url: 'blob:voz', duracao: 3 },
    });

    expect(mensagem.voz).toEqual(
      expect.objectContaining({ estado: 'transcrevendo', duracao: 3 })
    );
    expect(store.toHistory()).toEqual([]);

    store.marcarVoz(mensagem.id, 'pronta', { texto: 'quantos leads' });

    expect(store.toHistory()).toEqual([
      { role: 'user', content: 'quantos leads' },
    ]);
    expect(store.messages[0].voz.texto).toBe('quantos leads');
  });

  it('a falha da transcrição fica escrita na mensagem', () => {
    const mensagem = store.addUserMessage('', {
      voz: { audio: new Blob(), url: 'blob:voz', duracao: 1 },
    });

    store.marcarVoz(mensagem.id, 'erro', { erro: 'Não entendi.' });

    expect(store.messages[0].voz).toEqual(
      expect.objectContaining({ estado: 'erro', erro: 'Não entendi.' })
    );
    expect(store.toHistory()).toEqual([]);
  });

  it('marcarVoz devolve false quando a mensagem sumiu', () => {
    expect(store.marcarVoz(999, 'pronta', { texto: 'x' })).toBe(false);
  });

  it('nova conversa solta o áudio e as miniaturas da memória', () => {
    anexoPronto('print.png', { tipo: 'imagem', previa: 'blob:print' });
    store.addUserMessage('olha');
    store.addUserMessage('', {
      voz: { audio: new Blob(), url: 'blob:voz', duracao: 1 },
    });

    store.reset();

    expect(URL.revokeObjectURL).toHaveBeenCalledTimes(2);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:print');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:voz');
  });

  it('remover uma foto do campo solta a miniatura', () => {
    const id = store.addArquivo('print.png', {
      tipo: 'imagem',
      previa: 'blob:print',
    });

    store.removeArquivo(id);

    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:print');
    expect(store.arquivos).toHaveLength(0);
  });
});

// #861 — a conversa guardada no servidor volta para a tela.
describe('autonomiaGuide store — conversa guardada', () => {
  const store = useAutonomiaGuideStore();
  const ACAO_RETIDA = {
    nome: 'criar_funil',
    dados: { nome: 'Vendas' },
    descricao: { frase: 'Vou criar o funil Vendas.' },
  };
  const avisos = { retido: 'RETIDO', falhou: 'FALHOU' };

  const turno = (extra = {}) => ({
    pedido_id: 'p1',
    pergunta: 'quantos funis?',
    anexos: [],
    status: 'done',
    resposta: 'São 3.',
    navegacoes: [],
    artigos: [],
    acao: null,
    acao_estado: null,
    acao_resultado: null,
    execucao: null,
    ...extra,
  });

  beforeEach(() => {
    URL.revokeObjectURL = vi.fn();
  });

  afterEach(() => {
    store.reset();
  });

  it('transforma cada turno na pergunta e na resposta, com a conversa', () => {
    const pendente = store.hidratar(
      {
        id: 9,
        turnos: [
          turno(),
          turno({ pedido_id: 'p2', pergunta: 'e quais?', resposta: 'Vendas.' }),
        ],
      },
      avisos
    );

    expect(pendente).toBeNull();
    expect(store.conversaAtual()).toBe(9);
    expect(
      store.messages.map(m => [m.message_type, m.message.content])
    ).toEqual([
      ['user', 'quantos funis?'],
      ['assistant', 'São 3.'],
      ['user', 'e quais?'],
      ['assistant', 'Vendas.'],
    ]);
    expect(store.messages[1].pedidoId).toBe('p1');
  });

  it('retida e falha mostram o aviso da tela, e a pendente volta para buscar', () => {
    const pendente = store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ status: 'retido', resposta: null }),
          turno({ pedido_id: 'p2', status: 'failed', resposta: null }),
          turno({ pedido_id: 'p3', status: 'pending', resposta: null }),
        ],
      },
      avisos
    );

    expect(store.messages.map(m => m.message.content)).toEqual([
      'quantos funis?',
      'RETIDO',
      'quantos funis?',
      'FALHOU',
      'quantos funis?',
    ]);
    expect(pendente).toBe('p3');
  });

  // Entrega 2 — a mensagem do meio do trabalho volta onde estava: depois da
  // pergunta que o Guia estava fazendo e antes da resposta que a leu.
  it('a mensagem mandada no meio do trabalho volta antes da resposta que a leu', () => {
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ pergunta: 'cria três etiquetas', resposta: 'Parei.' }),
          turno({
            pedido_id: 'p2',
            pergunta: 'pensei melhor, pare',
            status: 'junto',
            resposta: null,
            junto_de: 'p1',
          }),
        ],
      },
      avisos
    );

    expect(
      store.messages.map(m => [m.message_type, m.message.content])
    ).toEqual([
      ['user', 'cria três etiquetas'],
      ['user', 'pensei melhor, pare'],
      ['assistant', 'Parei.'],
    ]);
  });

  it('fora do ar volta escrito, e falha e retida guardam a pergunta para repetir', () => {
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ status: 'failed', resposta: null, fora_do_ar: true }),
          turno({
            pedido_id: 'p2',
            status: 'retido',
            resposta: null,
            acao: ACAO_RETIDA,
          }),
        ],
      },
      { ...avisos, indisponivel: 'FORA' }
    );

    expect(store.messages[1]).toEqual(
      expect.objectContaining({
        message: expect.objectContaining({ content: 'FORA' }),
        repetir: 'quantos funis?',
      })
    );
    expect(store.messages[3]).toEqual(
      expect.objectContaining({
        acao: ACAO_RETIDA,
        acaoEstado: 'aguardando',
        repetir: 'quantos funis?',
      })
    );
  });

  // Conserto pós-deploy do #3144: o turno em que o Guia mexeu na conta volta
  // com o cartão e sem "Tentar de novo" — repetir faria tudo outra vez.
  it('falha e retida em que o Guia já fez algo voltam com o cartão, sem repetir', () => {
    const feito = { id: 9, passos: [{ acao: 'criar_contato', ok: true }] };
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({
            status: 'failed',
            resposta: null,
            fora_do_ar: true,
            execucao: feito,
          }),
          turno({
            pedido_id: 'p2',
            status: 'retido',
            resposta: null,
            execucao: feito,
          }),
        ],
      },
      { ...avisos, fezSemResposta: 'FIZ' }
    );

    expect(store.messages[1]).toEqual(
      expect.objectContaining({
        message: expect.objectContaining({ content: 'FIZ' }),
        execucao: feito,
        repetir: null,
      })
    );
    expect(store.messages[3]).toEqual(
      expect.objectContaining({
        message: expect.objectContaining({ content: 'FIZ' }),
        execucao: feito,
        repetir: null,
      })
    );
  });

  it('a resposta que chegou depois de mensagens novas fica antes delas', () => {
    store.addUserMessage('cria três etiquetas');
    const tardia = store.addUserMessage('e mais uma');
    store.marcarJunto(tardia.id, 'p2');

    store.addAssistantMessage({
      content: 'Criei as três.',
      antesDosPedidos: ['p2'],
    });

    expect(store.messages.map(m => m.message.content)).toEqual([
      'cria três etiquetas',
      'Criei as três.',
      'e mais uma',
    ]);
  });

  // Revisão do #3144: a pergunta seguinte (C) reabre depois das mensagens que
  // ela cobre (B), como aconteceu — e o "Tentar de novo" leva as duas.
  it('a pergunta seguinte volta depois das mensagens que ela cobre', () => {
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ pergunta: 'cria três etiquetas', resposta: 'Criei.' }),
          turno({
            pedido_id: 'p2',
            pergunta: 'e mais uma',
            status: 'junto',
            resposta: null,
            junto_de: 'p3',
          }),
          turno({
            pedido_id: 'p3',
            pergunta: 'chama de Vendas',
            status: 'failed',
            resposta: null,
          }),
        ],
      },
      avisos
    );

    expect(store.messages.map(m => m.message.content)).toEqual([
      'cria três etiquetas',
      'Criei.',
      'e mais uma',
      'chama de Vendas',
      'FALHOU',
    ]);
    expect(store.messages[4].repetir).toBe('e mais uma\n\nchama de Vendas');
  });

  it('a junta cujo turno não está na conversa aparece sozinha', () => {
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({
            pedido_id: 'p2',
            pergunta: 'pare',
            status: 'junto',
            resposta: null,
            junto_de: 'p-antigo',
          }),
        ],
      },
      avisos
    );

    expect(store.messages.map(m => m.message.content)).toEqual(['pare']);
  });

  it('a mensagem marcada depois da resposta que devia ficar antes desce para depois dela', () => {
    store.addUserMessage('cria três etiquetas');
    const tardia = store.addUserMessage('e mais uma');
    store.addAssistantMessage({
      content: 'Criei as três.',
      antesDosPedidos: ['p2'],
    });

    store.marcarJunto(tardia.id, 'p2');

    expect(store.messages.map(m => m.message.content)).toEqual([
      'cria três etiquetas',
      'Criei as três.',
      'e mais uma',
    ]);
    expect(store.textoDosPedidos(['p2'])).toBe('e mais uma');
  });

  it('a ação sem desfazer volta aguardando, ou com o desfecho que teve', () => {
    const acao = {
      nome: 'DELETE inboxes/1',
      dados: {},
      descricao: { frase: 'Apagar.' },
    };
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ acao }),
          turno({
            pedido_id: 'p2',
            acao,
            acao_estado: 'feita',
            acao_resultado: 'Pronto.',
          }),
        ],
      },
      avisos
    );

    expect(store.messages[1].acaoEstado).toBe('aguardando');
    expect(store.messages[3]).toEqual(
      expect.objectContaining({ acaoEstado: 'feita', acaoResultado: 'Pronto.' })
    );
  });

  it('a foto volta pelo nome, sem miniatura, e o que espera no campo fica', () => {
    const esperando = store.addArquivo('nova.pdf');
    store.hidratar(
      {
        id: 1,
        turnos: [turno({ anexos: [{ nome: 'print.png', tipo: 'imagem' }] })],
      },
      avisos
    );

    expect(store.messages[0].anexos).toEqual([
      expect.objectContaining({
        nome: 'print.png',
        tipo: 'imagem',
        previa: null,
      }),
    ]);
    expect(store.arquivosPendentes().map(item => item.id)).toEqual([esperando]);
  });

  // #3158 — o gráfico do relatório volta ao reabrir a conversa, nos três
  // desfechos: o número veio da ferramenta, não do modelo.
  it('os gráficos do turno voltam na resposta pronta, retida e com falha', () => {
    const graficos = [
      {
        id: '1',
        modo: 'serie',
        titulo: 'Conversas por dia',
        barras: [{ rotulo: '01/10', valor: 3 }],
      },
    ];
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ graficos }),
          turno({ pedido_id: 'p2', status: 'retido', graficos }),
          turno({ pedido_id: 'p3', status: 'failed', graficos }),
          turno({ pedido_id: 'p4' }),
        ],
      },
      avisos
    );

    const respostas = store.messages.filter(
      m => m.message_type === 'assistant'
    );
    expect(respostas.slice(0, 3).map(m => m.graficos)).toEqual([
      graficos,
      graficos,
      graficos,
    ]);
    expect(respostas[3].graficos).toEqual([]);
  });

  // #3158 (B8b) — a revisão de conversas volta ao reabrir a conversa, nos três
  // desfechos: ela começou e gasta mesmo quando o turno não teve texto.
  it('a revisão do turno volta na resposta pronta, retida e com falha', () => {
    const revisao = { id: 3, status: 'rodando' };
    store.hidratar(
      {
        id: 1,
        turnos: [
          turno({ revisao }),
          turno({ pedido_id: 'p2', status: 'retido', revisao }),
          turno({ pedido_id: 'p3', status: 'failed', revisao }),
          turno({ pedido_id: 'p4' }),
        ],
      },
      avisos
    );

    const respostas = store.messages.filter(
      m => m.message_type === 'assistant'
    );
    expect(respostas.map(m => m.revisao)).toEqual([
      revisao,
      revisao,
      revisao,
      null,
    ]);
  });

  it('"Nova conversa" esquece a conversa guardada', () => {
    store.hidratar({ id: 4, turnos: [turno()] }, avisos);

    store.reset();

    expect(store.conversaAtual()).toBeNull();
    expect(store.messages).toHaveLength(0);
  });

  // lote10 — a pergunta pendente (#859) é da conversa que estava na tela: abrir
  // outra conversa guardada não deixa a resposta velha entrar nela.
  it('abrir outra conversa solta a pergunta que esperava resposta', () => {
    const chave = store.abrirPendente(1, 'painel');
    store.registrarPedidoPendente(chave, 'p0');

    store.hidratar({ id: 4, turnos: [turno()] }, avisos);

    expect(store.pendente()).toBeNull();
    expect(store.pendenteAtivo(chave)).toBe(false);
  });
});
