import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import VitrineCartao from '../../vitrine/components/VitrineCartao.vue';
import VitrinePreco from '../../vitrine/components/VitrinePreco.vue';
import { ferramentaPorId } from '../../vitrine/catalogo';
import { emReais } from '../../vitrine/premium';

// #2858 F7 — o card Premium mostra o selo, "20 grátis, depois R$ X" e as grátis que restam, sem termo técnico. Cópia
// real em pt_BR.
withFullI18n('pt_BR');

const PROIBIDAS = ['BigDataCorp', 'dataset', 'API', 'token', 'http', 'JSON'];

describe('VitrinePreco', () => {
  it('shows the badge, the free lookups and the price range', () => {
    const wrapper = mount(VitrinePreco, {
      props: {
        premium: { gratis: 20, restantes: 15, precos: ['0.06', '0.15'] },
      },
    });
    const texto = wrapper.text();
    expect(texto).toContain('Premium');
    expect(wrapper.find('[data-vitrine-preco]').text()).toBe(
      `20 grátis, depois de ${emReais('0.06')} a ${emReais('0.15')}`
    );
    expect(wrapper.find('[data-vitrine-restantes]').text()).toBe(
      'Restam 15 grátis'
    );
    PROIBIDAS.forEach(palavra => expect(texto).not.toContain(palavra));
  });

  it('one price, one free left, and none left', async () => {
    const wrapper = mount(VitrinePreco, {
      props: { premium: { gratis: 20, restantes: 1, precos: ['0.09'] } },
    });
    expect(wrapper.find('[data-vitrine-preco]').text()).toBe(
      `20 grátis, depois ${emReais('0.09')}`
    );
    expect(wrapper.find('[data-vitrine-restantes]').text()).toBe(
      'Resta 1 grátis'
    );
    await wrapper.setProps({
      premium: { gratis: 20, restantes: 0, precos: ['0.09'] },
    });
    expect(wrapper.find('[data-vitrine-restantes]').text()).toBe(
      'As grátis acabaram'
    );
  });

  it('the full version explains that no-record counts and goes on the monthly bill', () => {
    const wrapper = mount(VitrinePreco, {
      props: {
        premium: { gratis: 20, restantes: 20, precos: ['0.39'] },
        completo: true,
      },
    });
    expect(wrapper.text()).toContain('mesmo quando não há registro');
    expect(wrapper.text()).toContain('fatura do mês');
  });
});

describe('VitrineCartao · Premium', () => {
  it('the Premium card shows the price; the free card does not', () => {
    const premium = mount(VitrineCartao, {
      props: {
        ferramenta: ferramentaPorId('historico_placa'),
        premium: { gratis: 20, restantes: 20, precos: ['0.09'] },
      },
    });
    expect(premium.find('[data-vitrine-premium]').exists()).toBe(true);
    expect(premium.text()).toContain('Histórico da placa');
    expect(premium.text()).toContain('Restam 20 grátis');

    const gratis = mount(VitrineCartao, {
      props: { ferramenta: ferramentaPorId('cep') },
    });
    expect(gratis.find('[data-vitrine-premium]').exists()).toBe(false);
  });
});
