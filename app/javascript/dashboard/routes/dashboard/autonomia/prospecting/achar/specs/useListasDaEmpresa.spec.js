import { ref } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { useListasDaEmpresa } from '../composables/useListasDaEmpresa';

// #2775 — F6: na gaveta, "Está na lista X · Tirar" e, depois, "Desfazer".
const montar = ({ podeLista = true } = {}) => {
  const fonte = {
    listasDaEmpresa: vi.fn().mockResolvedValue([
      { id: 4, nome: 'Padarias', enviada: false },
      { id: 5, nome: 'Antiga', enviada: true },
    ]),
    tirarDaLista: vi.fn().mockResolvedValue({ tirados: [9] }),
    devolverNaLista: vi.fn().mockResolvedValue({}),
  };
  const listas = useListasDaEmpresa({
    fonte: ref(fonte),
    empresaId: () => 3,
    podeLista: ref(podeLista),
  });
  return { fonte, listas };
};

describe('useListasDaEmpresa', () => {
  it('lê as listas da empresa ao abrir a gaveta', async () => {
    const { fonte, listas } = montar();
    await flushPromises();

    expect(fonte.listasDaEmpresa).toHaveBeenCalledWith(3);
    expect(listas.listas.value.map(lista => lista.nome)).toEqual([
      'Padarias',
      'Antiga',
    ]);
  });

  it('sem a permissão de guardar listas, não pede nada', async () => {
    const { fonte, listas } = montar({ podeLista: false });
    await flushPromises();

    expect(fonte.listasDaEmpresa).not.toHaveBeenCalled();
    expect(listas.listas.value).toEqual([]);
  });

  it('tirar grava pelo lead e Desfazer devolve pelo contato tirado', async () => {
    const { fonte, listas } = montar();
    await flushPromises();

    await listas.tirar(listas.listas.value[0]);
    expect(fonte.tirarDaLista).toHaveBeenCalledWith({
      listaId: 4,
      empresaIds: [3],
    });
    expect(listas.listas.value.map(lista => lista.id)).toEqual([5]);
    expect(listas.saida.value).toMatchObject({
      lista: { id: 4 },
      contatoIds: [9],
    });

    await listas.desfazer();
    expect(fonte.devolverNaLista).toHaveBeenCalledWith({
      listaId: 4,
      contatoIds: [9],
    });
    expect(listas.saida.value).toBeNull();
    expect(listas.listas.value.map(lista => lista.id)).toEqual([5, 4]);
  });

  it('falha ao tirar mostra o erro e não some com a lista', async () => {
    const { fonte, listas } = montar();
    await flushPromises();
    fonte.tirarDaLista.mockRejectedValue(new Error('x'));

    await listas.tirar(listas.listas.value[0]);

    expect(listas.erro.value).toBe('TIRAR');
    expect(listas.listas.value).toHaveLength(2);
  });

  // Revisão do #2775, item 12: a lista virou "já enviada" com a gaveta aberta.
  it('lista que virou enviada: frase própria e as listas lidas de novo', async () => {
    const { fonte, listas } = montar();
    await flushPromises();
    fonte.tirarDaLista.mockRejectedValue(
      Object.assign(new Error('x'), {
        codigo: 'prospecting.audience.audience_locked',
      })
    );
    fonte.listasDaEmpresa.mockResolvedValue([
      { id: 4, nome: 'Padarias', enviada: true },
      { id: 5, nome: 'Antiga', enviada: true },
    ]);

    await listas.tirar(listas.listas.value[0]);

    expect(listas.erro.value).toBe('ENVIADA');
    expect(fonte.listasDaEmpresa).toHaveBeenCalledTimes(2);
    expect(listas.listas.value[0]).toMatchObject({ id: 4, enviada: true });
  });
});
