import { computed, defineComponent } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { useModeloDaMensagem } from '../useModeloDaMensagem';

const botoes = texto => [
  { type: 'BUTTONS', buttons: [{ type: 'QUICK_REPLY', text: texto }] },
];
const MODELOS = [
  { name: 'promo', language: 'pt_BR', components: botoes('Quero') },
  { name: 'promo', language: 'en', components: botoes('I want it') },
  { name: 'boas_vindas', language: 'pt_BR', components: botoes('Oi') },
];

const textos = templateParams => {
  let resultado;
  const Componente = defineComponent({
    setup() {
      resultado = useModeloDaMensagem(
        computed(() => ({
          inboxId: 1,
          additionalAttributes: { templateParams },
        }))
      );
      return () => null;
    },
  });
  const store = createStore({
    getters: {
      'inboxes/getInbox': () => () => ({ message_templates: MODELOS }),
    },
  });
  const i18n = createI18n({ legacy: false, locale: 'en', missingWarn: false });
  mount(Componente, { global: { plugins: [store, i18n] } });
  return resultado.botoes.value.map(b => b.texto);
};

describe('useModeloDaMensagem (#1702)', () => {
  it('com idioma gravado, usa o modelo daquele idioma', () => {
    expect(textos({ name: 'promo', language: 'en' })).toEqual(['I want it']);
  });

  it('sem idioma (jornada de campanha), usa o modelo quando o nome tem um idioma só', () => {
    expect(textos({ name: 'boas_vindas' })).toEqual(['Oi']);
  });

  it('sem idioma e com o nome em vários idiomas, não mostra botões de outro idioma', () => {
    expect(textos({ name: 'promo' })).toEqual([]);
  });
});
