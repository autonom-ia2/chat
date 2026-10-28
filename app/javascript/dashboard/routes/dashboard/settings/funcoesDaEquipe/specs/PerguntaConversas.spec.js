import { mount } from '@vue/test-utils';
import PerguntaConversas from '../guiada/PerguntaConversas.vue';
import { global } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 5.B3 e decisão 10: em "Atende as próprias", o último alcance ligado diz por que não desliga.
const PROPRIAS = [
  'conversation_participating_manage',
  'conversation_unassigned_manage',
];

const montar = permissions =>
  mount(PerguntaConversas, {
    props: { permissions, inicial: PROPRIAS, giver: CARLA, nome: 'Atendente' },
    global: global(),
  });

const interruptor = (wrapper, chave) =>
  wrapper.find(`[data-subescolha="${chave}"] [role="switch"]`);

describe('PerguntaConversas', () => {
  it('título neutro, com o nome da função', () => {
    expect(montar(PROPRIAS).find('h1').text()).toBe(
      'Quais conversas Atendente atende?'
    );
  });

  it('com os dois alcances, os dois desligam', async () => {
    const wrapper = montar(PROPRIAS);
    expect(wrapper.text()).not.toContain('Pelo menos uma fica ligada.');
    await interruptor(wrapper, 'conversation_unassigned_manage').trigger(
      'click'
    );
    expect(wrapper.emitted('update:permissions')[0][0]).toEqual([
      'conversation_participating_manage',
    ]);
  });

  it('o último alcance fica ligado, travado, e explica: "Pelo menos uma fica ligada."', async () => {
    const wrapper = montar(['conversation_participating_manage']);
    const ultimo = wrapper.find(
      '[data-subescolha="conversation_participating_manage"]'
    );
    const botao = ultimo.find('[role="switch"]');
    expect(botao.attributes('aria-checked')).toBe('true');
    expect(botao.attributes('aria-disabled')).toBe('true');
    expect(ultimo.text()).toContain('Pelo menos uma fica ligada.');

    await botao.trigger('click');
    expect(wrapper.emitted('update:permissions')).toBeUndefined();
  });
});
