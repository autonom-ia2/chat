import { mount, flushPromises } from '@vue/test-utils';
import { nextTick } from 'vue';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useAlert } from 'dashboard/composables';
import {
  crmSubjectsChange,
  notifyCrmSubjectsChanged,
} from 'dashboard/routes/dashboard/crm/composables/useCrmConversationStages';
import CrmRepasseDoAssunto from './CrmRepasseDoAssunto.vue';

const user = vi.hoisted(() => ({ current: null }));

vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getConversationSubjects: vi.fn(),
    passSubjectToTeam: vi.fn(),
    keepSubjectWithMe: vi.fn(),
  },
}));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmConversationStages',
  async () => {
    const { ref } = await import('vue');
    return {
      crmSubjectsChange: ref({ conversationId: null, version: 0 }),
      notifyCrmSubjectsChanged: vi.fn(),
    };
  }
);
vi.mock('dashboard/composables/store', async () => {
  const { ref } = await import('vue');
  user.current = ref({ id: 7 });
  return { useMapGetter: () => user.current };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const REPASSE = {
  card_id: 31,
  pipeline_name: 'Agentes de IA',
  equipe_online: true,
};
const SEM_NINGUEM = { ...REPASSE, equipe_online: false };

const wrappers = [];
afterEach(() => wrappers.splice(0).forEach(wrapper => wrapper.unmount()));

const mountRepasse = ({ assigneeId = 7, repasse = REPASSE } = {}) => {
  CrmKanbanAPI.getConversationSubjects.mockResolvedValue({
    data: { payload: [], repasse },
  });
  const wrapper = mount(CrmRepasseDoAssunto, {
    props: { conversationId: 9, assigneeId },
    attachTo: document.body,
  });
  wrappers.push(wrapper);
  return wrapper;
};

const box = wrapper => wrapper.find('[data-crm-repasse-do-assunto]');

beforeEach(() => {
  vi.clearAllMocks();
  user.current.value = { id: 7 };
});

describe('CrmRepasseDoAssunto (#1606, decisão "a")', () => {
  it('mostra a sugestão a quem está com a conversa', async () => {
    const wrapper = mountRepasse();
    await flushPromises();

    expect(box(wrapper).exists()).toBe(true);
    expect(box(wrapper).text()).toContain(
      'CRM_KANBAN.CONVERSATION.REPASSE.TEXT'
    );
    expect(wrapper.find('[data-crm-repasse-pass]').exists()).toBe(true);
    expect(CrmKanbanAPI.getConversationSubjects).toHaveBeenCalledWith(9);
  });

  it('não mostra nem pergunta ao servidor quando outra pessoa está com a conversa', async () => {
    const wrapper = mountRepasse({ assigneeId: 8 });
    await flushPromises();

    expect(box(wrapper).exists()).toBe(false);
    expect(CrmKanbanAPI.getConversationSubjects).not.toHaveBeenCalled();
  });

  it('sem sugestão no servidor, nada aparece', async () => {
    const wrapper = mountRepasse({ repasse: null });
    await flushPromises();

    expect(box(wrapper).exists()).toBe(false);
  });

  it('Passar para a equipe: chama o servidor com o card, avisa e some', async () => {
    CrmKanbanAPI.passSubjectToTeam.mockResolvedValue({});
    const wrapper = mountRepasse();
    await flushPromises();

    await wrapper.find('[data-crm-repasse-pass]').trigger('click');
    await flushPromises();

    expect(CrmKanbanAPI.passSubjectToTeam).toHaveBeenCalledWith(9, 31);
    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(notifyCrmSubjectsChanged).toHaveBeenCalledWith(9);
    expect(box(wrapper).exists()).toBe(false);
  });

  it('Ficar com a conversa: chama o servidor com o card e some, sem aviso', async () => {
    CrmKanbanAPI.keepSubjectWithMe.mockResolvedValue({});
    const wrapper = mountRepasse();
    await flushPromises();

    await wrapper.find('[data-crm-repasse-keep]').trigger('click');
    await flushPromises();

    expect(CrmKanbanAPI.keepSubjectWithMe).toHaveBeenCalledWith(9, 31);
    expect(CrmKanbanAPI.passSubjectToTeam).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
    expect(box(wrapper).exists()).toBe(false);
  });

  describe('ninguém da equipe nova online (decisão 2a)', () => {
    const nobody = wrapper => wrapper.find('[data-crm-repasse-nobody-online]');

    it('Passar primeiro avisa que a conversa vai esperar, sem chamar o servidor', async () => {
      const wrapper = mountRepasse({ repasse: SEM_NINGUEM });
      await flushPromises();
      expect(nobody(wrapper).exists()).toBe(false);

      await wrapper.find('[data-crm-repasse-pass]').trigger('click');
      await flushPromises();

      expect(CrmKanbanAPI.passSubjectToTeam).not.toHaveBeenCalled();
      expect(nobody(wrapper).text()).toContain(
        'CRM_KANBAN.CONVERSATION.REPASSE.NOBODY_ONLINE'
      );
      expect(wrapper.find('[data-crm-repasse-pass]').attributes('label')).toBe(
        'CRM_KANBAN.CONVERSATION.REPASSE.PASS_ANYWAY'
      );
    });

    it('Passar mesmo assim chama o servidor e some', async () => {
      CrmKanbanAPI.passSubjectToTeam.mockResolvedValue({});
      const wrapper = mountRepasse({ repasse: SEM_NINGUEM });
      await flushPromises();

      await wrapper.find('[data-crm-repasse-pass]').trigger('click');
      await wrapper.find('[data-crm-repasse-pass]').trigger('click');
      await flushPromises();

      expect(CrmKanbanAPI.passSubjectToTeam).toHaveBeenCalledWith(9, 31);
      expect(box(wrapper).exists()).toBe(false);
    });

    it('presença desconhecida (null): não diz "ninguém online" e passa direto', async () => {
      CrmKanbanAPI.passSubjectToTeam.mockResolvedValue({});
      const wrapper = mountRepasse({
        repasse: { ...REPASSE, equipe_online: null },
      });
      await flushPromises();

      await wrapper.find('[data-crm-repasse-pass]').trigger('click');
      await flushPromises();

      expect(nobody(wrapper).exists()).toBe(false);
      expect(CrmKanbanAPI.passSubjectToTeam).toHaveBeenCalledWith(9, 31);
    });

    it('Ficar com a conversa, no aviso, fica e não passa', async () => {
      CrmKanbanAPI.keepSubjectWithMe.mockResolvedValue({});
      const wrapper = mountRepasse({ repasse: SEM_NINGUEM });
      await flushPromises();

      await wrapper.find('[data-crm-repasse-pass]').trigger('click');
      await wrapper.find('[data-crm-repasse-keep]').trigger('click');
      await flushPromises();

      expect(CrmKanbanAPI.keepSubjectWithMe).toHaveBeenCalledWith(9, 31);
      expect(CrmKanbanAPI.passSubjectToTeam).not.toHaveBeenCalled();
      expect(box(wrapper).exists()).toBe(false);
    });
  });

  it('erro do servidor avisa e mantém a sugestão para tentar de novo', async () => {
    CrmKanbanAPI.passSubjectToTeam.mockRejectedValue(new Error('422'));
    const wrapper = mountRepasse();
    await flushPromises();

    await wrapper.find('[data-crm-repasse-pass]').trigger('click');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledTimes(1);
    expect(box(wrapper).exists()).toBe(true);
  });

  it('o aviso em tempo real (assuntos mudaram) lê de novo e mostra sem recarregar', async () => {
    const wrapper = mountRepasse({ repasse: null });
    await flushPromises();
    expect(box(wrapper).exists()).toBe(false);

    CrmKanbanAPI.getConversationSubjects.mockResolvedValue({
      data: { payload: [], repasse: REPASSE },
    });
    crmSubjectsChange.value = { conversationId: 9, version: 1 };
    await nextTick();
    await flushPromises();

    expect(box(wrapper).exists()).toBe(true);
  });
});
