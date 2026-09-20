import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/emailCampaignProtection.json';
import crm from 'dashboard/i18n/locale/en/crm.json';
import CampaignTimelineChart from '../CampaignTimelineChart.vue';
import LineChart from 'shared/components/charts/LineChart.vue';

vi.mock('shared/components/charts/LineChart.vue', () => ({
  default: {
    name: 'LineChart',
    props: {
      collection: Object,
      ariaLabel: String,
      height: Number,
      pointRadius: Number,
      showValues: Boolean,
      showTooltip: Boolean,
      yTickCount: Number,
      xInset: Number,
      xLabelStride: Number,
      xTickLabels: Array,
      pointBorderColor: String,
    },
    template: '<div data-line-chart />',
  },
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  fallbackLocale: false,
  messages: { en: { ...en, ...crm } },
});

const hourlySeries = Array.from({ length: 24 }, (_, hour) => ({
  bucket: `2026-09-19T${String(hour).padStart(2, '0')}:00:00Z`,
  delivered: hour * 10,
  open: hour * 2,
  click: hour,
}));

describe('CampaignTimelineChart.vue', () => {
  it('renders a clean daily chart with aggregated KPIs and no point labels', () => {
    const series = [
      {
        bucket: '2026-09-14T00:00:00Z',
        delivered: 1594,
        open: 373,
        click: 111,
      },
      { bucket: '2026-09-15T00:00:00Z', delivered: 90, open: 8, click: 0 },
    ];
    const wrapper = mount(CampaignTimelineChart, {
      props: {
        series,
        source: { delivery_mode: 'ses' },
        interval: 'day',
      },
      global: { plugins: [i18n] },
    });

    expect(wrapper.get('[data-timeline-metric="delivered"]').text()).toContain(
      '1,684'
    );
    expect(wrapper.get('[data-timeline-metric="opened"]').text()).toContain(
      '381'
    );
    expect(wrapper.get('[data-timeline-metric="clicked"]').text()).toContain(
      '111'
    );

    const chart = wrapper.findComponent(LineChart);
    expect(chart.props('showValues')).toBe(false);
    expect(chart.props('showTooltip')).toBe(true);
    expect(chart.props('pointRadius')).toBe(4);
    expect(chart.props('xLabelStride')).toBe(1);
    expect(
      chart.props('collection').datasets.map(dataset => dataset.data)
    ).toEqual([
      [1594, 90],
      [373, 8],
      [111, 0],
    ]);
  });

  it('keeps every hourly point but limits the visible axis density', async () => {
    const wrapper = mount(CampaignTimelineChart, {
      props: {
        series: hourlySeries,
        source: { delivery_mode: 'ses' },
        interval: 'hour',
      },
      global: { plugins: [i18n] },
    });

    const chart = wrapper.findComponent(LineChart);
    expect(chart.props('collection').labels).toHaveLength(24);
    expect(chart.props('collection').labels[0]).toMatch(/:00/);
    expect(chart.props('collection').datasets[0].data).toHaveLength(24);
    expect(chart.props('xLabelStride')).toBe(8);
    expect(chart.props('pointRadius')).toBe(3);
    expect(chart.props('pointBorderColor')).toBe('rgb(var(--solid-1))');
    expect(chart.props('xTickLabels')).toHaveLength(24);
    expect(
      chart.props('xTickLabels').every(label => !label.includes('Sep'))
    ).toBe(true);

    const hourButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'By hour');
    expect(hourButton.attributes('aria-pressed')).toBe('true');

    const dayButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'By day');
    await dayButton.trigger('click');
    expect(wrapper.emitted('update:interval')).toEqual([['day']]);
  });

  it('does not claim delivery confirmation for direct-inbox campaigns', () => {
    const wrapper = mount(CampaignTimelineChart, {
      props: {
        series: hourlySeries.slice(0, 2),
        source: { delivery_mode: 'direct_inbox' },
        interval: 'hour',
      },
      global: { plugins: [i18n] },
    });

    expect(wrapper.get('[data-timeline-metric="delivered"]').text()).toContain(
      'Accepted by sending service'
    );
    expect(wrapper.get('[data-timeline-delivery-hint]').exists()).toBe(true);
  });
});
