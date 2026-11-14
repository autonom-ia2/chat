import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ColunasDosSeguros from '../../components/carteira/trazer/ColunasDosSeguros.vue';
import {
  SITUACAO_DA_COLUNA,
  chaveDoDestino,
} from '../../carteira/segurosDaPlanilha';

// #2897 — a lista "onde está cada coisa do seguro"
// (components/carteira/trazer/ColunasDosSeguros.vue): uma linha por coisa do
// seguro, com a coluna da planilha ao lado. A peça não grava nada: a escolha
// sobe para o Conferir.
withFullI18n('pt_BR');

const { CONFIRMADA, SUGERIDA, FALTA, OPCIONAL } = SITUACAO_DA_COLUNA;
const linha = (destino, situacao, coluna, obrigatorio = true) => ({
  destino,
  chave: chaveDoDestino(destino),
  obrigatorio,
  situacao,
  coluna,
});
const LINHAS = [
  linha('seguro_numero', CONFIRMADA, 3),
  linha('seguro_seguradora', SUGERIDA, 4),
  linha('seguro_termina', FALTA, null),
  linha('seguro_bem', OPCIONAL, null, false),
];
const COLUNAS = [
  { indice: 3, nome: 'Apólice' },
  { indice: 4, nome: 'Cia' },
  { indice: 5, nome: '' },
];

let aberta;
const abrir = (props = {}) => {
  aberta = mount(ColunasDosSeguros, {
    attachTo: document.body,
    props: { linhas: LINHAS, colunas: COLUNAS, ...props },
  });
  return aberta;
};
const linhaDo = (w, destino) => w.get(`[data-destino="${destino}"]`);
const campoDo = (w, destino) => linhaDo(w, destino).get('[role="combobox"]');

beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  aberta?.unmount();
  aberta = null;
  document.body.innerHTML = '';
});

describe('onde está cada coisa do seguro', () => {
  it('cada linha tem o nome da coisa, o que a tela sabe dela e a coluna escolhida', () => {
    const w = abrir();

    expect(w.get('ul').attributes('aria-label')).toBe(
      'Onde está cada coisa do seguro'
    );
    const frases = Object.fromEntries(
      w
        .findAll('li[data-destino]')
        .map(item => [
          item.attributes('data-destino'),
          item.get('[data-carteira="situacao-da-coluna"]').text(),
        ])
    );
    expect(frases).toEqual({
      seguro_numero: 'Já está guardada.',
      seguro_seguradora: 'Foi a coluna que achei. Confira.',
      seguro_termina: 'Não achei. Escolha a coluna.',
      seguro_bem: 'Não achei. Se a planilha não tiver, pode deixar assim.',
    });
    expect(campoDo(w, 'seguro_numero').text()).toContain('Apólice');
    expect(campoDo(w, 'seguro_termina').text()).toContain('Escolha a coluna');
  });

  it('o campo de cada linha tem nome próprio e é descrito pela frase da linha', () => {
    const w = abrir();
    const campo = campoDo(w, 'seguro_seguradora');

    expect(campo.attributes('aria-label')).toBe(
      'Coluna da planilha com: Seguradora'
    );
    const frase = linhaDo(w, 'seguro_seguradora').get(
      '[data-carteira="situacao-da-coluna"]'
    );
    expect(campo.attributes('aria-describedby')).toBe(frase.attributes('id'));
    // O rótulo visível leva ao campo.
    expect(linhaDo(w, 'seguro_seguradora').get('label').attributes('for')).toBe(
      campo.attributes('id')
    );
  });

  it('a coluna sem título na planilha é oferecida pela posição dela', () => {
    const w = abrir();

    const opcoes = linhaDo(w, 'seguro_termina')
      .findAll('[role="option"]')
      .map(opcao => opcao.text());

    expect(opcoes).toEqual(['Apólice', 'Cia', 'Coluna 6']);
  });

  it('a escolha sobe com o destino e a coluna, e nada é gravado aqui', async () => {
    const w = abrir();

    await campoDo(w, 'seguro_termina').trigger('click');
    await flushPromises();
    await linhaDo(w, 'seguro_termina')
      .get('[role="option"][data-value="5"]')
      .trigger('click');

    expect(w.emitted('apontar')).toEqual([['seguro_termina', 5]]);
  });

  it('o destino que o Conferir disse que falta fica marcado e aponta o alerta', () => {
    const w = abrir({ faltam: ['seguro_termina'], idDoAlerta: 'alerta-1' });

    const falta = campoDo(w, 'seguro_termina');
    expect(falta.attributes('aria-invalid')).toBe('true');
    expect(falta.attributes('aria-describedby')).toBe('alerta-1');
    expect(
      campoDo(w, 'seguro_numero').attributes('aria-invalid')
    ).toBeUndefined();
  });

  it('enquanto uma escrita anda, os campos esperam', () => {
    const w = abrir({ ocupado: true });

    w.findAll('[role="combobox"]').forEach(campo =>
      expect(campo.attributes('disabled')).toBeDefined()
    );
  });
});
