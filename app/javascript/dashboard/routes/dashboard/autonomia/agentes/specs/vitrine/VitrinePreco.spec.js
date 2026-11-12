import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import VitrineCartao from '../../vitrine/components/VitrineCartao.vue';
import VitrinePreco from '../../vitrine/components/VitrinePreco.vue';
import VitrineQuantoCusta from '../../vitrine/components/VitrineQuantoCusta.vue';
import { ferramentaPorId } from '../../vitrine/catalogo';
import { emReais } from '../../vitrine/premium';

// #2858 F7 — o card Premium mostra o selo, quantas das 20 grátis do mês restam e o preço depois, sem termo técnico.
// O "Quanto custa" do detalhe diz também o que conta, o que não conta e quando as grátis voltam. Cópia real em pt_BR.
withFullI18n('pt_BR');

const PROIBIDAS = ['BigDataCorp', 'dataset', 'API', 'token', 'http', 'JSON'];

// O número grande e a frase são dois elementos: o template deixa espaços entre eles. Aqui conta só a leitura.
const lido = no => no.text().split(' ').filter(Boolean).join(' ');

describe('VitrinePreco (cartão)', () => {
  it('many left: how many of the 20 and the price range after', () => {
    const wrapper = mount(VitrinePreco, {
      props: {
        premium: { gratis: 20, restantes: 15, precos: ['0.06', '0.15'] },
      },
    });
    expect(wrapper.find('[data-vitrine-restantes]').text()).toBe(
      'Restam 15 de 20 grátis no mês'
    );
    expect(wrapper.find('[data-vitrine-preco]').text()).toBe(
      `Depois, de ${emReais('0.06')} a ${emReais('0.15')} cada`
    );
    expect(
      wrapper.find('[data-vitrine-premium]').attributes('data-vitrine-estado')
    ).toBe('RESTAM');
    PROIBIDAS.forEach(palavra => expect(wrapper.text()).not.toContain(palavra));
  });

  it('one left, then none left (the price becomes "now")', async () => {
    const wrapper = mount(VitrinePreco, {
      props: { premium: { gratis: 20, restantes: 1, precos: ['0.09'] } },
    });
    expect(wrapper.find('[data-vitrine-restantes]').text()).toBe(
      'Resta 1 de 20 grátis no mês'
    );
    expect(wrapper.find('[data-vitrine-preco]').text()).toBe(
      `Depois, ${emReais('0.09')} cada`
    );
    await wrapper.setProps({
      premium: { gratis: 20, restantes: 0, precos: ['0.09'] },
    });
    expect(wrapper.find('[data-vitrine-restantes]').text()).toBe(
      'As grátis do mês acabaram'
    );
    expect(wrapper.find('[data-vitrine-preco]').text()).toBe(
      `Agora, ${emReais('0.09')} cada`
    );
  });
});

describe('VitrineQuantoCusta (detalhe)', () => {
  const montar = premium => mount(VitrineQuantoCusta, { props: { premium } });

  it('says what counts, what does not, when they come back and the bill', () => {
    const wrapper = montar({
      gratis: 20,
      restantes: 20,
      precos: ['0.39'],
      confere_documento: true,
    });
    const texto = wrapper.text();
    expect(texto).toContain('Quanto custa');
    expect(lido(wrapper.find('[data-vitrine-restantes]'))).toBe(
      '20 de 20 grátis restam neste mês'
    );
    expect(wrapper.find('[data-vitrine-preco]').text()).toContain(
      `${emReais('0.39')} por consulta`
    );
    expect(texto).toContain('Conta mesmo quando a consulta não acha nada.');
    expect(texto).toContain('CPF ou CNPJ com número errado não conta.');
    expect(texto).toContain('Todo dia 1º, voltam 20 grátis.');
    expect(texto).toContain('fatura do mês');
    // Preço único: sem a explicação da faixa.
    expect(texto).not.toContain('O preço muda');
    PROIBIDAS.forEach(palavra => expect(texto).not.toContain(palavra));
  });

  // A regra do número errado só vale no card que recebe CPF ou CNPJ (`confere_documento`, do servidor): a placa e o
  // endereço não têm documento para errar.
  it('the wrong CPF or CNPJ rule only in the cards that take one', () => {
    const REGRA = 'CPF ou CNPJ com número errado não conta.';
    const doServidor = {
      historico_placa: { precos: ['0.09'], confere_documento: false },
      risco_endereco: { precos: ['0.06', '0.15'], confere_documento: false },
      conferir_pessoa: { precos: ['0.06', '0.09'], confere_documento: true },
      certidoes_empresa: { precos: ['0.06', '0.15'], confere_documento: true },
    };
    const comARegra = Object.entries(doServidor)
      .filter(([, premium]) =>
        montar({ gratis: 20, restantes: 20, ...premium })
          .text()
          .includes(REGRA)
      )
      .map(([card]) => card);
    expect(comARegra).toEqual(['conferir_pessoa', 'certidoes_empresa']);
  });

  it('one left and none left; the range explains why the price changes', () => {
    const uma = montar({ gratis: 20, restantes: 1, precos: ['0.06', '0.15'] });
    expect(lido(uma.find('[data-vitrine-restantes]'))).toBe(
      '1 de 20 grátis resta neste mês'
    );
    expect(uma.text()).toContain(
      'O preço muda conforme o que o agente consulta.'
    );

    const nenhuma = montar({ gratis: 20, restantes: 0, precos: ['0.09'] });
    expect(nenhuma.find('[data-vitrine-restantes]').text()).toBe(
      'As grátis do mês acabaram'
    );
    expect(nenhuma.find('[data-vitrine-preco]').text()).toContain(
      'Agora, cada consulta custa'
    );
  });
});

describe('VitrineCartao · Premium', () => {
  it('the Premium card has the badge and the price; the free card has neither', () => {
    const premium = mount(VitrineCartao, {
      props: {
        ferramenta: ferramentaPorId('historico_placa'),
        premium: { gratis: 20, restantes: 20, precos: ['0.09'] },
      },
    });
    expect(premium.find('[data-vitrine-selo-premium]').text()).toBe('Premium');
    expect(premium.find('[data-vitrine-premium]').exists()).toBe(true);
    expect(premium.text()).toContain('Histórico da placa');
    expect(premium.text()).toContain('Restam 20 de 20 grátis no mês');

    const gratis = mount(VitrineCartao, {
      props: { ferramenta: ferramentaPorId('cep') },
    });
    expect(gratis.find('[data-vitrine-selo-premium]').exists()).toBe(false);
    expect(gratis.find('[data-vitrine-premium]').exists()).toBe(false);
  });
});
