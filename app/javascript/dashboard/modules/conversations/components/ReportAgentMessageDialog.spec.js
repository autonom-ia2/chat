import { mount } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { withFullI18n } from 'test-i18n';

import ReportAgentMessageDialog from './ReportAgentMessageDialog.vue';
import MessageReportsAPI from 'dashboard/api/autonomia/messageReports';
import { useAlert } from 'dashboard/composables';

withFullI18n();

vi.mock('dashboard/api/autonomia/messageReports', () => ({
  default: { create: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Dialog is stubbed to a plain confirm button so the spec drives the same
// `confirm` event the real component emits; Select/TextArea are not exercised.
const stubs = {
  Dialog: {
    props: ['title', 'confirmButtonLabel', 'disableConfirmButton'],
    template:
      '<div><h2>{{ title }}</h2><slot /><button class="confirm" :disabled="disableConfirmButton" @click="$emit(\'confirm\')">{{ confirmButtonLabel }}</button></div>',
  },
  Select: true,
  TextArea: true,
};

const mountDialog = () =>
  mount(ReportAgentMessageDialog, {
    props: { messageId: 42 },
    global: { stubs },
  });

describe('ReportAgentMessageDialog', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('uses the attendant feedback copy', () => {
    const wrapper = mountDialog();

    expect(wrapper.find('h2').text()).toBe('Mark this reply as wrong');
    expect(wrapper.find('button.confirm').text()).toBe('Mark as wrong');
  });

  it('does not submit without a reason', async () => {
    const wrapper = mountDialog();

    expect(wrapper.find('button.confirm').attributes('disabled')).toBeDefined();
    await wrapper.vm.handleConfirm();

    expect(MessageReportsAPI.create).not.toHaveBeenCalled();
  });

  it('posts the report for the message and confirms to the attendant', async () => {
    MessageReportsAPI.create.mockResolvedValue({ data: {} });
    const wrapper = mountDialog();
    wrapper.vm.form.reportReason = 'incorrect_information';
    wrapper.vm.form.description = '  Wrong delivery time  ';
    await wrapper.vm.$nextTick();

    await wrapper.find('button.confirm').trigger('click');
    await wrapper.vm.$nextTick();

    expect(MessageReportsAPI.create).toHaveBeenCalledWith({
      message_id: 42,
      report_reason: 'incorrect_information',
      description: 'Wrong delivery time',
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Thanks — this reply was marked as wrong.'
    );
  });

  it('alerts when the report fails', async () => {
    MessageReportsAPI.create.mockRejectedValue(new Error('nope'));
    const wrapper = mountDialog();
    wrapper.vm.form.reportReason = 'other';

    await wrapper.vm.handleConfirm();

    expect(useAlert).toHaveBeenCalledWith(
      "We couldn't mark this reply. Please try again."
    );
  });
});
