import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import { useCrmFollowUpReminders } from 'dashboard/composables/useCrmFollowUpReminders';
import BlocoCombinado from '../BlocoCombinado.vue';
import { criarI18n, criarStore } from './apoio';

// #2138 — "Combinado": o atrasado primeiro, a data falada no fuso da conta
// (navegador em UTC), 403 esconde, erro com "Tentar de novo", sem lembrete some,
// e lê de novo quando o aviso do lembrete entra ou sai.
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getFollowUps: vi.fn() },
}));

// Sexta, 23/10/2026, 22h30 em São Paulo = sábado 01h30 em UTC (já é "amanhã" no navegador).
const AGORA = new Date('2026-10-24T01:30:00Z');

const resposta = lembretes => ({
  data: { payload: lembretes, meta: { count: lembretes.length } },
});
const erroCom = status =>
  Object.assign(new Error('x'), { response: { status } });

const montar = () => {
  const { store } = criarStore();
  return mount(BlocoCombinado, {
    props: { contactId: 9 },
    global: { plugins: [store, criarI18n()] },
  });
};

enableAutoUnmount(afterEach);

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(AGORA);
  window.globalConfig = { CRM_KANBAN_ENABLED: 'true' };
});
afterEach(() => {
  vi.useRealTimers();
  const { dequeueReminder, activeReminder } = useCrmFollowUpReminders();
  while (activeReminder.value) dequeueReminder();
});

describe('BlocoCombinado', () => {
  it('pede só os abertos do contato e põe o atrasado primeiro, em âmbar', async () => {
    CrmKanbanAPI.getFollowUps.mockResolvedValue(
      resposta([
        // Vem do servidor por due_at; o futuro mais perto antes do atrasado de propósito.
        {
          id: 2,
          title: 'Mandar a proposta',
          status: 'pending',
          due_at: '2026-10-24T17:30:00Z', // sábado 14h30 em SP
        },
        {
          id: 1,
          title: 'Ligar para confirmar',
          status: 'overdue',
          due_at: '2026-10-22T13:00:00Z', // quinta 10h em SP = ontem
        },
      ])
    );
    const wrapper = montar();
    await flushPromises();

    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledWith({
      contact_id: 9,
      status: ['pending', 'overdue'],
      per_page: 20,
    });
    const linhas = wrapper.findAll('li');
    expect(linhas.map(l => l.text())).toEqual([
      'Era para ontem às 10h: Ligar para confirmar.',
      'Amanhã às 14h30: Mandar a proposta.',
    ]);
    expect(linhas[0].attributes('data-atrasado')).toBe('true');
    expect(linhas[0].classes()).toContain('text-n-amber-11');
    expect(linhas[1].attributes('data-atrasado')).toBeUndefined();
    expect(wrapper.text()).toContain('Combinado');
  });

  it('lembrete sem título usa o tipo, e o automático diz que vai uma mensagem', async () => {
    CrmKanbanAPI.getFollowUps.mockResolvedValue(
      resposta([
        {
          id: 1,
          title: '',
          follow_up_type: 'call',
          status: 'pending',
          due_at: '2026-10-24T13:00:00Z',
        },
        {
          id: 2,
          title: 'Oi',
          automation_mode: 'auto_send_message',
          status: 'pending',
          due_at: '2026-10-27T12:00:00Z',
        },
      ])
    );
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.findAll('li').map(l => l.text())).toEqual([
      'Amanhã às 10h: Ligar.',
      'Terça às 9h vai uma mensagem automática.',
    ]);
  });

  it('mostra até 3 e "Ver os outros {n}" abre o resto ali mesmo', async () => {
    const lembretes = [1, 2, 3, 4, 5].map(id => ({
      id,
      title: `Item ${id}`,
      status: 'pending',
      due_at: `2026-11-0${id}T13:00:00Z`,
    }));
    CrmKanbanAPI.getFollowUps.mockResolvedValue(resposta(lembretes));
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.findAll('li')).toHaveLength(3);
    const ver = wrapper
      .findAll('button')
      .find(b => b.text() === 'Ver os outros 2');
    await ver.trigger('click');
    expect(wrapper.findAll('li')).toHaveLength(5);
    expect(wrapper.text()).toContain('Mostrar menos');
  });

  it('enquanto carrega, mostra o esqueleto', async () => {
    CrmKanbanAPI.getFollowUps.mockReturnValue(new Promise(() => {}));
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-test-id="esqueleto"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Combinado');
  });

  it('sem lembrete aberto, o bloco não aparece', async () => {
    CrmKanbanAPI.getFollowUps.mockResolvedValue(resposta([]));
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-test-id="bloco-combinado"]').exists()).toBe(
      false
    );
  });

  it('403 (sem acesso ao CRM) esconde o bloco, sem mensagem', async () => {
    CrmKanbanAPI.getFollowUps.mockRejectedValue(erroCom(403));
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.find('[data-test-id="bloco-combinado"]').exists()).toBe(
      false
    );
    expect(wrapper.text()).toBe('');
  });

  it('outro erro mostra a frase e "Tentar de novo" lê de novo', async () => {
    CrmKanbanAPI.getFollowUps.mockRejectedValueOnce(erroCom(500));
    const wrapper = montar();
    await flushPromises();
    expect(wrapper.text()).toContain('Não deu para carregar esta parte agora.');

    CrmKanbanAPI.getFollowUps.mockResolvedValueOnce(
      resposta([
        {
          id: 1,
          title: 'Ligar',
          status: 'pending',
          due_at: '2026-10-24T13:00:00Z',
        },
      ])
    );
    await wrapper.get('[data-test-id="erro-da-parte"] button').trigger('click');
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledTimes(2);
    expect(wrapper.findAll('li').map(l => l.text())).toEqual([
      'Amanhã às 10h: Ligar.',
    ]);
  });

  it('lê de novo quando o aviso do lembrete deste contato sai da fila (concluído ou dispensado)', async () => {
    const { enqueueReminder, dequeueReminder } = useCrmFollowUpReminders();
    CrmKanbanAPI.getFollowUps.mockResolvedValue(
      resposta([
        {
          id: 1,
          title: 'Ligar',
          status: 'overdue',
          due_at: '2026-10-22T13:00:00Z',
        },
      ])
    );
    const wrapper = montar();
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledTimes(1);

    // O lembrete venceu (crm.follow_up.due): o aviso entra na fila.
    enqueueReminder({ id: 1, contact_id: 9 });
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledTimes(2);

    // A pessoa concluiu pelo aviso: ele sai da fila e o painel lê de novo.
    CrmKanbanAPI.getFollowUps.mockResolvedValue(resposta([]));
    dequeueReminder();
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledTimes(3);
    expect(wrapper.find('[data-test-id="bloco-combinado"]').exists()).toBe(
      false
    );
  });

  it('o aviso de outro contato não faz ler de novo', async () => {
    const { enqueueReminder } = useCrmFollowUpReminders();
    CrmKanbanAPI.getFollowUps.mockResolvedValue(resposta([]));
    montar();
    await flushPromises();
    enqueueReminder({ id: 77, contact_id: 123 });
    await flushPromises();
    expect(CrmKanbanAPI.getFollowUps).toHaveBeenCalledTimes(1);
  });
});
