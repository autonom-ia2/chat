import { mount, config } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaign.json';
import AiAdjustPreview from '../AiAdjustPreview.vue';

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const mountPreview = props =>
  mount(AiAdjustPreview, {
    props: {
      beforeHtml: '<p>antes</p>',
      afterHtml: '<p>depois</p>',
      summary: 'Made the button green.',
      ...props,
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
    },
  });

const panel = (wrapper, key) =>
  wrapper.find(`[data-test="ai-adjust-panel-${key}"]`);

// #1095: the adjusted e-mail is shown before and after; nothing changes until "Apply".
describe('AiAdjustPreview', () => {
  it('shows before and after with what changed', () => {
    const wrapper = mountPreview();

    expect(panel(wrapper, 'before').find('iframe').attributes('srcdoc')).toBe(
      '<p>antes</p>'
    );
    expect(panel(wrapper, 'after').find('iframe').attributes('srcdoc')).toBe(
      '<p>depois</p>'
    );
    expect(panel(wrapper, 'after').find('iframe').attributes('sandbox')).toBe(
      ''
    );
    expect(wrapper.find('[data-test="ai-adjust-summary"]').text()).toBe(
      'Made the button green.'
    );
  });

  it('shows one side at a time on small screens, after first, and switches', async () => {
    const wrapper = mountPreview();

    expect(panel(wrapper, 'after').classes()).toContain('flex');
    expect(panel(wrapper, 'before').classes()).toContain('hidden');
    await wrapper.find('[data-test="ai-adjust-view-before"]').trigger('click');

    expect(panel(wrapper, 'before').classes()).toContain('flex');
    expect(panel(wrapper, 'after').classes()).toContain('hidden');
    expect(
      wrapper
        .find('[data-test="ai-adjust-view-before"]')
        .attributes('aria-pressed')
    ).toBe('true');
  });

  it('applies or discards on request', async () => {
    const wrapper = mountPreview();

    await wrapper.find('[data-test="ai-adjust-apply"]').trigger('click');
    await wrapper.find('[data-test="ai-adjust-discard"]').trigger('click');

    expect(wrapper.emitted('apply')).toHaveLength(1);
    expect(wrapper.emitted('discard')).toHaveLength(1);
  });

  it('does not let apply an e-mail Gmail would clip', () => {
    const wrapper = mountPreview({ afterHtml: 'x'.repeat(102 * 1024 + 1) });

    expect(wrapper.find('[data-test="ai-adjust-too-large"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-test="ai-adjust-apply"]').attributes('disabled')
    ).toBeDefined();
  });
});
