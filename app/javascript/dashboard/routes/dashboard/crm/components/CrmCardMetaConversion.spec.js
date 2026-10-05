import { config, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CrmCardMetaConversion from './CrmCardMetaConversion.vue';

const NS = 'CRM_KANBAN.META_SYNC_STATUS';
const render = (conversion, props = {}) =>
  mount(CrmCardMetaConversion, { props: { conversion, ...props } });

describe('CrmCardMetaConversion', () => {
  it('stays hidden without a row', () => {
    expect(render(null).text()).toBe('');
  });

  it('shows the sent pill and event as before', () => {
    const wrapper = render({ status: 'accepted', event_type: 'won' });

    expect(wrapper.text()).toContain(`${NS}.CARD_SENT`);
    expect(wrapper.text()).toContain(`${NS}.CARD_EVENT`);
  });

  it.each([
    ['won', 'Sale'],
    ['lost', 'Lost deal'],
    ['moved', 'Stage change'],
  ])('names the event %s in plain words, never the raw enum', (type, label) => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      missingWarn: false,
      fallbackWarn: false,
      messages: {
        en: {
          CRM_KANBAN: {
            META_SYNC_STATUS: {
              CARD_EVENT: 'Event: {event}',
              EVENT_WON: 'Sale',
              EVENT_LOST: 'Lost deal',
              EVENT_MOVED: 'Stage change',
            },
          },
        },
      },
    });
    const plugins = config.global.plugins;
    config.global.plugins = [i18n];
    const wrapper = mount(CrmCardMetaConversion, {
      props: { conversion: { status: 'accepted', event_type: type } },
    });
    config.global.plugins = plugins;

    expect(wrapper.text()).toContain(`Event: ${label}`);
    expect(wrapper.text()).not.toContain(`Event: ${type}`);
  });

  it('hides the event line for an unknown event type', () => {
    const wrapper = render({ status: 'accepted', event_type: 'mystery' });

    expect(wrapper.text()).not.toContain(`${NS}.CARD_EVENT`);
    expect(wrapper.text()).not.toContain('mystery');
  });

  it.each([
    ['missing_pixel', 'SKIP_MISSING_PIXEL'],
    ['event_too_old', 'SKIP_EVENT_TOO_OLD'],
    ['missing_credentials', 'SKIP_MISSING_CREDENTIALS'],
    ['no_meta_event', 'SKIP_NO_META_EVENT'],
    ['missing_signals', 'SKIP_MISSING_SIGNALS'],
  ])('explains the skip %s as "Not sent"', (reason, key) => {
    const wrapper = render({ status: 'skipped', error_message: reason });

    expect(wrapper.text()).toContain(`${NS}.LABEL_SKIPPED`);
    expect(wrapper.text()).toContain(`${NS}.${key}`);
    expect(wrapper.text()).not.toContain(reason);
  });

  it('keeps cards that never came from an ad quiet', () => {
    const wrapper = render({
      status: 'skipped',
      error_message: 'missing_ctwa_clid',
    });

    expect(wrapper.text()).toBe('');
  });

  it('explains a landing page card without ad signals (CA-3.4)', () => {
    const wrapper = render(
      { status: 'skipped', error_message: 'missing_ctwa_clid' },
      { fromWebsite: true }
    );

    expect(wrapper.text()).toContain(`${NS}.LABEL_SKIPPED`);
    expect(wrapper.text()).toContain(`${NS}.SKIP_MISSING_SIGNALS`);
    expect(wrapper.text()).not.toContain('missing_ctwa_clid');
  });

  it('leads the error with an actionable sentence and keeps the Meta text in details', () => {
    const wrapper = render({
      status: 'error',
      event_type: 'won',
      error_message: '(#100) Missing Permission',
    });
    const details = wrapper.find('details');

    expect(wrapper.text()).toContain(`${NS}.LABEL_ERROR`);
    expect(wrapper.text()).toContain(`${NS}.ERROR_HINT`);
    expect(details.exists()).toBe(true);
    expect(details.find('summary').text()).toBe(`${NS}.ERROR_RAW`);
    expect(details.text()).toContain('(#100) Missing Permission');
  });

  it('skips the details block when Meta sent no message', () => {
    const wrapper = render({ status: 'error', error_message: null });

    expect(wrapper.text()).toContain(`${NS}.ERROR_HINT`);
    expect(wrapper.find('details').exists()).toBe(false);
  });
});
