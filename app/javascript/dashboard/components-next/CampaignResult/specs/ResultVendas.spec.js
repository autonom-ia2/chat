import { mount } from '@vue/test-utils';
import ResultVendas from '../ResultVendas.vue';

// #3115 — o bloco "Quem recebeu e comprou" quando a campanha não chegou a ninguém.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
    locale: { value: 'pt_BR' },
  }),
}));

const vendas = extra => ({
  janela_dias: 7,
  contando_ate: null,
  receberam: 0,
  compraram: { pessoas: 0, valor: null },
  responderam: { pessoas: 0, valor: null },
  sem_responder: { pessoas: 0, valor: null },
  controle: null,
  ...extra,
});

describe('ResultVendas', () => {
  it('ninguém recebeu: diz isso, sem a janela nem o aviso do valor', () => {
    const w = mount(ResultVendas, { props: { vendas: vendas() } });
    expect(w.get('[data-ninguem-recebeu]').text()).toBe(
      'CAMPANHA_VENDAS.RESULTADO.NINGUEM_RECEBEU'
    );
    expect(w.find('[data-situacao]').exists()).toBe(false);
    expect(w.find('[data-ninguem]').exists()).toBe(false);
    expect(w.find('[data-so-contagem]').exists()).toBe(false);
    expect(w.find('[data-total]').exists()).toBe(false);
    expect(w.find('[data-compraram]').exists()).toBe(false);
    expect(w.find('[data-parte]').exists()).toBe(false);
  });

  it('ninguém recebeu: a comparação com o grupo de controle não aparece', () => {
    const w = mount(ResultVendas, {
      props: { vendas: vendas({ controle: { pessoas: 40, compraram: 2 } }) },
    });
    expect(w.find('[data-ninguem-recebeu]').exists()).toBe(true);
    expect(w.find('[data-comparacao]').exists()).toBe(false);
  });

  it('houve envio e ninguém comprou: continua a frase da janela', () => {
    const w = mount(ResultVendas, {
      props: { vendas: vendas({ receberam: 237 }) },
    });
    expect(w.find('[data-ninguem-recebeu]').exists()).toBe(false);
    expect(w.get('[data-ninguem]').text()).toContain('NINGUEM_FECHADO');
    expect(w.get('[data-situacao]').text()).toContain('FECHADO');
  });
});
