import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import ContactAPI from 'dashboard/api/contacts';
import { withFullI18n } from '../../../../../../../vitest.i18n';
import CrmCardDrawer from './CrmCardDrawer.vue';

// Real copy (not i18n keys) so the assertions prove what the user actually reads.
const i18n = withFullI18n('en');
const { t } = i18n.global;

const recordPermission = ref(true);
vi.mock('dashboard/composables/useRelationshipPermissions', () => ({
  useRelationshipPermissions: () => ({
    canManageRelationshipRecords: recordPermission,
  }),
}));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: () => {},
}));
vi.mock('dashboard/api/contacts', () => ({
  default: {
    search: vi.fn().mockResolvedValue({ data: { payload: [] } }),
    update: vi.fn().mockResolvedValue({}),
  },
}));
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getFollowUpMessagingWindow: vi.fn().mockResolvedValue({ data: {} }),
  },
}));
vi.mock('dashboard/api/whatsappApiMessageTemplates', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: [] }) },
}));

const PROVIDER_ERROR = 'Meta API 131047 raw';
const now = new Date().toISOString();
const inOneHour = new Date(Date.now() + 60 * 60 * 1000).toISOString();

const mountDrawer = (props = {}) =>
  mount(CrmCardDrawer, {
    props: {
      show: true,
      mode: 'edit',
      card: { id: 5, title: 'Card A', stage_id: 10 },
      stages: [{ id: 10, name: 'Novo', color: '#2563eb' }],
      pipelineId: 1,
      ...props,
    },
    global: {
      stubs: {
        Dialog: {
          template: '<div />',
          methods: { open: vi.fn(), close: vi.fn() },
        },
        CrmCardRelationshipPanel: {
          name: 'CrmCardRelationshipPanel',
          template: '<div />',
          data: () => ({ companyAction: null, dirty: false, saving: false }),
          methods: { reset: vi.fn(), reload: vi.fn() },
        },
        CrmCardAiPanel: true,
        CrmCardSummaryPanel: true,
        CrmCardAutoFollowupStatus: true,
        PhoneNumberInput: true,
        CrmOpportunityContactPicker: true,
      },
    },
  });

const activity = (id, eventType, payload, extra = {}) => ({
  id,
  event_type: eventType,
  actor_type: 'system',
  payload,
  created_at: now,
  ...extra,
});

const mountTimeline = activities =>
  mountDrawer({
    initialTab: 'timeline',
    card: { id: 5, title: 'Card A', stage_id: 10, activities },
  });

describe('CrmCardDrawer timeline copy', () => {
  it('never shows the raw provider error of a failed follow-up', () => {
    const activities = [
      activity(1, 'follow_up_message_failed', {
        follow_up_id: 7,
        title: 'Enviar proposta',
        error: PROVIDER_ERROR,
      }),
      activity(
        2,
        'ai_followup_failed',
        { touch: 1, error: PROVIDER_ERROR, attempts: 1, retry_at: inOneHour },
        { metadata: { send_error: PROVIDER_ERROR } }
      ),
    ];
    const wrapper = mountTimeline(activities);

    activities.forEach(item => {
      expect(wrapper.vm.describeActivity(item).detail).not.toContain(
        PROVIDER_ERROR
      );
    });
    expect(wrapper.text()).toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_AI_FOLLOWUP_FAILED')
    );
    expect(wrapper.text()).not.toContain(PROVIDER_ERROR);
    expect(wrapper.text()).not.toContain('131047');
    wrapper.unmount();
  });

  it('shows the follow-up title on a failed manual follow-up', () => {
    const failed = activity(1, 'follow_up_message_failed', {
      follow_up_id: 7,
      title: 'Enviar proposta',
      error: PROVIDER_ERROR,
    });
    const wrapper = mountTimeline([failed]);

    expect(wrapper.vm.describeActivity(failed).detail).toBe('Enviar proposta');
    expect(wrapper.text()).toContain('Enviar proposta');
    wrapper.unmount();
  });

  it('shows attempt and next retry time on a failed AI follow-up', () => {
    const wrapper = mountDrawer();
    const { detail } = wrapper.vm.describeActivity(
      activity(1, 'ai_followup_failed', {
        touch: 3,
        attempts: 2,
        retry_at: inOneHour,
      })
    );

    expect(detail).toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPT', { attempt: 2 })
    );
    expect(detail).toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_RETRY_AT', { time: '' }).trim()
    );
    expect(detail).not.toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPTS_FINISHED')
    );
    wrapper.unmount();
  });

  it('says attempts are finished on the final AI follow-up failure', () => {
    const wrapper = mountDrawer();
    const { detail } = wrapper.vm.describeActivity(
      activity(1, 'ai_followup_failed', { attempts: 3, final: true })
    );

    expect(detail).toBe(
      [
        t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPT', { attempt: 3 }),
        t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPTS_FINISHED'),
      ].join(' · ')
    );
    wrapper.unmount();
  });

  it.each([[{}], [{ attempts: 0 }], [{ touch: 2 }]])(
    'shows no retry detail on a failed AI follow-up without a counter (%o)',
    payload => {
      const wrapper = mountDrawer();
      expect(
        wrapper.vm.describeActivity(activity(1, 'ai_followup_failed', payload))
          .detail
      ).toBe('');
      wrapper.unmount();
    }
  );

  it('says who received a reassigned meeting, in plain words', () => {
    const wrapper = mountDrawer();
    const reassigned = activity(
      1,
      'meeting_host_reassigned',
      { meeting_id: 9, from_user_id: 3, to_user_id: 4 },
      { labels: { to_user_id: 'Camila Torres' } }
    );

    const described = wrapper.vm.describeActivity(reassigned);

    expect(described.title).toBe('Meeting moved to Camila Torres');
    expect(described.icon).toBe('i-lucide-user-check');
    expect(described.title).not.toContain('#4');
    wrapper.unmount();
  });

  it('falls back to a nameless title when the new host name is missing', () => {
    const wrapper = mountDrawer();
    const { title } = wrapper.vm.describeActivity(
      activity(1, 'meeting_host_reassigned', { to_user_id: 4 })
    );

    expect(title).toBe('Meeting moved to someone else');
    wrapper.unmount();
  });

  it('has the pt_BR copy for the reassigned meeting', () => {
    const ptBR = { locale: 'pt_BR' };

    expect(
      t(
        'CRM_KANBAN.DRAWER.ACTIVITY_MEETING_HOST_REASSIGNED_TO',
        { name: 'Camila' },
        ptBR
      )
    ).toBe('Reunião passou para Camila');
    expect(
      t('CRM_KANBAN.DRAWER.ACTIVITY_MEETING_HOST_REASSIGNED', {}, ptBR)
    ).toBe('Reunião passou para outra pessoa');
  });

  it('does not use the cadence touch as an attempt counter on a sent AI follow-up', () => {
    const wrapper = mountDrawer();
    const { detail } = wrapper.vm.describeActivity(
      activity(1, 'ai_followup_sent', { touch: 2 })
    );

    expect(detail).toBe('');
    wrapper.unmount();
  });
});

