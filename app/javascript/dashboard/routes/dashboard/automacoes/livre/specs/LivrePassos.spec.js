import { mount } from '@vue/test-utils';
import LivrePassos from '../components/LivrePassos.vue';

// #2500 F7 — os galhos do "decidir" pela travessia única: um por caminho, com o
// nome que a pessoa deu ("Caminho N" enquanto não tem nome), e o "nenhum".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
  }),
}));

const CATALOGO = {
  gatilhos: [],
  operadores: [],
  unidades: [],
  valores: [],
  passos: [],
};

const montar = passos =>
  mount(LivrePassos, {
    props: { passos, listaId: 'raiz', catalogo: CATALOGO, podeMudar: true },
    global: { mocks: { $t: chave => chave }, stubs: { Button: true } },
  });

describe('LivrePassos com o decidir', () => {
  it('mostra um galho por caminho, com o nome ou o número, e o nenhum', () => {
    const wrapper = montar([
      {
        id: 'd1',
        tipo: 'decidir',
        caminhos: [
          { chave: 'sinistro', descricao: 'batida', passos: [] },
          { chave: '', descricao: 'preço', passos: [] },
        ],
        nenhum: [],
      },
    ]);

    const rotulos = wrapper
      .findAll('[data-galho]')
      .map(galho => galho.text().trim());
    expect(rotulos[0]).toContain('sinistro');
    expect(rotulos[1]).toContain('AUTOMACAO_LIVRE.RAMOS.CAMINHO {"n":2}');
    expect(rotulos[2]).toContain('AUTOMACAO_LIVRE.RAMOS.NENHUM');
  });
});
