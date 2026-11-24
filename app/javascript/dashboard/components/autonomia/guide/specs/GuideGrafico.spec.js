import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import GuideGrafico from '../GuideGrafico.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) => (valores ? `${key}:${JSON.stringify(valores)}` : key),
    locale: ref('pt_BR'),
  }),
}));

// #3158 (B8a) — o gráfico sob a resposta do Guia. O BarChart da tela
// Relatórios fica de dublê: aqui importa o que ele recebe, não o SVG.
const BarChartDuble = {
  name: 'BarChart',
  props: ['data', 'ariaLabel', 'height', 'maxBarWidth', 'showValues'],
  template: '<div data-bar-chart />',
};

const montar = props =>
  mount(GuideGrafico, {
    props: { de: '2026-10-01', ate: '2026-10-31', ...props },
    global: { stubs: { BarChart: BarChartDuble } },
  });

describe('GuideGrafico', () => {
  it('ranking: uma linha por barra, com o nome inteiro e o número no idioma', () => {
    const wrapper = montar({
      modo: 'ranking',
      titulo: 'Conversas resolvidas por pessoa',
      barras: [
        { rotulo: 'Ana Souza', valor: 1280 },
        { rotulo: 'Bruno Lima', valor: 97 },
      ],
    });

    const linhas = wrapper.findAll('li');
    expect(wrapper.find('figcaption').text()).toBe(
      'Conversas resolvidas por pessoa'
    );
    expect(linhas).toHaveLength(2);
    expect(linhas[0].text()).toContain('Ana Souza');
    expect(linhas[0].text()).toContain('1.280');
    expect(wrapper.find('[data-bar-chart]').exists()).toBe(false);
  });

  it('ranking: a maior barra ocupa a largura toda e as outras em proporção', () => {
    const wrapper = montar({
      modo: 'ranking',
      titulo: 't',
      barras: [
        { rotulo: 'A', valor: 200 },
        { rotulo: 'B', valor: 50 },
      ],
    });

    const larguras = wrapper
      .findAll('li [aria-hidden="true"] > span')
      .map(barra => barra.attributes('style'));
    expect(larguras).toEqual(['width: 100%;', 'width: 25%;']);
  });

  it('série: o BarChart da tela recebe colunas, medida e o título como rótulo', () => {
    const wrapper = montar({
      modo: 'serie',
      titulo: 'Conversas por dia',
      medida: 'Conversas',
      barras: [
        { rotulo: '01/10', valor: 45 },
        { rotulo: '02/10', valor: 38 },
      ],
    });

    const grafico = wrapper.findComponent(BarChartDuble);
    expect(wrapper.find('ol').exists()).toBe(false);
    expect(grafico.props('ariaLabel')).toBe('Conversas por dia');
    expect(grafico.props('data').categories).toEqual(['01/10', '02/10']);
    expect(grafico.props('data').series[0]).toEqual(
      expect.objectContaining({ label: 'Conversas', data: [45, 38] })
    );
    expect(grafico.props('showValues')).toBe(true);
  });

  it('série longa: o número some de cima das colunas', () => {
    const barras = Array.from({ length: 31 }, (_, dia) => ({
      rotulo: String(dia + 1),
      valor: dia,
    }));

    const wrapper = montar({ modo: 'serie', titulo: 't', barras });

    expect(wrapper.findComponent(BarChartDuble).props('showValues')).toBe(
      false
    );
  });

  it('diz de onde vêm os números e o período, no formato do idioma', () => {
    const wrapper = montar({ modo: 'ranking', titulo: 't', barras: [] });

    expect(wrapper.find('p').text()).toBe(
      'AUTONOMIA_GUIDE.GRAFICO.FONTE:{"de":"01/10","ate":"31/10"}'
    );
  });
});
