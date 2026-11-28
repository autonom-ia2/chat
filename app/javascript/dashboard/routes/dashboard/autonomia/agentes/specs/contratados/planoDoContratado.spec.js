import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ContratadoCartao from '../../components/ContratadoCartao.vue';
import ProntosParaContratar from '../../components/ProntosParaContratar.vue';
import FaixaDoPlano from '../../components/pagina/FaixaDoPlano.vue';
import ContratadoNaPagina from '../../components/pagina/ContratadoNaPagina.vue';
import {
  faixaDoPlano,
  linhaDoPreco,
  mostraFaixa,
  precoDoPlano,
} from '../../utils/planoDoContratado';

vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => true) }) };
});

// #3270 — o preço e o período grátis do agente contratado, como o servidor manda (Contratados::Gratis.para_tela). A
// tela não guarda número nenhum: os dias, o valor e a moeda vêm do plano, e o valor sai pelo Intl. Cópia real (pt_BR).
const i18n = withFullI18n('pt_BR');
const { t } = i18n.global;

const UNIVERSAL = 'seguro_viagem_universal';
const plano = (extra = {}) => ({
  dias_gratis: 7,
  preco_mensal_centavos: 19700,
  moeda: 'BRL',
  situacao: 'gratis',
  dias_restantes: 7,
  ...extra,
});

// O Intl separa "R$" do valor com espaço sem quebra; o texto da tela é o mesmo, com o espaço comum.
const semNbsp = texto => texto.replaceAll(' ', ' ');

describe('planoDoContratado (#3270)', () => {
  it('formats the monthly price from cents, in the panel language', () => {
    expect(semNbsp(precoDoPlano(plano(), 'pt_BR'))).toBe('R$ 197,00');
  });

  it('uses the values the server sends, never fixed ones', () => {
    const outro = plano({ dias_gratis: 14, preco_mensal_centavos: 25050 });

    expect(semNbsp(linhaDoPreco(t, outro, 'pt_BR'))).toBe(
      '14 dias grátis, depois R$ 250,50 por mês'
    );
  });

  it('price line: free days, then the price', () => {
    expect(semNbsp(linhaDoPreco(t, plano(), 'pt_BR'))).toBe(
      '7 dias grátis, depois R$ 197,00 por mês'
    );
  });

  it('price line for an account that already used the free days: only the price', () => {
    const pausado = plano({ situacao: 'pausado', dias_restantes: null });

    expect(semNbsp(linhaDoPreco(t, pausado, 'pt_BR'))).toBe(
      'R$ 197,00 por mês'
    );
  });

  it('no plan, no line', () => {
    expect(linhaDoPreco(t, null, 'pt_BR')).toBe('');
  });

  it('banner during the free period: days left and the price after', () => {
    const faixa = faixaDoPlano(t, plano({ dias_restantes: 3 }), 'pt_BR');

    expect(faixa.situacao).toBe('gratis');
    expect(semNbsp(faixa.texto)).toBe(
      'Faltam 3 dias do período grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('banner on the last free day says one day', () => {
    const faixa = faixaDoPlano(t, plano({ dias_restantes: 1 }), 'pt_BR');

    expect(semNbsp(faixa.texto)).toBe(
      'Falta 1 dia do período grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('banner when paused: what happened and who releases it', () => {
    const faixa = faixaDoPlano(
      t,
      plano({ situacao: 'pausado', dias_restantes: null }),
      'pt_BR'
    );

    expect(faixa.situacao).toBe('pausado');
    expect(faixa.texto).toBe(
      'O período grátis acabou e o agente está pausado: ele não responde aos clientes. Fale com a Hub2You para liberar.'
    );
  });

  it('released account (or no plan): no banner', () => {
    expect(
      faixaDoPlano(
        t,
        plano({ situacao: 'liberado', dias_restantes: null }),
        'pt_BR'
      )
    ).toBeNull();
    expect(faixaDoPlano(t, null, 'pt_BR')).toBeNull();
  });
});

describe('FaixaDoPlano (#3270)', () => {
  const montar = valor => mount(FaixaDoPlano, { props: { plano: valor } });

  it('shows the free period banner', () => {
    const wrapper = montar(plano({ dias_restantes: 5 }));

    const faixa = wrapper.get('[data-faixa-plano="gratis"]');
    expect(faixa.attributes('role')).toBe('status');
    expect(semNbsp(faixa.text())).toContain('Faltam 5 dias do período grátis.');
  });

  it('shows the paused banner', () => {
    const wrapper = montar(
      plano({ situacao: 'pausado', dias_restantes: null })
    );

    expect(wrapper.get('[data-faixa-plano="pausado"]').text()).toContain(
      'o agente está pausado'
    );
  });

  it('shows only during the free period and the pause', () => {
    expect(mostraFaixa(plano())).toBe(true);
    expect(mostraFaixa(plano({ situacao: 'pausado' }))).toBe(true);
    expect(mostraFaixa(plano({ situacao: 'liberado' }))).toBe(false);
    expect(mostraFaixa(null)).toBe(false);
  });
});

describe('ContratadoNaPagina with the plan (#3270)', () => {
  const montar = valor =>
    mount(ContratadoNaPagina, {
      props: {
        nome: 'Bia',
        agente: {
          contratado: {
            modelo: UNIVERSAL,
            nome_corretora: 'Corretora Exemplo',
            acesso: { estado: 'ok' },
            plano: valor,
          },
        },
      },
    });

  it('puts the banner first on the page', () => {
    const wrapper = montar(plano({ dias_restantes: 2 }));

    const faixa = wrapper.get('[data-faixa-plano="gratis"]');
    expect(semNbsp(faixa.text())).toContain('Faltam 2 dias');
    const html = wrapper.html();
    expect(html.indexOf('data-faixa-plano')).toBeLessThan(
      html.indexOf('data-corretora-e-acesso')
    );
  });

  it('released account: no banner', () => {
    const wrapper = montar(
      plano({ situacao: 'liberado', dias_restantes: null })
    );

    expect(wrapper.find('[data-faixa-plano]').exists()).toBe(false);
  });

  it('old answer without a plan: no banner', () => {
    expect(montar(undefined).find('[data-faixa-plano]').exists()).toBe(false);
  });
});

describe('ContratadoCartao with the price (#3270)', () => {
  it('shows the price line from the plan', () => {
    const wrapper = mount(ContratadoCartao, {
      props: { modelo: UNIVERSAL, plano: plano() },
    });

    expect(semNbsp(wrapper.get('[data-preco]').text())).toBe(
      '7 dias grátis, depois R$ 197,00 por mês'
    );
  });

  it('without a plan, no price line', () => {
    const wrapper = mount(ContratadoCartao, { props: { modelo: UNIVERSAL } });

    expect(wrapper.find('[data-preco]').exists()).toBe(false);
  });

  it('the section passes each model its plan', () => {
    const wrapper = mount(ProntosParaContratar, {
      props: { modelos: [UNIVERSAL], planos: { [UNIVERSAL]: plano() } },
    });

    expect(semNbsp(wrapper.get('[data-preco]').text())).toBe(
      '7 dias grátis, depois R$ 197,00 por mês'
    );
  });
});
