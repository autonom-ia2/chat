import { mount } from '@vue/test-utils';
import LivreWebhookCorpo from '../components/LivreWebhookCorpo.vue';

// G13 (#2670) — o corpo que o Guia montou abre inteiro no editor: texto fixo
// em caixa de texto, dado do cliente na escolha, e a forma que a tela não
// edita fica como está, sem sumir.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));
vi.mock('../texto', () => ({ opcoesDosValores: () => [] }));

const corpoDoGuia = {
  plano: 'anual',
  valor: 100,
  itens: ['a', 'b'],
  cnpj: { $valor: 'card.atributos.cnpj' },
};

const montar = (modelValue = corpoDoGuia) =>
  mount(LivreWebhookCorpo, {
    props: { rotulo: 'Corpo', modelValue, catalogo: {}, atributosDo: () => [] },
    global: {
      mocks: { $t: chave => chave },
      stubs: {
        ChoiceSelect: { props: ['modelValue'], template: '<div />' },
        Button: { template: '<button />' },
      },
    },
  });

describe('LivreWebhookCorpo', () => {
  it('abre o texto fixo, o dado e a forma do Guia sem perder nada', () => {
    const wrapper = montar();
    const textos = wrapper.findAll('[data-texto-fixo]');
    expect(textos.map(caixa => caixa.element.value)).toEqual(['anual', '100']);
    expect(wrapper.findAll('[data-linha-do-guia]')).toHaveLength(1);
    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
  });

  it('editar o texto fixo muda só aquela linha', async () => {
    const wrapper = montar();
    await wrapper.findAll('[data-texto-fixo]')[0].setValue('mensal');
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
      ...corpoDoGuia,
      plano: 'mensal',
    });
  });

  it('texto fixo apagado segura o salvar', async () => {
    const wrapper = montar({ plano: 'anual' });
    await wrapper.find('[data-texto-fixo]').setValue('');
    // A marca '' no corpo segura o "Salvar" (corpoDasLinhas).
    expect(wrapper.emitted('update:modelValue').at(-1)[0]).toEqual({
      plano: '',
      '': null,
    });
  });
});
