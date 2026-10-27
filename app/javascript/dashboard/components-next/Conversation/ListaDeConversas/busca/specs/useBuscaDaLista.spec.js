import { nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import BuscaDaListaAPI from 'dashboard/api/buscaDaLista';
import { emitter } from 'shared/helpers/mitt';
import { useBuscaDaLista } from '../useBuscaDaLista';
import { BUSCA_DESATUALIZADA } from '../buscaDaLista';

vi.mock('dashboard/api/buscaDaLista', () => ({
  default: { buscar: vi.fn() },
}));

const resposta = payload => ({ data: { payload } });

describe('useBuscaDaLista (#2211)', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    BuscaDaListaAPI.buscar.mockReset();
    BuscaDaListaAPI.buscar.mockResolvedValue(
      resposta({
        conversations: [{ id: 1 }],
        messages: [],
        contacts: [],
        telefone_novo: null,
      })
    );
  });
  afterEach(() => vi.useRealTimers());

  it('espera 300 ms depois da última letra e busca uma vez', async () => {
    const busca = useBuscaDaLista();
    busca.texto.value = 'jo';
    await nextTick();
    busca.texto.value = 'joa';
    await nextTick();
    vi.advanceTimersByTime(299);
    expect(BuscaDaListaAPI.buscar).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    await flushPromises();
    expect(BuscaDaListaAPI.buscar).toHaveBeenCalledTimes(1);
    expect(BuscaDaListaAPI.buscar.mock.calls[0][0]).toBe('joa');
    expect(busca.resultado.value.conversas).toEqual([{ id: 1 }]);
    expect(busca.buscado.value).toBe('joa');
    expect(busca.carregando.value).toBe(false);
  });

  it('lê do servidor o e-mail novo e as caixas com texto livre (#2257)', async () => {
    BuscaDaListaAPI.buscar.mockResolvedValue(
      resposta({
        conversations: [],
        messages: [],
        contacts: [],
        telefone_novo: '+5511955554444',
        email_novo: null,
        texto_livre_nas_caixas: [1, 5],
      })
    );
    const busca = useBuscaDaLista();
    busca.texto.value = '11 95555-4444';
    await nextTick();
    vi.advanceTimersByTime(300);
    await flushPromises();
    expect(busca.resultado.value.textoLivreNasCaixas).toEqual([1, 5]);
    expect(busca.resultado.value.emailNovo).toBeNull();
  });

  it('servidor sem os campos novos: nada de e-mail, nenhuma caixa livre', async () => {
    const busca = useBuscaDaLista();
    busca.texto.value = 'jo';
    await nextTick();
    vi.advanceTimersByTime(300);
    await flushPromises();
    expect(busca.resultado.value.textoLivreNasCaixas).toEqual([]);
    expect(busca.resultado.value.emailNovo).toBeNull();
  });

  it('com 1 letra não busca e a lista volta', async () => {
    const busca = useBuscaDaLista();
    busca.texto.value = 'j';
    await nextTick();
    vi.advanceTimersByTime(500);
    expect(busca.ativa.value).toBe(false);
    expect(BuscaDaListaAPI.buscar).not.toHaveBeenCalled();
  });

  it('telefone só a partir de 4 dígitos', async () => {
    const busca = useBuscaDaLista();
    busca.texto.value = '11 9';
    await nextTick();
    expect(busca.ativa.value).toBe(false);
    busca.texto.value = '11 97';
    await nextTick();
    expect(busca.ativa.value).toBe(true);
  });

  it('cancela o pedido anterior quando o texto muda', async () => {
    let sinalDoPrimeiro;
    BuscaDaListaAPI.buscar.mockImplementationOnce((_q, { signal }) => {
      sinalDoPrimeiro = signal;
      return new Promise(() => {});
    });
    const busca = useBuscaDaLista();
    busca.texto.value = 'jo';
    await nextTick();
    vi.advanceTimersByTime(300);
    busca.texto.value = 'joana';
    await nextTick();
    vi.advanceTimersByTime(300);
    await flushPromises();
    expect(sinalDoPrimeiro.aborted).toBe(true);
    expect(busca.buscado.value).toBe('joana');
  });

  it('erro da rede vira erro na tela, e "Tentar de novo" busca outra vez', async () => {
    BuscaDaListaAPI.buscar.mockRejectedValueOnce(new Error('rede'));
    const busca = useBuscaDaLista();
    busca.texto.value = 'jo';
    await nextTick();
    vi.advanceTimersByTime(300);
    await flushPromises();
    expect(busca.erro.value).toBe(true);
    await busca.buscar();
    expect(busca.erro.value).toBe(false);
    expect(BuscaDaListaAPI.buscar).toHaveBeenCalledTimes(2);
  });

  it('limpar volta ao vazio', async () => {
    const busca = useBuscaDaLista();
    busca.texto.value = 'jo';
    await nextTick();
    vi.advanceTimersByTime(300);
    await flushPromises();
    busca.limpar();
    await nextTick();
    expect(busca.ativa.value).toBe(false);
    expect(busca.resultado.value.conversas).toEqual([]);
  });

  it('a conversa vazia enviou: a busca aberta refaz o pedido; a fechada não', async () => {
    emitter.all.clear();
    const busca = useBuscaDaLista();
    emitter.emit(BUSCA_DESATUALIZADA);
    expect(BuscaDaListaAPI.buscar).not.toHaveBeenCalled();

    busca.texto.value = '11 95555-4444';
    await nextTick();
    vi.advanceTimersByTime(300);
    await flushPromises();
    emitter.emit(BUSCA_DESATUALIZADA);
    await flushPromises();
    expect(BuscaDaListaAPI.buscar).toHaveBeenCalledTimes(2);
  });
});
