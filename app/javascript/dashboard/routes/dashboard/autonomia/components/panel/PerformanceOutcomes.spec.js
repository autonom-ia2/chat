import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import { withFullI18n } from 'test-i18n';

import PerformanceOutcomes from './PerformanceOutcomes.vue';

// The labels asserted below are translated copy (see vitest.setup.js).
withFullI18n();

const outcomes = {
  handled: 12,
  resolved_without_human: 5,
  handed_off: 4,
  reopened: 1,
  wrong_replies: 2,
};

const mountOutcomes = (props = {}) =>
  mount(PerformanceOutcomes, {
    props: { outcomes, ...props },
    global: { stubs: { Icon: true } },
  });

describe('PerformanceOutcomes', () => {
  it('renders the five outcome numbers with their labels', () => {
    const wrapper = mountOutcomes();
    const tiles = wrapper.findAll('button[data-metric]');

    expect(tiles.map(tile => tile.attributes('data-metric'))).toEqual([
      'handled',
      'resolved_without_human',
      'handed_off',
      'reopened',
      'wrong_replies',
    ]);
    expect(tiles[1].text()).toContain('5');
    expect(tiles[1].text()).toContain('Resolved without a human');
    expect(tiles[4].text()).toContain('Replies marked as wrong');
  });

  it('emits the metric key when a number is clicked', async () => {
    const wrapper = mountOutcomes();

    await wrapper.find('button[data-metric="handed_off"]').trigger('click');

    expect(wrapper.emitted('select')).toEqual([['handed_off']]);
  });

  it('falls back to zero when a metric is missing', () => {
    const wrapper = mountOutcomes({ outcomes: {} });

    expect(wrapper.find('button[data-metric="reopened"]').text()).toContain(
      '0'
    );
  });
});