describe('CrmCardDrawer loading states', () => {
  it('does not flash the empty history or conversations while details load', async () => {
    const wrapper = mountDrawer({
      initialTab: 'timeline',
      isLoadingDetails: true,
    });
    expect(wrapper.text()).not.toContain(
      t('CRM_KANBAN.DRAWER.NO_TIMELINE_TITLE')
    );
    wrapper.vm.activeTab = 'conversations';
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).not.toContain(
      t('CRM_KANBAN.DRAWER.NO_CONVERSATIONS_TITLE')
    );

    await wrapper.setProps({ isLoadingDetails: false });
    expect(wrapper.text()).toContain(
      t('CRM_KANBAN.DRAWER.NO_CONVERSATIONS_TITLE')
    );
    wrapper.vm.activeTab = 'timeline';
    await wrapper.vm.$nextTick();
    expect(wrapper.text()).toContain(t('CRM_KANBAN.DRAWER.NO_TIMELINE_TITLE'));
    wrapper.unmount();
  });
});

describe('CrmCardDrawer contact save failure', () => {
  it('shows the generic translated error, not the server message, and does not refresh the card', async () => {
    const serverMessage = 'PG::UniqueViolation: email already taken';
    ContactAPI.update.mockRejectedValueOnce({
      response: { data: { message: serverMessage } },
      message: serverMessage,
    });
    const wrapper = mountDrawer({
      initialTab: 'contact',
      card: {
        id: 5,
        title: 'Card A',
        stage_id: 10,
        contact: { id: 42, name: 'Original' },
      },
    });
    wrapper.vm.contactForm.name = 'Updated person';

    await wrapper.vm.saveContact();
    await flushPromises();

    const generic = t('CRM_KANBAN.RELATIONSHIP.SAVE_ERROR');
    expect(generic).not.toBe('CRM_KANBAN.RELATIONSHIP.SAVE_ERROR');
    expect(wrapper.vm.contactError).toBe(generic);
    expect(wrapper.text()).not.toContain(serverMessage);
    expect(wrapper.emitted('refreshCard')).toBeUndefined();
    wrapper.unmount();
  });

  // #1196 (J6-A4): the meeting the AI booked is identifiable on the card.
  it('says the AI booked the meeting, and only for AI bookings', () => {
    const wrapper = mountDrawer();
    const byAi = activity(1, 'meeting_scheduled', {
      title: 'Conversa de 30 min',
      source: 'ai',
    });
    const byLink = activity(2, 'meeting_scheduled', {
      title: 'Conversa de 30 min',
      source: 'public_link',
    });

    expect(wrapper.vm.describeActivity(byAi).detail).toBe(
      'Booked by the AI: Conversa de 30 min'
    );
    expect(wrapper.vm.describeActivity(byLink).detail).not.toContain('AI');
    wrapper.unmount();
  });
});
