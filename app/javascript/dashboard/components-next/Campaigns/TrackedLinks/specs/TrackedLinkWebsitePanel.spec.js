import { mount, flushPromises } from '@vue/test-utils';
import CtwaTrackedLinksAPI from 'dashboard/api/ctwaTrackedLinks';
import { useAlert } from 'dashboard/composables';
import TrackedLinkWebsitePanel from '../TrackedLinkWebsitePanel.vue';

vi.mock('dashboard/api/ctwaTrackedLinks', () => ({
  default: { update: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const AD_PARAMS =
  'utm_source=meta&utm_medium=paid&utm_campaign={{campaign.name}}&utm_term={{adset.name}}&utm_content={{ad.name}}&utm_id={{campaign.id}}';
const link = (overrides = {}) => ({
  id: 7,
  name: 'LP Seguro Viagem',
  code: 'AB3CDE',
  usage: 'website',
  allowed_origins: ['https://placement.com.br'],
  last_signal_at: null,
  signal_url: 'https://chat.hub2you.ai/l/AB3CDE/clicks',
  ad_url_params: AD_PARAMS,
  campaigns: [],
  ...overrides,
});
const mountPanel = (props = {}) =>
  mount(TrackedLinkWebsitePanel, {
    props: { link: link(), canManage: true, ...props },
  });
const buttonWith = (wrapper, key) =>
  wrapper
    .findAll('button')
    .find(button =>
      button.text().includes(`CRM_KANBAN.TRACKED_LINKS.PAGE.${key}`)
    );

describe('TrackedLinkWebsitePanel', () => {
  const writeText = vi.fn();

  beforeEach(() => {
    vi.clearAllMocks();
    Object.assign(navigator, { clipboard: { writeText } });
  });

  it('shows the ad text and copies it exactly', async () => {
    writeText.mockResolvedValue();
    const wrapper = mountPanel();

    expect(wrapper.text()).toContain(AD_PARAMS);
    await buttonWith(wrapper, 'COPY_AD_PARAMS').trigger('click');
    await flushPromises();

    expect(writeText).toHaveBeenCalledWith(AD_PARAMS);
    expect(useAlert).toHaveBeenCalledWith('CRM_KANBAN.TRACKED_LINKS.COPIED');
  });

  it('copies the signal address for the developer', async () => {
    writeText.mockResolvedValue();
    const wrapper = mountPanel();

    await buttonWith(wrapper, 'COPY_SIGNAL_URL').trigger('click');
    await flushPromises();

    expect(writeText).toHaveBeenCalledWith(
      'https://chat.hub2you.ai/l/AB3CDE/clicks'
    );
  });

  it('tells the user when copying fails', async () => {
    writeText.mockRejectedValue(new Error('denied'));
    const wrapper = mountPanel();

    await buttonWith(wrapper, 'COPY_AD_PARAMS').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.COPY_FAILED'
    );
  });

  it.each([
    [null, 'SIGNAL_NEVER', 'bg-n-slate-8'],
    [
      new Date(Date.now() - 5 * 60 * 1000).toISOString(),
      'SIGNAL_LAST',
      'bg-n-teal-9',
    ],
    [
      new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString(),
      'SIGNAL_LAST',
      'bg-n-amber-9',
    ],
  ])('shows the last signal %s as %s', (lastSignalAt, key, dot) => {
    const wrapper = mountPanel({
      link: link({ last_signal_at: lastSignalAt }),
    });
    const status = wrapper.get('[role="status"]');

    expect(status.text()).toContain(`CRM_KANBAN.TRACKED_LINKS.PAGE.${key}`);
    expect(status.find(`.${dot}`).exists()).toBe(true);
  });

  it('edits the allowed pages through PATCH and hands back the saved link', async () => {
    const saved = link({
      allowed_origins: [
        'https://placement.com.br',
        'https://lp.placement.com.br',
      ],
    });
    CtwaTrackedLinksAPI.update.mockResolvedValue({ data: { payload: saved } });
    const wrapper = mountPanel();

    await buttonWith(wrapper, 'EDIT').trigger('click');
    await wrapper
      .get('textarea')
      .setValue(
        'https://placement.com.br\nhttps://LP.placement.com.br/cotacao'
      );
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(CtwaTrackedLinksAPI.update).toHaveBeenCalledWith(7, {
      allowed_origins: [
        'https://placement.com.br',
        'https://lp.placement.com.br',
      ],
    });
    expect(wrapper.emitted('updated')[0][0]).toEqual(saved);
    expect(wrapper.find('textarea').exists()).toBe(false);
  });

  it('does not save invalid pages and keeps the form open on server error', async () => {
    CtwaTrackedLinksAPI.update.mockRejectedValue(new Error('422'));
    const wrapper = mountPanel();
    await buttonWith(wrapper, 'EDIT').trigger('click');

    await wrapper.get('textarea').setValue('http://placement.com.br');
    await wrapper.get('form').trigger('submit');
    expect(CtwaTrackedLinksAPI.update).not.toHaveBeenCalled();

    await wrapper.get('textarea').setValue('https://placement.com.br');
    await wrapper.get('form').trigger('submit');
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain(
      'CRM_KANBAN.TRACKED_LINKS.PAGE.ORIGINS_SAVE_ERROR'
    );
    expect(wrapper.emitted('updated')).toBeUndefined();
  });

  it('warns when the site went over the daily signal limit', () => {
    const blocked = mountPanel({ link: link({ signals_blocked: true }) });
    const open = mountPanel({ link: link({ signals_blocked: false }) });

    expect(
      blocked.get('[data-testid="tracked-link-signals-blocked"]').text()
    ).toContain('CRM_KANBAN.TRACKED_LINKS.PAGE.SIGNALS_BLOCKED');
    expect(
      open.find('[data-testid="tracked-link-signals-blocked"]').exists()
    ).toBe(false);
  });

  it('hides editing for people who cannot manage campaigns', () => {
    const wrapper = mountPanel({ canManage: false });

    expect(buttonWith(wrapper, 'EDIT')).toBeUndefined();
    expect(wrapper.text()).toContain('https://placement.com.br');
  });
});
