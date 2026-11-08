import { defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { useOrigemLeiga } from '../useOrigemLeiga';

// Sem mensagens: o t() devolve a própria chave, e o teste confere qual frase foi escolhida.
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: { pt_BR: {} },
});

const leiga = () => {
  let api;
  mount(
    defineComponent({
      setup() {
        api = useOrigemLeiga();
        return () => null;
      },
    }),
    { global: { plugins: [i18n] } }
  );
  return api;
};

describe('useOrigemLeiga: clique no anúncio que abre o Messenger e o Direct (#2620)', () => {
  it.each([
    ['meta_ctm', 'CRM_CARD.ORIGEM.FONTE.ANUNCIO_MESSENGER'],
    ['meta_ctd', 'CRM_CARD.ORIGEM.FONTE.ANUNCIO_DIRECT'],
  ])('%s diz o canal', (source, chave) => {
    const origem = leiga();
    const item = origem.daCampanha([
      {
        source,
        source_type: 'ad',
        source_id: '120255246077900416',
        ad_name: 'Seguro auto',
        touched_at: '2026-11-06T12:00:00Z',
      },
    ]);

    expect(origem.fonte(item)).toBe(chave);
  });

  it('quem não vê o anúncio fica com o canal, sem o nome do anúncio', () => {
    const origem = leiga();
    const item = origem.daCampanha([
      {
        source: 'meta_ctd',
        source_type: 'ad',
        ad_hidden: true,
        ad_name: 'Seguro auto',
        headline: 'Seguro auto',
        touched_at: '2026-11-06T12:00:00Z',
      },
    ]);

    expect(origem.fonte(item)).toBe('CRM_CARD.ORIGEM.FONTE.ANUNCIO_DIRECT');
    expect(origem.nome(item)).not.toContain('Seguro auto');
  });
});
