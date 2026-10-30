import { mount } from '@vue/test-utils';
import PerguntaConversas from '../guiada/PerguntaConversas.vue';
import { global } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 5.B3 e revisão do #2308: em "Atende as próprias", o último alcance ligado diz por que não desliga.
const PROPRIAS = [
  'conversation_participating_manage',
  'conversation_unassigned_manage',
];

const montar = (permissions, giver = CARLA) => {
  const wrapper = mount(PerguntaConversas, {
    props: {
      permissions,
      inicial: PROPRIAS,
      giver,
      nome: 'Atendente',
      'onUpdate:permissions': novas => wrapper.setProps({ permissions: novas }),
    },
    global: global(),
  });
  return wrapper;
};

const interruptor = (wrapper, chave) =>
  wrapper.find(`[data-subescolha="${chave}"] [role="switch"]`);

describe('PerguntaConversas', () => {
  it('título neutro, com o nome da função', () => {
    expect(montar(PROPRIAS).find('h1').text()).toBe(
      'Com a função Atendente, quais conversas a pessoa atende?'
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

  it('ir para "Atende todas" e voltar a "Atende as próprias" devolve os alcances de entrada', async () => {
    const entrada = ['conversation_participating_manage'];
    const wrapper = montar(entrada);
    const radios = () => wrapper.findAll('[role="radio"]');
    const proprias = radios().findIndex(
      r => r.attributes('aria-checked') === 'true'
    );

    await radios()[proprias + 1].trigger('click');
    expect(wrapper.props('permissions')).toContain('conversation_manage');

    await radios()[proprias].trigger('click');
    expect(wrapper.props('permissions')).toEqual(entrada);
  });

  // #2403: quem monta só com as novas sem ninguém dá "Atende as próprias" por esse alcance (GrantGuard#reach? confere
  // chave a chave); antes, a opção aparecia com cadeado.
  it('quem dá só com conversation_unassigned_manage escolhe "Atende as próprias", sem cadeado, pelo alcance que tem', async () => {
    const soNovas = {
      userId: 20,
      isAdmin: false,
      customRoleId: 21,
      permissions: ['custom_role_manage', 'conversation_unassigned_manage'],
    };
    const wrapper = montar([], soNovas);
    const proprias = wrapper.find('[data-nivel="limited"]');
    expect(proprias.attributes('aria-disabled')).toBe('false');
    expect(proprias.find('.i-lucide-lock').exists()).toBe(false);
    expect(wrapper.find('[data-nivel="all"]').attributes('aria-disabled')).toBe(
      'true'
    );

    await proprias.trigger('click');
    expect(wrapper.emitted('update:permissions')[0][0]).toEqual([
      'conversation_unassigned_manage',
    ]);
    const participa = wrapper.find(
      '[data-subescolha="conversation_participating_manage"]'
    );
    expect(participa.find('.i-lucide-lock').exists()).toBe(true);
  });

  // Só "Atende as próprias" tem o bloco de dentro; nas outras, nada de linha vazia dentro do cartão.
  it('"Atende todas" não desenha o bloco de dentro', async () => {
    const wrapper = montar(PROPRIAS);
    const radios = () => wrapper.findAll('[role="radio"]');
    const proprias = radios().findIndex(
      r => r.attributes('aria-checked') === 'true'
    );
    expect(wrapper.findAll('[data-subescolha]').length).toBeGreaterThan(0);

    await radios()[proprias + 1].trigger('click');
    expect(wrapper.find('.border-t.border-n-blue-6').exists()).toBe(false);
  });
});
