import { mount } from '@vue/test-utils';
import LivreLigar from '../components/LivreLigar.vue';
import LivreLinha from '../components/LivreLinha.vue';

// #2572 (F3.7) — o motor pausou a automação porque quem ligou perdeu o acesso.
// O editor e a lista mostram o motivo e "Assumir e religar", dizendo que ela
// passa a agir em nome de quem clica. Quem não pode assumir vê o motivo, sem o
// botão.
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: chave => chave }) }));

const PAUSA = {
  motivo: 'quem_ligou_saiu_da_conta',
  frase: 'Quem ligou a automação saiu da conta. Assuma e religue.',
};
const RECEITA = {
  gatilho: { tipo: 'conversa.resolvida' },
  passos: [
    { id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
  ],
};
const STUBS = {
  Button: {
    props: ['label', 'disabled'],
    emits: ['click'],
    template:
      '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
  },
  Switch: { template: '<span data-switch />' },
};
const global = { mocks: { $t: chave => chave }, stubs: STUBS };

const ligar = props =>
  mount(LivreLigar, { props: { receita: RECEITA, ...props }, global });
const linha = props =>
  mount(LivreLinha, {
    props: { nome: 'Lembrete', quando: 'Quando resolver', ...props },
    global,
  });

describe('a automação pausada no editor', () => {
  it('mostra o motivo, o aviso e "Assumir e religar", que liga', async () => {
    const wrapper = ligar({ pausa: PAUSA, podeMudar: true });

    expect(wrapper.find('[data-pausa]').text()).toContain(PAUSA.frase);
    expect(wrapper.find('[data-pausa]').text()).toContain(
      'AUTOMACAO_LIVRE.LIGAR.ASSUMIR_AVISO'
    );
    expect(wrapper.text()).not.toContain('AUTOMACAO_LIVRE.LIGAR.DESLIGADA');
    const botao = wrapper.find('[data-ligar]');
    expect(botao.text()).toBe('AUTOMACAO_LIVRE.LIGAR.ASSUMIR');

    await botao.trigger('click');

    expect(wrapper.emitted('ligar')).toHaveLength(1);
  });

  it('quem não pode assumir vê o motivo, sem o botão', () => {
    const wrapper = ligar({ pausa: PAUSA, podeMudar: false });

    expect(wrapper.find('[data-pausa]').text()).toContain(PAUSA.frase);
    expect(wrapper.find('[data-ligar]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('AUTOMACAO_LIVRE.LIGAR.ASSUMIR');
  });

  it('desligada à mão segue com "Ligar" e sem aviso de pausa', () => {
    const wrapper = ligar({ podeMudar: true });

    expect(wrapper.find('[data-pausa]').exists()).toBe(false);
    expect(wrapper.find('[data-ligar]').text()).toBe(
      'AUTOMACAO_LIVRE.LIGAR.BOTAO'
    );
  });
});

describe('a automação pausada na lista', () => {
  it('troca o interruptor por "Assumir e religar", que liga', async () => {
    const wrapper = linha({ pausa: PAUSA.frase, podeMudar: true });

    expect(wrapper.find('[data-pausa]').text()).toContain(PAUSA.frase);
    expect(wrapper.find('[data-switch]').exists()).toBe(false);

    await wrapper.find('[data-assumir]').trigger('click');

    expect(wrapper.emitted('alternar')).toHaveLength(1);
  });

  it('quem não pode assumir vê o motivo, sem o botão', () => {
    const wrapper = linha({ pausa: PAUSA.frase, podeMudar: false });

    expect(wrapper.find('[data-pausa]').text()).toContain(PAUSA.frase);
    expect(wrapper.find('[data-assumir]').exists()).toBe(false);
  });

  it('sem pausa, fica o interruptor', () => {
    expect(linha({ podeMudar: true }).find('[data-switch]').exists()).toBe(
      true
    );
  });
});
