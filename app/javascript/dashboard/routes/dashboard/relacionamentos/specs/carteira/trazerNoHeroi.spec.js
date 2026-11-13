import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import HeroiDeSeguros from '../../components/carteira/HeroiDeSeguros.vue';
import pt from 'dashboard/i18n/locale/pt_BR/relacionamentosCarteira.json';
import en from 'dashboard/i18n/locale/en/relacionamentosCarteira.json';
import { daCarteira } from './apoio';

// #2897 — o botão de trazer seguros no herói da aba Seguros: só para quem pode
// trazer lista. Na carteira vazia ele é a ação principal; com seguros, fica
// ao lado da ação da frase do dia. E o catálogo de textos do trazer com
// seguros, que não fala de IA, de custo nem de limite.
withFullI18n('pt_BR');

const SEM_SEGUROS = { total: 0, vence7: 0 };
const COM_SEGUROS = { total: 12, vence7: 0 };

const montar = props => mount(HeroiDeSeguros, { props });

describe('trazer seguros no herói', () => {
  it('na carteira vazia é o único botão: "Trazer meus seguros"', async () => {
    const w = montar({ resumo: SEM_SEGUROS, podeTrazer: true });

    expect(w.find(daCarteira('heroi-acao')).exists()).toBe(false);
    const trazer = w.get(daCarteira('heroi-trazer'));
    expect(trazer.text()).toBe('Trazer meus seguros');
    expect(trazer.attributes('disabled')).toBeUndefined();

    await trazer.trigger('click');

    expect(w.emitted('trazer')).toHaveLength(1);
  });

  it('com seguros fica ao lado da ação principal: "Trazer seguros"', async () => {
    const w = montar({ resumo: COM_SEGUROS, podeTrazer: true });

    expect(w.findAll(daCarteira('heroi-acao'))).toHaveLength(1);
    const trazer = w.get(daCarteira('heroi-trazer'));
    expect(trazer.text()).toBe('Trazer seguros');

    await trazer.trigger('click');

    expect(w.emitted('trazer')).toHaveLength(1);
    expect(w.emitted('verGrupo')).toBeUndefined();
  });

  it.each([
    ['vazia', SEM_SEGUROS],
    ['com seguros', COM_SEGUROS],
  ])('quem não pode trazer lista não vê o botão (carteira %s)', (_, resumo) => {
    const w = montar({ resumo });

    expect(w.find(daCarteira('heroi-trazer')).exists()).toBe(false);
    expect(w.text()).not.toContain('Trazer');
  });
});

describe('o catálogo do trazer com seguros', () => {
  // Todas as frases de uma seção do catálogo, em qualquer profundidade.
  const frasesDe = secao =>
    Object.values(secao).flatMap(valor =>
      typeof valor === 'string' ? [valor] : frasesDe(valor)
    );
  const palavrasDe = (frases, idioma) => {
    const separador = new Intl.Segmenter(idioma, { granularity: 'word' });
    return frases.flatMap(frase =>
      [...separador.segment(frase)]
        .filter(parte => parte.isWordLike)
        .map(parte => parte.segment.toLowerCase())
    );
  };

  it.each([
    ['pt-BR', pt, ['ia', 'inteligência', 'custo', 'limite', 'tokens']],
    ['en', en, ['ai', 'intelligence', 'cost', 'limit', 'tokens']],
  ])(
    'em %s não fala de IA, de custo nem de limite',
    (idioma, catalogo, fora) => {
      const frases = frasesDe(catalogo.RELACIONAMENTOS_CARTEIRA.TRAZER);
      const palavras = palavrasDe(frases, idioma);

      expect(frases.length).toBeGreaterThan(0);
      fora.forEach(palavra => expect(palavras).not.toContain(palavra));
    }
  );

  it('pt_BR e en têm as mesmas chaves', () => {
    const chavesDe = (secao, prefixo = '') =>
      Object.entries(secao).flatMap(([chave, valor]) =>
        typeof valor === 'string'
          ? [`${prefixo}${chave}`]
          : chavesDe(valor, `${prefixo}${chave}.`)
      );

    expect(chavesDe(en.RELACIONAMENTOS_CARTEIRA.TRAZER)).toEqual(
      chavesDe(pt.RELACIONAMENTOS_CARTEIRA.TRAZER)
    );
  });
});
