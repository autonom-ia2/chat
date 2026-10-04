import { defineComponent, h, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { declararContexto, contextoAtual } from '../useContextoDaTela';

// #934 — a tela declara o que a pessoa tem aberto, selecionado e filtrado; o
// painel do Guia lê isso na hora de perguntar.
const ROTA = { name: 'crm_kanban_index' };

const telaQueDeclara = fontes =>
  mount(
    defineComponent({
      setup() {
        declararContexto(fontes);
        return () => h('div');
      },
    })
  );

describe('useContextoDaTela', () => {
  let wrapper;

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  it('sem declaração, manda só a rota', () => {
    expect(contextoAtual(ROTA)).toEqual({ rota: 'crm_kanban_index' });
  });

  it('lê aberto, seleção e filtros da tela, acompanhando o que muda', () => {
    const selecionados = ref([881, 882]);
    wrapper = telaQueDeclara({
      aberto: () => [{ recurso: 'crm/cards', id: 881 }],
      selecionados: () => ({ recurso: 'crm/cards', ids: selecionados.value }),
      filtros: ref({ pipeline_id: 3, stageIds: [7], status: 'open' }),
    });

    expect(contextoAtual(ROTA)).toEqual({
      rota: 'crm_kanban_index',
      aberto: [{ recurso: 'crm/cards', id: 881 }],
      selecionados: { recurso: 'crm/cards', ids: [881, 882], total: 2 },
      filtros: { pipeline_id: 3, stageIds: [7], status: 'open' },
    });

    selecionados.value = [881, 882, 883];
    expect(contextoAtual(ROTA).selecionados.total).toBe(3);
  });

  it('limpa a declaração quando a tela sai', () => {
    wrapper = telaQueDeclara({
      selecionados: () => ({ recurso: 'contacts', ids: [5] }),
    });

    wrapper.unmount();
    wrapper = null;

    expect(contextoAtual(ROTA)).toEqual({ rota: 'crm_kanban_index' });
  });

  it('deixa fora o vazio, o que não é id e o que passa dos tetos', () => {
    wrapper = telaQueDeclara({
      aberto: [1, 2, 3, 4, 'x'].map(id => ({ recurso: 'crm/cards', id })),
      selecionados: {
        recurso: 'conversations',
        ids: Array.from({ length: 60 }, (_, i) => i + 1),
      },
      filtros: {
        search: '',
        ownerId: null,
        labelIds: [],
        nested: { a: 1 },
        result: 'open',
      },
    });

    const tela = contextoAtual(ROTA);
    expect(tela.aberto.map(item => item.id)).toEqual([1, 2, 3]);
    expect(tela.selecionados.ids).toHaveLength(50);
    expect(tela.selecionados.total).toBe(60);
    expect(tela.filtros).toEqual({ result: 'open' });
  });

  it('sem nada selecionado, não manda seleção', () => {
    wrapper = telaQueDeclara({
      selecionados: () => ({ recurso: 'contacts', ids: [] }),
    });

    expect(contextoAtual(ROTA)).toEqual({ rota: 'crm_kanban_index' });
  });
});
