import { mount, flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmOpportunityForm from './CrmOpportunityForm.vue';

vi.mock('dashboard/api/crmKanban', () => ({ default: { getStages: vi.fn() } }));
const makeForm = props =>
  mount(CrmOpportunityForm, {
    props: {
      pipelines: [
        { id: 1, name: 'Comercial' },
        { id: 2, name: 'Renovações' },
      ],
      pipelineId: 1,
      stages: [{ id: 10, name: 'Novo' }],
      agents: [{ id: 8, name: 'Responsável' }],
      inboxes: [{ id: 9, name: 'Comercial' }],
      canManage: true,
      ...props,
    },
    global: { stubs: { CrmOpportunityContactPicker: true } },
  });
let wrapper;
beforeEach(() => vi.clearAllMocks());
afterEach(() => wrapper?.unmount());

it('starts with two sections, no validation errors and no fake create-contact control', () => {
  wrapper = makeForm();
  expect(wrapper.find('[data-opportunity-relationship]').exists()).toBe(true);
  expect(wrapper.find('[data-opportunity-details]').exists()).toBe(true);
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.vm.canSave).toBe(false);
  expect(wrapper.findAll('select')).toHaveLength(0);
});
it('requires an explicit contact or an explicit choice to continue without one', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Negociação';
  expect(wrapper.vm.canSave).toBe(false);
  wrapper.vm.contact = { id: 42, name: 'Mariana' };
  expect(wrapper.vm.canSave).toBe(true);
  await wrapper.vm.changeMode('none');
  expect(wrapper.vm.contact).toBeNull();
  expect(wrapper.vm.canSave).toBe(true);
});
it('keeps the commercial draft when changing contact mode or selecting a person', async () => {
  wrapper = makeForm();
  Object.assign(wrapper.vm.form, {
    title: 'Título comercial',
    valueAmount: '1200.45',
    description: 'Contexto',
    score: 70,
  });
  wrapper.vm.contact = { id: 42, name: 'Mariana' };
  await wrapper.vm.changeMode('none');
  await wrapper.vm.changeMode('existing');
  wrapper.vm.contact = { id: 43, name: 'João' };
  expect(wrapper.vm.form).toMatchObject({
    title: 'Título comercial',
    valueAmount: '1200.45',
    description: 'Contexto',
    score: 70,
  });
});
it('submits only opportunity fields and the existing contact ID, never a new contact object', async () => {
  wrapper = makeForm();
  Object.assign(wrapper.vm.form, {
    title: ' Negociação ',
    valueAmount: '1200.45',
    ownerId: 8,
    inboxId: 9,
    currency: 'USD',
    priority: 'urgent',
    score: 0,
    expectedCloseAt: '2026-11-15',
  });
  wrapper.vm.contact = {
    id: 42,
    name: 'Mariana',
    company_id: 7,
    company: { id: 7 },
    email: 'mariana@example.com',
  };
  await wrapper.vm.$nextTick();
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual({
    title: 'Negociação',
    description: '',
    pipeline_id: 1,
    stage_id: 10,
    value_cents: 120045,
    owner_id: 8,
    inbox_id: 9,
    currency: 'USD',
    priority: 'urgent',
    score: 0,
    expected_close_at: '2026-11-15',
    contact_id: 42,
    idempotencyKey: expect.any(String),
  });
});
it('does not send a stale contact after choosing no relationship', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Sem vínculo';
  wrapper.vm.contact = { id: 42 };
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).not.toHaveProperty('contact_id');
  expect(wrapper.vm.summary).toBe('CRM_KANBAN.OPPORTUNITY.SUMMARY_NONE');
});
it('blocks synchronous duplicate submissions and editing mode during the request', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Teste';
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  wrapper.vm.changeMode('existing');
  expect(wrapper.emitted('save')).toHaveLength(1);
  expect(wrapper.vm.mode).toBe('none');
  expect(wrapper.vm.sending).toBe(true);
});
it('keeps the payload and idempotency key for a retry of the same request', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Retry';
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  const [first, failed] = wrapper.emitted('save')[0];
  failed();
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(wrapper.vm.form.title).toBe('Retry');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')[1][0]).toEqual(first);
});
it('uses another key when the user changes the submitted intent', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Original';
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  const [first, failed] = wrapper.emitted('save')[0];
  failed();
  wrapper.vm.form.title = 'Corrigido';
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')[1][0].idempotencyKey).not.toBe(
    first.idempotencyKey
  );
});
it('loads stages for the chosen pipeline without clearing the commercial draft', async () => {
  let resolve;
  CrmKanbanAPI.getStages.mockReturnValue(
    new Promise(done => {
      resolve = done;
    })
  );
  wrapper = makeForm();
  wrapper.vm.form.title = 'Título preservado';
  wrapper.vm.changeMode('none');
  wrapper.vm.form.pipelineId = 2;
  expect(wrapper.vm.form.stageId).toBe('');
  expect(wrapper.vm.canSave).toBe(false);
  resolve({ data: { payload: [{ id: 20, name: 'Revisão' }] } });
  await flushPromises();
  expect(wrapper.vm.form.stageId).toBe(20);
  expect(wrapper.vm.form.title).toBe('Título preservado');
  expect(wrapper.vm.canSave).toBe(true);
});
it('ignores a late stage response from the previous pipeline', async () => {
  let resolveOld;
  CrmKanbanAPI.getStages.mockImplementation(id =>
    id === 2
      ? new Promise(done => {
          resolveOld = done;
        })
      : Promise.resolve({ data: { payload: [{ id: 10, name: 'Novo' }] } })
  );
  wrapper = makeForm();
  wrapper.vm.form.pipelineId = 2;
  wrapper.vm.form.pipelineId = 1;
  await flushPromises();
  resolveOld({ data: { payload: [{ id: 20, name: 'Antiga resposta' }] } });
  await flushPromises();
  expect(wrapper.vm.form.stageId).toBe(10);
  expect(wrapper.vm.loadedStages.map(item => item.id)).toEqual([10]);
});
it('retains the form on stage-loading failure and offers a real retry', async () => {
  CrmKanbanAPI.getStages.mockRejectedValue(new Error('Offline'));
  wrapper = makeForm();
  wrapper.vm.form.title = 'Preservado';
  wrapper.vm.form.pipelineId = 2;
  await flushPromises();
  expect(wrapper.vm.stageError).toBe(true);
  expect(wrapper.vm.canSave).toBe(false);
  CrmKanbanAPI.getStages.mockResolvedValue({
    data: { payload: [{ id: 20, name: 'Retomada' }] },
  });
  await wrapper.vm.loadStages();
  expect(wrapper.vm.form.title).toBe('Preservado');
  expect(wrapper.vm.form.stageId).toBe(20);
});
it('never resets the title or selected contact when the board stages refresh', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Em edição';
  wrapper.vm.contact = { id: 42 };
  await wrapper.setProps({ stages: [{ id: 10, name: 'Novo nome da etapa' }] });
  expect(wrapper.vm.form.title).toBe('Em edição');
  expect(wrapper.vm.contact.id).toBe(42);
});
it('does not accept a stage outside the selected pipeline', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Inválida';
  wrapper.vm.changeMode('none');
  wrapper.vm.form.stageId = 999;
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')).toBeUndefined();
});
it('reveals invalid extra fields before native validation and does not submit', async () => {
  wrapper = makeForm();
  wrapper.vm.form.title = 'Inválido';
  wrapper.vm.changeMode('none');
  wrapper.vm.form.score = 101;
  await wrapper.vm.$nextTick();
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.vm.more).toBe(true);
  expect(wrapper.emitted('save')).toBeUndefined();
});
it('blocks creating when card management permission is absent', async () => {
  wrapper = makeForm({ canManage: false });
  wrapper.vm.form.title = 'Sem permissão';
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')).toBeUndefined();
});
it('accepts a pipeline ID supplied as a route string without sending the wrong stage', () => {
  wrapper = makeForm({ pipelineId: '1' });
  wrapper.vm.form.title = 'Rota';
  wrapper.vm.changeMode('none');
  expect(wrapper.vm.canSave).toBe(true);
});
