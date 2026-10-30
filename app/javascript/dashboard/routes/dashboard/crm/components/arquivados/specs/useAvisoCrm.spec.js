import {
  DURACAO_COM_ACAO,
  DURACAO_SIMPLES,
  avisar,
  desfazerPeloTeclado,
  executarAviso,
  limparAvisos,
  pausarAvisos,
  useAvisoCrm,
} from '../useAvisoCrm';

// #2095 item 12: aviso com ação fica 12 s, para de contar com o mouse ou o foco, e Ctrl+Z desfaz.
describe('useAvisoCrm', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    limparAvisos();
  });
  afterEach(() => vi.useRealTimers());

  const { avisos } = useAvisoCrm();

  it('aviso com ação fica 12 s; sem ação, 6 s', () => {
    avisar('com', { rotulo: 'Desfazer', executar: vi.fn() });
    avisar('sem');
    vi.advanceTimersByTime(DURACAO_SIMPLES);
    expect(avisos.value.map(a => a.mensagem)).toEqual(['com']);
    vi.advanceTimersByTime(DURACAO_COM_ACAO - DURACAO_SIMPLES);
    expect(avisos.value).toEqual([]);
  });

  it('pausado, não conta', () => {
    avisar('com', { rotulo: 'Desfazer', executar: vi.fn() });
    pausarAvisos(true);
    vi.advanceTimersByTime(DURACAO_COM_ACAO * 2);
    expect(avisos.value).toHaveLength(1);
    pausarAvisos(false);
    vi.advanceTimersByTime(DURACAO_COM_ACAO);
    expect(avisos.value).toHaveLength(0);
  });

  it('Ctrl+Z roda a ação de desfazer do último aviso, não a outra', () => {
    const desfazer = vi.fn();
    const ver = vi.fn();
    avisar('arquivado', [
      { rotulo: 'Desfazer', desfazer: true, executar: desfazer },
      { rotulo: 'Ver arquivados', executar: ver },
    ]);
    expect(desfazerPeloTeclado()).toBe(true);
    expect(desfazer).toHaveBeenCalledTimes(1);
    expect(ver).not.toHaveBeenCalled();
    expect(avisos.value).toHaveLength(0);
    expect(desfazerPeloTeclado()).toBe(false);
  });

  it('a segunda ação roda pelo índice e fecha o aviso', () => {
    const ver = vi.fn();
    const id = avisar('x', [
      { rotulo: 'Desfazer', desfazer: true, executar: vi.fn() },
      { rotulo: 'Ver', executar: ver },
    ]);
    executarAviso(id, 1);
    expect(ver).toHaveBeenCalledTimes(1);
    expect(avisos.value).toHaveLength(0);
  });

  it('guarda no máximo dois avisos', () => {
    avisar('1');
    avisar('2');
    avisar('3');
    expect(avisos.value.map(a => a.mensagem)).toEqual(['2', '3']);
  });
});
