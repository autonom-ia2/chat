import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
// #2894 — "Listas que você já trouxe": o título e o Desfazer, que só a lista
// pronta tem, por mais antiga que seja.
// #2896 — o Desfazer só aparece quando a conta tem (`temDesfazer`) e o
// servidor diz que aquela lista pode ser desfeita (`podeDesfazer`), seja qual
// for a situação dela; e os dois botões da linha têm 44 px de altura (alvo de
// toque). A lista que está sendo desfeita diz "Desfazendo…".
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
  const lista = (id, situacao, extra = {}) => ({
    id,
    arquivo: `${id}.xlsx`,
    quando: Date.UTC(2020, 0, 1),
    quem: 'Marina Dornelaz',
    total: 5,
    situacao,
    porcentagem: 100,
    ...extra,
  });
  const PODE = { podeDesfazer: true };
  const temBotao = (w, id, nome = 'desfazer') =>
    w.find(`[data-lista="${id}"] [data-relacionamentos="${nome}"]`).exists();

  it('sem o Desfazer na conta, nem a lista que pode ser desfeita tem o botão', () => {
    const w = mount(HistoricoDeListas, {
      props: { listas: [lista('a', 'pronto', PODE), lista('b', 'trazendo')] },
    });
    expect(w.find('[data-relacionamentos="desfazer"]').exists()).toBe(false);
    expect(w.text()).not.toContain('Desfazer');
    expect(w.get('[data-lista="a"] [data-situacao]').text()).toBe('Pronto');
  });

  it('a lista pronta, por mais antiga que seja, tem Desfazer; trazendo e desfeita não', () => {
    const w = mount(HistoricoDeListas, {
      props: {
        temDesfazer: true,
        listas: [
          lista('a', 'pronto', PODE),
          lista('b', 'trazendo'),
          lista('c', 'desfeito'),
        ],
      },
    });
    expect(['a', 'b', 'c'].map(id => temBotao(w, id))).toEqual([
      true,
      false,
      false,
    ]);
    expect(w.text()).not.toContain('Prazo');
    expect(w.text()).not.toContain('até');
  });

  // Quem diz se dá para desfazer é o servidor (`podeDesfazer`), não a situação.
  it.each(['pronto', 'falhou', 'desfazendo'])(
    'a lista "%s" tem o botão quando o servidor diz que pode, e não tem quando ele diz que não',
    situacao => {
      const w = mount(HistoricoDeListas, {
        props: {
          temDesfazer: true,
          listas: [
            lista('pode', situacao, PODE),
            lista('nao-pode', situacao, { podeDesfazer: false }),
            lista('sem-dizer', situacao),
          ],
        },
      });
      expect(
        ['pode', 'nao-pode', 'sem-dizer'].map(id => temBotao(w, id))
      ).toEqual([true, false, false]);
    }
  );

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

  // O desfazer travou no servidor: o selo não muda e o botão volta, para a
  // pessoa pedir de novo. Sem frase de erro: o botão já é a saída.
  it('a lista cujo desfazer travou continua "Desfazendo…" e tem o botão, que emite a lista', async () => {
    const travada = lista('a', 'desfazendo', PODE);
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [travada] },
    });
    expect(w.get('[data-lista="a"] [data-situacao]').text()).toBe(
      'Desfazendo…'
    );
    expect(w.findAll('button').map(b => b.text())).toEqual(['Desfazer']);
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await w.get('[data-relacionamentos="desfazer"]').trigger('click');
    expect(w.emitted('desfazer')).toEqual([[travada]]);
  });

  // A lista que parou no meio depois de pôr gente: a pessoa escolhe continuar
  // ou desfazer. Um botão não esconde o outro.
  describe('a lista que parou no meio e pode ser desfeita', () => {
    const parada = lista('a', 'falhou', { podeTentar: true, ...PODE });
    const montar = () =>
      mount(HistoricoDeListas, {
        props: { temDesfazer: true, listas: [parada] },
      });

    it('tem a frase, "Tentar de novo" e "Desfazer", nesta ordem, os dois ligados', () => {
      const w = montar();
      expect(w.get('[data-situacao="falhou"]').text()).toBe(
        'Não consegui trazer esta lista.'
      );
      const botoes = w.findAll('[data-lista="a"] button');
      expect(botoes.map(b => b.text())).toEqual(['Tentar de novo', 'Desfazer']);
      botoes.forEach(b => expect(b.attributes('disabled')).toBeUndefined());
      expect(botoes[1].attributes('aria-label')).toBe(
        'Desfazer a lista a.xlsx'
      );
    });

    it('cada botão emite o seu pedido', async () => {
      const w = montar();
      await w.get('[data-relacionamentos="desfazer"]').trigger('click');
      await w.get('[data-relacionamentos="tentar-de-novo"]').trigger('click');
      expect(w.emitted('desfazer')).toEqual([[parada]]);
      expect(w.emitted('tentarDeNovo')).toEqual([[parada]]);
    });

    // Em tela estreita (390 px) a linha é uma coluna e os botões descem para a
    // linha de baixo quando não cabem ao lado da frase; cada um com 44 px.
    it('os dois botões têm 44 px de altura e ficam num grupo que quebra de linha', () => {
      const w = montar();
      const tentar = w.get('[data-relacionamentos="tentar-de-novo"]');
      const desfazer = w.get('[data-relacionamentos="desfazer"]');
      expect(tentar.classes()).toContain('min-h-11');
      expect(desfazer.classes()).toContain('min-h-11');
      const grupo = desfazer.element.parentElement;
      expect(tentar.element.parentElement).toBe(grupo);
      expect([...grupo.classList]).toEqual(
        expect.arrayContaining(['flex', 'flex-wrap', 'gap-3'])
      );
      expect([...w.get('[data-lista="a"]').element.classList]).toEqual(
        expect.arrayContaining(['flex-col', 'sm:flex-row'])
      );
    });

    it('enquanto tenta de novo, o Desfazer continua lá', () => {
      const w = mount(HistoricoDeListas, {
        props: { temDesfazer: true, listas: [parada], tentando: 'a' },
      });
      expect(temBotao(w, 'a')).toBe(true);
      expect(temBotao(w, 'a', 'tentar-de-novo')).toBe(true);
    });
  });

  it.each([
    ['Desfazer', 'desfazer', lista('a', 'pronto', PODE)],
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
