import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import HistoricoDeListas from '../../components/trazer/HistoricoDeListas.vue';
// #2894 — "Listas que você já trouxe": o título e o Desfazer, que só a lista
// pronta tem, por mais antiga que seja.
// #2896 — o Desfazer só aparece quando a conta tem (`temDesfazer`) e o
// servidor diz que aquela lista pode ser desfeita (`podeDesfazer`), seja qual
// for a situação dela; e os dois botões da linha têm 44 px de altura (alvo de
// toque). A lista que está sendo desfeita diz "Desfazendo…".
// O desfazer que travou não tem selo: a linha diz "O desfazer parou no meio."
// embaixo do nome, e o botão vira "Continuar". A frase do problema (esta e a
// da lista que não foi trazida) fica no bloco da esquerda; à direita, só o
// selo e os botões.
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
    // 15h UTC: o dia é o mesmo em qualquer fuso em que o teste rode.
    quando: Date.UTC(2020, 0, 1, 15),
    quem: 'Marina Dornelaz',
    total: 5,
    situacao,
    porcentagem: 100,
    ...extra,
  });
  const PODE = { podeDesfazer: true };
  const PAROU = 'O desfazer parou no meio.';
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

  // O desfazer travou no servidor: não está acontecendo nada, então o selo
  // "Desfazendo…" sai. A linha diz que parou e o botão vira "Continuar".
  it('a lista cujo desfazer travou não diz "Desfazendo…": diz que parou e tem "Continuar", que emite a lista', async () => {
    const travada = lista('a', 'desfazendo', PODE);
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [travada] },
    });
    expect(w.find('[data-lista="a"] span[data-situacao]').exists()).toBe(false);
    expect(w.text()).not.toContain('Desfazendo…');
    const frase = w.get('[data-relacionamentos="desfazer-parou"]');
    expect(frase.text()).toBe(PAROU);
    expect(frase.attributes('data-situacao')).toBe('desfazendo');
    // Quem anuncia a frase é o bloco que já estava na tela quando ela chega.
    expect(frase.attributes('aria-live')).toBeUndefined();
    expect(frase.element.parentElement.getAttribute('aria-live')).toBe(
      'polite'
    );
    expect(frase.classes()).toEqual(
      expect.arrayContaining(['text-sm', 'font-medium', 'text-n-amber-11'])
    );
    const botoes = w.findAll('button');
    expect(botoes.map(b => b.text())).toEqual(['Continuar']);
    expect(botoes[0].attributes('aria-label')).toBe(
      'Continuar a desfazer a lista a.xlsx'
    );
    expect(botoes[0].attributes('disabled')).toBeUndefined();
    expect(botoes[0].classes()).toContain('min-h-11');
    // Azul: é a ação principal da linha.
    expect(botoes[0].classes()).toContain('text-n-blue-11');
    expect(w.find('[role="alert"]').exists()).toBe(false);
    await w.get('[data-relacionamentos="desfazer"]').trigger('click');
    expect(w.emitted('desfazer')).toEqual([[travada]]);
  });

  // "Continuar" é só da linha travada: nas outras o botão diz "Desfazer", cinza.
  it.each([
    ['pronto', {}],
    ['falhou', { podeTentar: true }],
  ])(
    'a lista "%s" que pode ser desfeita tem "Desfazer", cinza',
    (situacao, extra) => {
      const w = mount(HistoricoDeListas, {
        props: {
          temDesfazer: true,
          listas: [lista('a', situacao, { ...extra, ...PODE })],
        },
      });
      const botao = w.get('[data-relacionamentos="desfazer"]');
      expect(botao.text()).toBe('Desfazer');
      expect(botao.attributes('aria-label')).toBe('Desfazer a lista a.xlsx');
      expect(botao.classes()).toContain('text-n-slate-12');
      expect(botao.classes()).not.toContain('text-n-blue-11');
    }
  );

  it('a frase de que o desfazer parou só aparece nesse estado', () => {
    const w = mount(HistoricoDeListas, {
      props: {
        temDesfazer: true,
        listas: [
          lista('andando', 'desfazendo'),
          lista('pronta', 'pronto', PODE),
          lista('parada', 'falhou', { podeTentar: true, ...PODE }),
          lista('desfeita', 'desfeito'),
          lista('entrando', 'trazendo'),
        ],
      },
    });
    expect(w.find('[data-relacionamentos="desfazer-parou"]').exists()).toBe(
      false
    );
    expect(w.text()).not.toContain(PAROU);
  });

  // Sem o Desfazer na conta não há botão para continuar: a lista travada fica
  // como a que está sendo desfeita, só com o selo.
  it('sem o Desfazer na conta, a lista travada fica só com o selo "Desfazendo…", sem frase nem botão', () => {
    const w = mount(HistoricoDeListas, {
      props: { listas: [lista('a', 'desfazendo', PODE)] },
    });
    expect(w.find('[data-relacionamentos="desfazer-parou"]').exists()).toBe(
      false
    );
    expect(w.get('[data-lista="a"] span[data-situacao]').text()).toBe(
      'Desfazendo…'
    );
    expect(w.findAll('button')).toHaveLength(0);
  });

  // Leitor de tela: a troca "Desfazendo…" → "Desfeito" é anunciada. A lista
  // que está entrando muda de porcentagem a cada consulta: essa não anuncia.
  it.each([
    ['pronto', 'polite'],
    ['desfazendo', 'polite'],
    ['desfeito', 'polite'],
    ['trazendo', 'off'],
  ])('o selo da lista "%s" tem aria-live "%s"', (situacao, anuncio) => {
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [lista('a', situacao)] },
    });
    expect(w.get('[data-situacao]').attributes('aria-live')).toBe(anuncio);
  });

  it('a troca de "Desfazendo…" para "Desfeito" acontece no mesmo selo (é o que o leitor de tela anuncia)', async () => {
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [lista('a', 'desfazendo')] },
    });
    const selo = w.get('[data-situacao]').element;
    await w.setProps({ listas: [lista('a', 'desfeito')] });
    expect(w.get('[data-situacao]').element).toBe(selo);
    expect(selo.textContent.trim()).toBe('Desfeito');
    expect(selo.getAttribute('aria-live')).toBe('polite');
  });

  it('a frase do desfazer que travou também fica no bloco do texto, a terceira linha dele', () => {
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [lista('a', 'desfazendo', PODE)] },
    });
    const [texto, grupo] = [...w.get('[data-lista="a"]').element.children];
    expect([...texto.children].map(linha => linha.textContent.trim())).toEqual([
      'a.xlsx',
      'em 01/01 · por Marina Dornelaz · 5 pessoas',
      PAROU,
    ]);
    expect(grupo.querySelector('[data-situacao]')).toBeNull();
    expect(grupo.querySelectorAll('button')).toHaveLength(1);
  });

  // Depois de desfazer, o botão da linha some: a tela leva o foco à linha.
  it('a linha da lista pode receber o foco, sem entrar na ordem do Tab', () => {
    const w = mount(HistoricoDeListas, {
      props: { temDesfazer: true, listas: [lista('a', 'desfazendo')] },
      attachTo: document.body,
    });
    const linha = w.get('[data-lista="a"]');
    expect(linha.attributes('tabindex')).toBe('-1');
    linha.element.focus();
    expect(document.activeElement).toBe(linha.element);
    w.unmount();
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
      const frase = w.get('[data-situacao="falhou"]');
      expect(frase.text()).toBe('Não consegui trazer esta lista.');
      expect(frase.classes()).toEqual(
        expect.arrayContaining(['text-sm', 'font-medium', 'text-n-ruby-11'])
      );
      // A lista que falhou não tem selo: só a frase.
      expect(w.find('[data-lista="a"] span[data-situacao]').exists()).toBe(
        false
      );
      const botoes = w.findAll('[data-lista="a"] button');
      expect(botoes.map(b => b.text())).toEqual(['Tentar de novo', 'Desfazer']);
      botoes.forEach(b => expect(b.attributes('disabled')).toBeUndefined());
      expect(botoes[1].attributes('aria-label')).toBe(
        'Desfazer a lista a.xlsx'
      );
      // "Tentar de novo" é a ação principal da linha que falhou: azul.
      expect(botoes[0].classes()).toContain('text-n-blue-11');
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

    // O bloco dos botões não espreme o do texto: o da esquerda fica com o
    // espaço que sobra e o da direita não encolhe.
    it('a frase fica no bloco do texto, a terceira linha dele; o dos botões não o espreme', () => {
      const w = montar();
      const [texto, grupo] = [...w.get('[data-lista="a"]').element.children];
      expect([...texto.classList]).toEqual(
        expect.arrayContaining(['flex', 'flex-col', 'flex-1', 'min-w-0'])
      );
      expect([...grupo.classList]).toEqual(
        expect.arrayContaining(['shrink-0', 'sm:justify-end'])
      );
      expect(
        [...texto.children].map(linha => linha.textContent.trim())
      ).toEqual([
        'a.xlsx',
        'em 01/01 · por Marina Dornelaz · 5 pessoas',
        'Não consegui trazer esta lista.',
      ]);
      expect(grupo.querySelector('[data-situacao]')).toBeNull();
      expect(texto.children[1].classList.contains('tabular-nums')).toBe(true);
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
