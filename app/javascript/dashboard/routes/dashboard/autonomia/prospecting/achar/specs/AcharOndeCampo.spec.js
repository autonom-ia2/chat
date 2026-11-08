import { mount } from '@vue/test-utils';
import AcharOndeCampo from '../components/AcharOndeCampo.vue';

// #2696 — travado enquanto a IA lê a frase: a lista de sugestões fecha, e o
// campo e o "Alterar" ficam desligados.
const SUGESTOES = [
  { placeId: 'a', rotulo: 'Centro, Campinas' },
  { placeId: 'b', rotulo: 'Centro, São Paulo' },
];

describe('AcharOndeCampo travado', () => {
  it('fecha a lista de sugestões e desliga o campo', async () => {
    const wrapper = mount(AcharOndeCampo, {
      props: { sugestoes: SUGESTOES, texto: 'centro' },
    });
    expect(wrapper.findAll('[data-sugestao]')).toHaveLength(2);
    const campo = wrapper.find('[data-campo-onde]');
    // A primeira sugestão fica marcada: sem a trava, o Enter a escolheria.
    await campo.trigger('keydown', { key: 'ArrowDown' });
    expect(campo.attributes('aria-activedescendant')).toBeDefined();

    await wrapper.setProps({ bloqueado: true });

    expect(wrapper.find('[data-sugestoes]').exists()).toBe(false);
    expect(campo.attributes('disabled')).toBeDefined();
    // dispatchEvent chega ao campo desligado (o trigger dos testes não chega).
    campo.element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
    expect(wrapper.emitted('escolher')).toBeUndefined();
  });

  it('com o lugar escolhido, o "Alterar" fica desligado', () => {
    const wrapper = mount(AcharOndeCampo, {
      props: { lugar: { rotulo: 'Centro, Campinas' }, bloqueado: true },
    });

    expect(
      wrapper.find('[data-alterar-lugar]').attributes('disabled')
    ).toBeDefined();
  });
});
