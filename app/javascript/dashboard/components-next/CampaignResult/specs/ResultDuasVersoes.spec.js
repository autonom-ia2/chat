import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import duasVersoes from 'dashboard/i18n/locale/en/duasVersoes.json';
import ResultDuasVersoes from '../ResultDuasVersoes.vue';

// #3099 — o resultado das duas versões: em que pé está, quem foi melhor e a escolha à mão com confirmação.
const R = duasVersoes.DUAS_VERSOES.RESULTADO;
const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en: duasVersoes } });

const versoes = [
  {
    numero: 1,
    texto: 'Oi! Seu pedido favorito voltou.',
    receberam: 135,
    responderam: 11,
    compraram: 2,
    valor: null,
  },
  {
    numero: 2,
    texto: 'Saudade? Hoje tem frete grátis.',
    receberam: 135,
    responderam: 24,
    compraram: 6,
    valor: null,
  },
];

const montar = (teste, extra = {}) =>
  mount(ResultDuasVersoes, {
    props: {
      teste: { criterio: 'respostas', resto: 1080, versoes, ...teste },
      ...extra,
    },
    global: { plugins: [i18n()] },
  });

describe('ResultDuasVersoes', () => {
  it('testando: diz até quando e quem está na frente, sem dono do botão', () => {
    const wrapper = montar({
      estado: 'testando',
      escolhe_em: Math.floor(Date.now() / 1000) + 3600,
    });
    expect(wrapper.find('[data-situacao="testando"]').text()).toContain(
      '1,080'
    );
    expect(wrapper.find('[data-comparacao]').text()).toBe(
      R.ATE_AGORA.replace(
        '{frase}',
        R.FRASE.RESPOSTAS.DOBRO.replace('{n}', '2').replace('V', 'v')
      )
    );
    expect(wrapper.find('[data-cartao-versao="2"] [data-selo]').text()).toBe(
      R.NA_FRENTE
    );
    expect(wrapper.find('[data-escolher-versao]').exists()).toBe(false);
    // O sistema escolhe sozinho na hora: quem pode disparar só adianta.
    expect(wrapper.find('[data-sem-permissao]').text()).toBe(
      R.SEM_PERMISSAO_TESTANDO
    );
  });

  it('esperando você sem permissão: diz quem escolhe', () => {
    const wrapper = montar({
      estado: 'esperando_voce',
      criterio: 'eu_escolho',
    });
    expect(wrapper.find('[data-sem-permissao]').text()).toBe(R.SEM_PERMISSAO);
  });

  it('o botão da versão na frente é o principal e diz qual versão manda', () => {
    const wrapper = montar(
      { estado: 'esperando_voce', criterio: 'eu_escolho' },
      { podeEscolher: true }
    );
    const daFrente = wrapper.find(
      '[data-cartao-versao="2"] [data-escolher-versao]'
    );
    const outra = wrapper.find(
      '[data-cartao-versao="1"] [data-escolher-versao]'
    );
    expect(daFrente.attributes('data-escolher-versao')).toBe('principal');
    expect(outra.attributes('data-escolher-versao')).toBe('');
    expect(daFrente.attributes('aria-label')).toBe(
      R.ESCOLHER_ARIA.replace('{n}', '2').replace('{resto}', '1,080')
    );
  });

  it('esperando você: escolher pede confirmação no cartão e só então avisa', async () => {
    const wrapper = montar(
      { estado: 'esperando_voce', criterio: 'eu_escolho' },
      { podeEscolher: true }
    );
    const cartao = wrapper.find('[data-cartao-versao="1"]');
    await cartao.find('[data-escolher-versao]').trigger('click');
    expect(wrapper.emitted('escolher')).toBeUndefined();
    expect(cartao.find('[data-confirmar-versao]').text()).toContain(
      R.CONFIRMAR.replace('{n}', '1').replace('{resto}', '1,080')
    );
    await cartao.find('[data-sim-mandar]').trigger('click');
    expect(wrapper.emitted('escolher')).toEqual([[1]]);
  });

  it('escolhida pelo sistema: selo Ganhou e o resto com a vencedora', () => {
    const wrapper = montar(
      { estado: 'escolhida', vencedora: 2, escolhida_por: 'sistema' },
      { podeEscolher: true }
    );
    expect(wrapper.find('[data-situacao="escolhida"]').text()).toBe(
      R.ESCOLHIDA_SISTEMA.replace('{n}', '2').replace('{resto}', '1,080')
    );
    expect(wrapper.find('[data-cartao-versao="2"] [data-selo]').text()).toBe(
      R.GANHOU
    );
    expect(wrapper.find('[data-cartao-versao="1"] [data-selo]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-escolher-versao]').exists()).toBe(false);
  });

  it('empate segue a versão 1', () => {
    const wrapper = montar({
      estado: 'escolhida',
      vencedora: 1,
      escolhida_por: 'empate',
    });
    expect(wrapper.find('[data-situacao]').text()).toBe(
      R.ESCOLHIDA_EMPATE.replace('{resto}', '1,080')
    );
    expect(wrapper.find('[data-cartao-versao="1"] [data-selo]').text()).toBe(
      R.FOI_PARA_O_RESTO
    );
    // Sem troféu nem a frase de comparação repetindo a faixa.
    expect(
      wrapper.find('[data-icone-do-selo]').attributes('data-icone-do-selo')
    ).toBe('i-lucide-send');
    expect(wrapper.find('[data-comparacao]').exists()).toBe(false);
  });

  it('pelas compras mostra a linha de compras e o valor', () => {
    const comValor = versoes.map((versao, indice) => ({
      ...versao,
      valor: [{ currency: 'BRL', cents: (indice + 1) * 45000 }],
    }));
    const wrapper = montar({
      estado: 'todos',
      criterio: 'compras',
      versoes: comValor,
    });
    const linha = wrapper.find(
      '[data-cartao-versao="2"] [data-linha="compraram"]'
    );
    expect(linha.text()).toContain('6');
    expect(linha.text()).toContain('900');
  });

  it('automação: quantas pessoas faltam e o texto da automação', () => {
    const wrapper = montar(
      { estado: 'testando', faltam: 37 },
      { naAutomacao: true, podeEscolher: true }
    );
    expect(wrapper.find('[data-faltam]').text()).toBe(
      '37 more people need to get version 1 to close the test.'
    );
    expect(wrapper.find('[data-situacao="testando"]').text()).toContain(
      '4 hours'
    );
    expect(wrapper.find('[data-escolher-versao]').text()).toBe(
      R.AUTOMACAO.ESCOLHER
    );
  });

  it('sem teste e sem carregar: avisa e oferece tentar de novo', async () => {
    const wrapper = mount(ResultDuasVersoes, {
      props: { teste: null },
      global: { plugins: [i18n()] },
    });
    expect(wrapper.find('[data-erro-duas-versoes]').text()).toContain(R.ERRO);
    await wrapper.find('[data-erro-duas-versoes] button').trigger('click');
    expect(wrapper.emitted('recarregar')).toHaveLength(1);
  });

  it('carregando: esqueleto com aviso para leitor de tela', () => {
    const wrapper = montar(null, { carregando: true });
    expect(wrapper.attributes('aria-busy')).toBe('true');
    expect(wrapper.find('[role="status"]').text()).toBe(R.CARREGANDO);
  });
});
