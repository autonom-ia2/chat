import { shallowMount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import instagramClient from 'dashboard/api/channel/instagramClient';
import { useAlert } from 'dashboard/composables';
import Reauthorize from './Reauthorize.vue';

vi.mock('dashboard/api/channel/instagramClient', () => ({
  default: { generateAuthorization: vi.fn(), getTesterConfiguration: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
withFullI18n('pt_BR');

describe('Instagram reauthorization regression', () => {
  it('keeps the existing OAuth authorization without a tester selection or configuration request', async () => {
    instagramClient.generateAuthorization.mockResolvedValue({
      data: { url: window.location.href },
    });
    const wrapper = shallowMount(Reauthorize, { props: { inbox: { id: 42 } } });
    wrapper
      .findComponent({ name: 'InboxReconnectionRequired' })
      .vm.$emit('reauthorize');
    await flushPromises();
    expect(instagramClient.generateAuthorization).toHaveBeenCalledWith({
      inbox_id: 42,
      return_to: 'inbox',
    });
    expect(instagramClient.getTesterConfiguration).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('keeps the translated OAuth error alert on request failure', async () => {
    instagramClient.generateAuthorization.mockRejectedValue(
      new Error('network')
    );
    const wrapper = shallowMount(Reauthorize, { props: { inbox: { id: 42 } } });
    wrapper
      .findComponent({ name: 'InboxReconnectionRequired' })
      .vm.$emit('reauthorize');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(expect.any(String));
    expect(useAlert.mock.calls[0][0]).not.toContain('INBOX_MGMT');
    wrapper.unmount();
  });
});
