import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
// #2894 — "Listas que você já trouxe": o título e o Desfazer, que só a lista
// pronta tem, por mais antiga que seja.
// #2896 — o Desfazer só aparece quando a conta tem (`temDesfazer`); e os dois
// botões da linha têm 44 px de altura (alvo de toque). A lista que está sendo
// desfeita diz "Desfazendo…" e não tem botão.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

afterEach(() => {
  document.body.innerHTML = '';
});

describe('o título', () => {
  it('diz "Listas que você já trouxe"', () => {
    const w = mount(HistoricoDeListas, {
      props: { listas: [] },
    });
    expect(w.get('h2').text()).toBe('Listas que você já trouxe');
  });
});

describe('Desfazer sem prazo', () => {
  const lista = (id, situacao) => ({
    id,
    arquivo: `${id}.xlsx`,
    quando: Date.UTC(2020, 0, 1),
    quem: 'Marina Dornelaz',
    total: 5,
    situacao,
    porcentagem: 100,
  });

  it('sem o Desfazer na conta, nem a lista pronta tem o botão', () => {
    const w = mount(HistoricoDeListas, {
      props: { listas: [lista('a', 'pronto'), lista('b', 'trazendo')] },
    });
    expect(w.find('[data-relacionamentos="desfazer"]').exists()).toBe(false);
    expect(w.text()).not.toContain('Desfazer');
    expect(w.get('[data-lista="a"] [data-situacao]').text()).toBe('Pronto');
  });

  it('só a lista pronta tem Desfazer, por mais antiga que seja; trazendo e desfeita não', () => {
    const w = mount(HistoricoDeListas, {
      props: {
        temDesfazer: true,
        listas: [
          lista('a', 'pronto'),
          lista('b', 'trazendo'),
          lista('c', 'desfeito'),
        ],
      },
    });
    const tem = id =>
      w.find(`[data-lista="${id}"] [data-relacionamentos="desfazer"]`).exists();
    expect([tem('a'), tem('b'), tem('c')]).toEqual([true, false, false]);
    expect(w.text()).not.toContain('Prazo');
    expect(w.text()).not.toContain('até');
  });

  it('a lista sendo desfeita diz "Desfazendo…", como lista em andamento, e não tem botão', () => {
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [lista('a', 'desfazendo')] },
    });
    const selo = w.get('[data-lista="a"] [data-situacao="desfazendo"]');
    expect(selo.text()).toBe('Desfazendo…');
    // O mesmo selo da lista que está sendo trazida.
    expect(selo.classes()).toEqual(
      expect.arrayContaining(['bg-n-blue-3', 'text-n-blue-11'])
    );
    expect(w.find('[data-relacionamentos="desfazer"]').exists()).toBe(false);
    expect(w.findAll('button')).toHaveLength(0);
  });

  it.each([
    ['Desfazer', 'desfazer', lista('a', 'pronto')],
    [
      'Tentar de novo',
      'tentar-de-novo',
      { ...lista('b', 'falhou'), podeTentar: true },
    ],
  ])('"%s" tem 44 px de altura (alvo de toque)', (texto, nome, daLista) => {
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [daLista] },
    });
    const botao = w.get(`[data-relacionamentos="${nome}"]`);
    expect(botao.text()).toBe(texto);
    expect(botao.classes()).toContain('min-h-11');
  });
});
