import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ContratadoCartao from '../../components/ContratadoCartao.vue';
import ProntosParaContratar from '../../components/ProntosParaContratar.vue';
import FaixaDoPlano from '../../components/pagina/FaixaDoPlano.vue';
import ContratadoNaPagina from '../../components/pagina/ContratadoNaPagina.vue';
import {
  faixaDoPlano,
  iconeDoPreco,
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
      'R$ 197,00 por mês. Os dias grátis já foram usados.'
    );
  });

  it('price icon: the gift while there are free days, the tag when they were used', () => {
    expect(iconeDoPreco(plano())).toBe('i-lucide-gift');
    expect(iconeDoPreco(plano({ situacao: 'liberado' }))).toBe('i-lucide-gift');
    expect(iconeDoPreco(plano({ situacao: 'pausado' }))).toBe('i-lucide-tag');
  });

  it('price line for an account in the middle of the free days: the days left, with the banner texts', () => {
    expect(
      semNbsp(linhaDoPreco(t, plano({ dias_restantes: 3 }), 'pt_BR'))
    ).toBe(
      'Faltam 3 dias grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
    expect(
      semNbsp(linhaDoPreco(t, plano({ dias_restantes: 1 }), 'pt_BR'))
    ).toBe(
      'Falta 1 dia grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('price line on the last free day: today is the last one', () => {
    expect(
      semNbsp(linhaDoPreco(t, plano({ dias_restantes: 0 }), 'pt_BR'))
    ).toBe(
      'Hoje é o último dia grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('price line for an account that never hired (all the free days left): the full offer', () => {
    expect(
      semNbsp(linhaDoPreco(t, plano({ dias_restantes: 7 }), 'pt_BR'))
    ).toBe('7 dias grátis, depois R$ 197,00 por mês');
  });

  it('no plan, no line', () => {
    expect(linhaDoPreco(t, null, 'pt_BR')).toBe('');
  });

  it('banner during the free period: days left and the price after', () => {
    const faixa = faixaDoPlano(t, plano({ dias_restantes: 3 }), 'pt_BR');

    expect(faixa.situacao).toBe('gratis');
    expect(faixa.papel).toBe('status');
    expect(semNbsp(faixa.texto)).toBe(
      'Faltam 3 dias grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('banner with one free day left says one day', () => {
    const faixa = faixaDoPlano(t, plano({ dias_restantes: 1 }), 'pt_BR');

    expect(semNbsp(faixa.texto)).toBe(
      'Falta 1 dia grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('banner on the last free day (0 days left) says today is the last one', () => {
    const faixa = faixaDoPlano(t, plano({ dias_restantes: 0 }), 'pt_BR');

    expect(faixa.situacao).toBe('gratis');
    expect(semNbsp(faixa.texto)).toBe(
      'Hoje é o último dia grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
  });

  it('banner when paused: what happened and who releases it', () => {
    const faixa = faixaDoPlano(
      t,
      plano({ situacao: 'pausado', dias_restantes: null }),
      'pt_BR'
    );

    expect(faixa.situacao).toBe('pausado');
    expect(faixa.papel).toBe('alert');
    expect(faixa.texto).toBe(
      'Os dias grátis acabaram. O agente está pausado e não responde aos clientes. Para liberar, fale com a Hub2You.'
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
    expect(semNbsp(faixa.text())).toContain('Faltam 5 dias grátis.');
  });

  it('shows the last-day banner', () => {
    const wrapper = montar(plano({ dias_restantes: 0 }));

    expect(wrapper.get('[data-faixa-plano="gratis"]').text()).toContain(
      'Hoje é o último dia grátis.'
    );
  });

  it('shows the paused banner as an alert, with no button', () => {
    const wrapper = montar(
      plano({ situacao: 'pausado', dias_restantes: null })
    );

    const faixa = wrapper.get('[data-faixa-plano="pausado"]');
    expect(faixa.attributes('role')).toBe('alert');
    expect(faixa.text()).toContain('O agente está pausado');
    expect(faixa.find('button').exists()).toBe(false);
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
    expect(semNbsp(faixa.text())).toContain('Faltam 2 dias grátis');
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
  it('shows the price line from the plan, with the gift icon', () => {
    const wrapper = mount(ContratadoCartao, {
      props: { modelo: UNIVERSAL, plano: plano() },
    });

    const linha = wrapper.get('[data-preco]');
    expect(semNbsp(linha.text())).toBe(
      '7 dias grátis, depois R$ 197,00 por mês'
    );
    expect(linha.classes()).toEqual(
      expect.arrayContaining(['text-base', 'font-semibold'])
    );
    expect(linha.find('.i-lucide-gift').exists()).toBe(true);
  });

  it('puts the price right below the text, before what the agent needs', () => {
    const wrapper = mount(ContratadoCartao, {
      props: { modelo: UNIVERSAL, plano: plano() },
    });

    const html = wrapper.html();
    const texto = html.indexOf(t('AGENTS.CONTRATADOS.CARTAO.TEXTO'));
    const preco = html.indexOf('data-preco');
    const precisa = html.indexOf(t('AGENTS.CONTRATADOS.CARTAO.PRECISA'));
    expect(texto).toBeGreaterThan(-1);
    expect(texto).toBeLessThan(preco);
    expect(preco).toBeLessThan(precisa);
  });

  it('account in the middle of the free days: the card says how many are left', () => {
    const wrapper = mount(ContratadoCartao, {
      props: { modelo: UNIVERSAL, plano: plano({ dias_restantes: 4 }) },
    });

    const linha = wrapper.get('[data-preco]');
    expect(semNbsp(linha.text())).toBe(
      'Faltam 4 dias grátis. Depois, R$ 197,00 por mês na fatura da Hub2You.'
    );
    expect(linha.find('.i-lucide-gift').exists()).toBe(true);
  });

  it('account that already used the free days: only the price, with the tag icon', () => {
    const wrapper = mount(ContratadoCartao, {
      props: {
        modelo: UNIVERSAL,
        plano: plano({ situacao: 'pausado', dias_restantes: null }),
      },
    });

    const linha = wrapper.get('[data-preco]');
    expect(semNbsp(linha.text())).toBe(
      'R$ 197,00 por mês. Os dias grátis já foram usados.'
    );
    expect(linha.find('.i-lucide-tag').exists()).toBe(true);
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
