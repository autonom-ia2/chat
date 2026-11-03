import { mount } from '@vue/test-utils';
import LivreTexto from '../components/LivreTexto.vue';

// #2486 — o dado de um campo que a conta apagou fica no texto, marcado, com o
// aviso no painel; não volta para a lista do "Pôr um dado".
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) => (valores ? `${chave} ${valores.dado}` : chave),
  }),
}));

const CATALOGO = {
  valores: [
    { caminho: 'contato.nome', frase: 'NOME' },
    {
      caminho: 'contato.atributos',
      atributos: 'contact_attribute',
      frase: 'ATRIB',
    },
  ],
};

const montar = modelValue =>
  mount(LivreTexto, {
    props: {
      rotulo: 'TEXTO',
      modelValue,
      catalogo: CATALOGO,
      atributosDo: () => [],
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        TextArea: {
          props: ['modelValue'],
          template: '<textarea :value="modelValue" />',
        },
        ChoiceSelect: {
          props: ['options'],
          template: '<div data-opcoes>{{ options.map(o => o.label) }}</div>',
        },
      },
    },
  });

describe('LivreTexto', () => {
  it('campo apagado aparece marcado, com aviso, e fica fora do "Pôr um dado"', () => {
    const wrapper = montar(['Placa: ', { $valor: 'contato.atributos.placa' }]);

    expect(wrapper.find('textarea').element.value).toContain(
      '[AUTOMACAO_LIVRE.ALTERAR_PAINEL.DADO_APAGADO'
    );
    expect(wrapper.find('[data-dado-apagado]').exists()).toBe(true);
    expect(wrapper.find('[data-opcoes]').text()).not.toContain('DADO_APAGADO');
  });

  it('sem dado apagado, sem aviso', () => {
    const wrapper = montar(['Oi ', { $valor: 'contato.nome' }]);

    expect(wrapper.find('textarea').element.value).toBe('Oi [NOME]');
    expect(wrapper.find('[data-dado-apagado]').exists()).toBe(false);
  });
});
