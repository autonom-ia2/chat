import { mount } from '@vue/test-utils';
import LivreDestinatarios from '../components/LivreDestinatarios.vue';
import { doAlvoDoGatilho } from '../catalogo';
import catalogoGerado from '../../../../../../../../lib/operator_guide/automacao-passos.json';

// G9 (#2707) — o "avisar" chama também quem cuida do card, que nem sempre é
// quem atende a conversa (a gerente troca o dono do card na Lista do CRM).
const SwitchFalso = {
  props: ['modelValue'],
  emits: ['update:modelValue'],
  template:
    '<button type="button" :data-ligado="modelValue" @click="$emit(\'update:modelValue\', !modelValue)" />',
};

const montar = (modelValue, doCard = true) =>
  mount(LivreDestinatarios, {
    props: {
      rotulo: 'PARA',
      doCard,
      modelValue,
      opcoes: { time: [], pessoa: [] },
    },
    global: {
      mocks: { $t: chave => chave },
      stubs: { Switch: SwitchFalso, LivreMarcar: true },
    },
  });

describe('LivreDestinatarios, quem cuida do card', () => {
  it('ligar põe responsavel_do_card e mantém o resto da escolha', async () => {
    const wrapper = montar({ pessoas: [3] });

    await wrapper.find('[data-responsavel-do-card]').trigger('click');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { pessoas: [3], responsavel_do_card: true },
    ]);
  });

  it('desligar tira a chave da receita, como nas outras escolhas', async () => {
    const wrapper = montar({ responsavel_do_card: true, responsavel: true });

    await wrapper.find('[data-responsavel-do-card]').trigger('click');

    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual([
      { responsavel: true },
    ]);
  });
});

describe('LivreDestinatarios, gatilho que não é de card', () => {
  it('esconde quem cuida do card', () => {
    expect(montar({}, false).find('[data-responsavel-do-card]').exists()).toBe(
      false
    );
  });

  it('mostra se já estava marcado, para poder desligar', () => {
    const wrapper = montar({ responsavel_do_card: true }, false);
    expect(wrapper.find('[data-responsavel-do-card]').exists()).toBe(true);
  });
});

describe('o que era antes da troca, no catálogo', () => {
  const caminhos = tipo =>
    doAlvoDoGatilho(catalogoGerado, tipo).valores.map(item => item.caminho);

  it('aparece no gatilho da troca de responsável', () => {
    expect(caminhos('card.responsavel_mudou')).toEqual(
      expect.arrayContaining([
        'gatilho.responsavel_anterior_id',
        'gatilho.responsavel_anterior_nome',
        'gatilho.responsavel_anterior_ausente',
        'card.responsavel_nome',
      ])
    );
  });

  it('o time de antes só na troca de time, e quem cuidava antes só na de dono', () => {
    expect(caminhos('card.time_mudou')).toContain('gatilho.time_anterior_nome');
    expect(caminhos('card.time_mudou')).not.toContain(
      'gatilho.responsavel_anterior_nome'
    );
    expect(caminhos('card.responsavel_mudou')).not.toContain(
      'gatilho.time_anterior_nome'
    );
  });

  it('some nos outros gatilhos do card', () => {
    expect(caminhos('card.ganho')).not.toContain(
      'gatilho.responsavel_anterior_nome'
    );
    expect(caminhos('card.ganho')).toContain('card.responsavel_nome');
  });
});

// #2552 — a reserva da caixa é um Switch (nunca um <select>) que só aparece
// com o responsável ligado; desligar o responsável tira a reserva também.
describe('LivreDestinatarios, a reserva da caixa', () => {
  it('sem o responsável, não oferece a reserva; nada de <select>', () => {
    const wrapper = montar({ times: [3] });

    expect(wrapper.find('[data-reserva-caixa]').exists()).toBe(false);
    expect(wrapper.find('select').exists()).toBe(false);
  });

  it('com o responsável, liga a reserva da caixa', async () => {
    const wrapper = montar({ responsavel: true });

    await wrapper.find('[data-reserva-caixa]').trigger('click');

    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      responsavel: true,
      se_nao_houver: 'caixa',
    });
  });

  it('desligar o responsável tira a reserva e guarda o resto', async () => {
    const wrapper = montar({
      responsavel: true,
      se_nao_houver: 'caixa',
      pessoas: [7],
    });

    await wrapper.find('[data-responsavel]').trigger('click');

    expect(wrapper.emitted('update:modelValue')[0][0]).toEqual({
      pessoas: [7],
    });
  });
});
