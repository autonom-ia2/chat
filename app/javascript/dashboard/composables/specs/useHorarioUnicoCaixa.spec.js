// #1619 — a flag horario_unico_caixa e o fuso da conta, lidos da store do painel.
import { defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { useHorarioUnicoCaixa } from '../useHorarioUnicoCaixa';

const ler = plugins => {
  let resultado;
  const Sonda = defineComponent({
    setup() {
      resultado = useHorarioUnicoCaixa();
      return () => h('i');
    },
  });
  mount(Sonda, { global: { plugins } });
  return {
    ligado: resultado.ligado.value,
    fuso: resultado.fuso.value,
    fusoIana: resultado.fusoIana.value,
  };
};

const criarStore = flag =>
  createStore({
    getters: {
      getCurrentAccountId: () => 3,
      'accounts/isFeatureEnabledonAccount': () => (conta, nome) =>
        flag && conta === 3 && nome === 'horario_unico_caixa',
      'accounts/getAccount': () => id => ({
        id,
        custom_attributes: { timezone: 'America/Sao_Paulo' },
      }),
    },
  });

describe('useHorarioUnicoCaixa', () => {
  it('flag ligada: ligado e o fuso da conta, com o rótulo de Configurações', () => {
    expect(ler([criarStore(true)])).toEqual({
      ligado: true,
      fuso: 'America/Sao Paulo',
      fusoIana: 'America/Sao_Paulo',
    });
  });

  it('flag desligada: desligado, e o fuso continua o da conta', () => {
    expect(ler([criarStore(false)])).toMatchObject({
      ligado: false,
      fusoIana: 'America/Sao_Paulo',
    });
  });

  it('sem a store do painel: desligado, sem quebrar', () => {
    expect(ler([]).ligado).toBe(false);
  });
});
