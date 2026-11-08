import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import OrigemAnuncioMeta from '../origem/OrigemAnuncioMeta.vue';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: {
    pt_BR: {
      CRM_CARD: {
        ORIGEM: {
          TELA: 'De onde veio',
          FORMULARIO_META:
            'Veio do formulário "{formulario}" · anúncio {anuncio}',
          FORMULARIO_META_GENERICO: 'Veio de um formulário de anúncio da Meta',
        },
      },
    },
  },
});
const montar = formulario =>
  mount(OrigemAnuncioMeta, {
    props: { formulario },
    global: { plugins: [i18n], stubs: { OrigemFormulario: true } },
  });

describe('OrigemAnuncioMeta (#2558)', () => {
  it('com o formulário e o anúncio, diz de onde veio', () => {
    const wrapper = montar({
      form_name: 'Orçamento',
      ad_name: 'Carrossel',
      fields: [{ key: 'city', value: 'Campinas' }],
    });
    expect(wrapper.text()).toContain(
      'Veio do formulário "Orçamento" · anúncio Carrossel'
    );
  });

  it('sem o formulário (quem não vê o anúncio), mostra a origem genérica', () => {
    const wrapper = montar({
      captured_at: '2026-11-01T12:00:00Z',
      fields: [{ key: 'city', value: 'Campinas' }],
    });
    expect(wrapper.text()).toContain(
      'Veio de um formulário de anúncio da Meta'
    );
    expect(wrapper.text()).not.toContain('undefined');
  });

  it('com o anúncio e sem o nome do formulário, não esconde o anúncio de quem pode ver', () => {
    const wrapper = montar({ ad_name: 'Carrossel', fields: [] });
    expect(wrapper.text()).toContain('anúncio Carrossel');
  });
});
