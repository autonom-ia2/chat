import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import VitrineExperimente from '../../vitrine/components/VitrineExperimente.vue';
import { ferramentaPorId } from '../../vitrine/catalogo';
import { emReais } from '../../vitrine/premium';

// #2858 F7, decisão A do Rodrigo (11/11): o card Premium também tem o "Experimente". Enquanto há grátis, o teste usa uma
// delas, e a tela diz isso. Acabadas as grátis, o próprio botão mostra o preço ("Testar por R$ 0,09"; na faixa, "Testar
// por até R$ 0,15") e é a confirmação: sem janela de confirmação. Cópia real em pt_BR.
withFullI18n('pt_BR');

const experimentar = vi.hoisted(() => vi.fn());
vi.mock('../../vitrine/useVitrine', () => ({
  useVitrine: () => ({ experimentar }),
}));

const montadas = [];
const montar = (id, premium) => {
  const wrapper = mount(VitrineExperimente, {
    props: { ferramenta: ferramentaPorId(id), premium },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};

const botao = wrapper => wrapper.find('[data-experimentar]');
const rodar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  await flushPromises();
};

beforeEach(() => experimentar.mockReset());
afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('VitrineExperimente · Premium', () => {
  it('with free lookups left, the button is the usual one and the screen says the test uses one of them', async () => {
    experimentar.mockResolvedValue({ situacao: 'encontrado', dados: {} });
    const wrapper = montar('historico_placa', {
      gratis: 20,
      restantes: 12,
      precos: ['0.09'],
    });
    expect(botao(wrapper).text()).toBe('Experimentar');
    expect(wrapper.find('[data-experimente-gratis]').text()).toBe(
      'O teste usa 1 das grátis do mês.'
    );
    await rodar(wrapper);
    expect(experimentar).toHaveBeenCalledWith(
      'historico_placa',
      wrapper.find('[data-experimente-valor]').element.value,
      false
    );
  });

  it('with no free lookups left, the button shows the single price and that click pays', async () => {
    experimentar.mockResolvedValue({ situacao: 'encontrado', dados: {} });
    const wrapper = montar('historico_placa', {
      gratis: 20,
      restantes: 0,
      precos: ['0.09'],
    });
    expect(botao(wrapper).text()).toBe(`Testar por ${emReais('0.09')}`);
    expect(wrapper.find('[data-experimente-gratis]').exists()).toBe(false);
    await rodar(wrapper);
    expect(experimentar.mock.calls[0][2]).toBe(true);
  });

  it('on a price range, the button shows "up to" the highest price', () => {
    const wrapper = montar('certidoes_empresa', {
      gratis: 20,
      restantes: 0,
      precos: ['0.06', '0.15'],
    });
    expect(botao(wrapper).text()).toBe(`Testar por até ${emReais('0.15')}`);
  });

  it('the free lookups ran out meanwhile: the server asks for the price click and nothing is charged', async () => {
    experimentar.mockResolvedValue({ situacao: 'confirmar_preco' });
    const wrapper = montar('historico_placa', {
      gratis: 20,
      restantes: 1,
      precos: ['0.09'],
    });
    await rodar(wrapper);
    expect(wrapper.find('[data-experimente-aviso]').text()).toBe(
      'As grátis do mês acabaram. Para testar, clique no botão com o preço.'
    );
  });

  it('a document the source refuses is said in plain words', async () => {
    experimentar.mockResolvedValue({ situacao: 'documento_invalido' });
    const wrapper = montar('conferir_pessoa', {
      gratis: 20,
      restantes: 5,
      precos: ['0.06', '0.09'],
    });
    await rodar(wrapper);
    expect(wrapper.find('[data-experimente-aviso]').text()).toBe(
      'A consulta foi feita, mas esse número não existe. Confira e tente de novo.'
    );
  });

  it('every Premium card asks for what a lay person writes', () => {
    [
      'certidoes_empresa',
      'raio_x_empresa',
      'conferir_pessoa',
      'historico_placa',
      'risco_endereco',
      'imovel_rural',
      'contato_empresa',
    ].forEach(id => {
      const wrapper = montar(id, { gratis: 20, restantes: 20, precos: [] });
      expect(wrapper.find('label').text()).not.toBe('');
      expect(wrapper.find('[data-experimente-valor]').element.value).not.toBe(
        ''
      );
    });
  });
});
