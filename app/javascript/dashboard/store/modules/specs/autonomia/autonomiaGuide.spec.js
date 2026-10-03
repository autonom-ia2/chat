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
