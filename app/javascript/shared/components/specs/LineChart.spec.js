import { mount, flushPromises } from '@vue/test-utils';
import LineChart from '../charts/LineChart.vue';

vi.mock('@chatwoot/viz', () => ({
  LineChart: {
    name: 'VizLineChart',
    props: [
      'data',
      'ariaLabel',
      'showValues',
      'showTooltip',
      'pointRadius',
      'yTickCount',
      'xInset',
    ],
    template: `
      <div class="viz-line-mock">
        <svg>
          <g
            v-for="(label, index) in data.categories"
            :key="index"
            class="cw-viz-line__x-tick"
          ><text>{{ label }}</text></g>
        </svg>
      </div>
    `,
  },
}));

describe('LineChart.vue', () => {
  const collection = {
    labels: [
      '00:00 full',
      '01:00 full',
      '02:00 full',
      '03:00 full',
      '04:00 full',
      '05:00 full',
      '06:00 full',
      '07:00 full',
    ],
    datasets: [
      {
        id: 'delivered',
        label: 'Delivered',
        borderColor: '#16a34a',
        data: [1, 2, 3, 4, 5, 6, 7, 8],
      },
    ],
  };

  it('preserves all data while reducing only visible x-axis labels', async () => {
    const wrapper = mount(LineChart, {
      props: {
        collection,
        showValues: false,
        showTooltip: true,
        pointRadius: 4,
        yTickCount: 5,
        xInset: 12,
        xLabelStride: 3,
        xTickLabels: ['00h', '01h', '02h', '03h', '04h', '05h', '06h', '07h'],
        pointBorderColor: 'rgb(var(--solid-1))',
      },
    });

    await flushPromises();

    const chart = wrapper.findComponent({ name: 'VizLineChart' });
    expect(chart.props('data').categories).toEqual(collection.labels);
    expect(chart.props('data').series[0].data).toEqual(
      collection.datasets[0].data
    );
    expect(chart.props('showValues')).toBe(false);
    expect(chart.props('showTooltip')).toBe(true);
    expect(chart.props('pointRadius')).toBe(4);
    expect(chart.props('yTickCount')).toBe(5);
    expect(chart.props('xInset')).toBe(12);
    expect(chart.props('data').series[0].pointBorderColor).toBe(
      'rgb(var(--solid-1))'
    );

    const ticks = wrapper.findAll('.cw-viz-line__x-tick');
    expect(ticks.map(tick => tick.text())).toEqual([
      '00h',
      '01h',
      '02h',
      '03h',
      '04h',
      '05h',
      '06h',
      '07h',
    ]);
    expect(ticks).toHaveLength(8);
    expect(
      ticks.map((tick, index) => ({
        index,
        hidden: tick.classes().includes('hidden'),
      }))
    ).toEqual([
      { index: 0, hidden: false },
      { index: 1, hidden: true },
      { index: 2, hidden: true },
      { index: 3, hidden: false },
      { index: 4, hidden: true },
      { index: 5, hidden: true },
      { index: 6, hidden: false },
      { index: 7, hidden: false },
    ]);

    await wrapper.setProps({ xTickLabels: [] });
    await flushPromises();

    expect(
      wrapper.findAll('.cw-viz-line__x-tick').map(tick => tick.text())
    ).toEqual(collection.labels);
  });

  it('keeps the existing default presentation for other consumers', async () => {
    const wrapper = mount(LineChart, { props: { collection } });
    await flushPromises();

    const chart = wrapper.findComponent({ name: 'VizLineChart' });
    expect(chart.props('showValues')).toBe(true);
    expect(chart.props('showTooltip')).toBe(true);
    expect(chart.props('pointRadius')).toBe(3);
    expect(wrapper.findAll('.cw-viz-line__x-tick.hidden')).toHaveLength(0);
  });
});
