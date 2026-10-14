import { mount, flushPromises } from '@vue/test-utils';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import CrmOpportunityForm from './CrmOpportunityForm.vue';

vi.mock('dashboard/api/crmKanban', () => ({
  default: { getStages: vi.fn(), getOwnerOptions: vi.fn() },
}));
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
      canCreateContact: true,
      ...props,
    },
    global: {
      stubs: {
        CrmOpportunityContactPicker: true,
        CrmOpportunityRegistration: {
          template: '<div />',
          data: () => ({ canSave: true }),
          methods: { validate: () => true, showError: vi.fn() },
        },
      },
    },
  });
let wrapper;
beforeEach(() => vi.clearAllMocks());
afterEach(() => wrapper?.unmount());

it('starts a contextual form with the existing person, no invented title and a clean draft', async () => {
  const person = {
    id: 42,
    name: 'Mariana',
    company: { id: 7, name: 'Empresa atual' },
  };
  wrapper = makeForm({ passo: 1, initialContact: person });
  expect(wrapper.vm.contact).toEqual(person);
  expect(wrapper.vm.form.title).toBe('');
  expect(wrapper.vm.mode).toBe('existing');
  expect(wrapper.vm.dirty).toBe(false);
  wrapper.vm.form.title = 'Nova negociação';
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  const payload = wrapper.emitted('save')[0][0];
  expect(payload).toMatchObject({ title: 'Nova negociação', contact_id: 42 });
  expect(payload).not.toHaveProperty('relationship');
  expect(payload).not.toHaveProperty('company');
});
it('tracks clearing or replacing the contextual contact without altering commercial fields', async () => {
  wrapper = makeForm({ passo: 1, initialContact: { id: 42, name: 'Mariana' } });
  wrapper.vm.contact = null;
  expect(wrapper.vm.dirty).toBe(true);
  wrapper.vm.form.valueAmount = '250.50';
  wrapper.vm.contact = { id: 43, name: 'João' };
  expect(wrapper.vm.dirty).toBe(true);
  expect(wrapper.vm.form.valueAmount).toBe('250.50');
  await wrapper.vm.changeMode('none');
  expect(wrapper.vm.contact).toBeNull();
  expect(wrapper.vm.dirty).toBe(true);
});
it('never restores the contextual contact over a deliberate later selection', async () => {
  wrapper = makeForm({ passo: 1, initialContact: { id: 42, name: 'Mariana' } });
  wrapper.vm.contact = { id: 43, name: 'João' };
  wrapper.vm.form.title = 'Preservado';
  await wrapper.setProps({ stages: [{ id: 10, name: 'Novo atualizado' }] });
  expect(wrapper.vm.contact.id).toBe(43);
  expect(wrapper.vm.form.title).toBe('Preservado');
});

it('starts on step 1 with the details hidden, no validation errors and no native select', () => {
  wrapper = makeForm({ passo: 1 });
  expect(wrapper.find('[data-opportunity-relationship]').isVisible()).toBe(
    true
  );
  expect(wrapper.find('[data-opportunity-details]').isVisible()).toBe(false);
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  expect(wrapper.vm.canSave).toBe(false);
  expect(wrapper.findAll('select')).toHaveLength(0);
});
it('explains the new-contact permission without blocking an existing contact', () => {
  wrapper = makeForm({ passo: 1, canCreateContact: false });
  expect(wrapper.find('[data-record-read-only]').exists()).toBe(false);
  expect(wrapper.text()).toContain('CRM_CARD.CRIAR.PESSOA.NOVA.SEM_PERMISSAO');
  expect(
    wrapper.find('[data-pessoa="new"]').attributes('disabled')
  ).toBeDefined();
  expect(
    wrapper.find('[data-pessoa="existing"]').attributes('disabled')
  ).toBeUndefined();
});
it('requires an explicit contact or an explicit choice to continue without one', async () => {
  wrapper = makeForm({ passo: 1 });
  wrapper.vm.form.title = 'Negociação';
  expect(wrapper.vm.canSave).toBe(false);
  wrapper.vm.contact = { id: 42, name: 'Mariana' };
  expect(wrapper.vm.canSave).toBe(true);
  await wrapper.vm.changeMode('none');
  expect(wrapper.vm.contact).toBeNull();
  expect(wrapper.vm.canSave).toBe(true);
});
it('keeps the commercial draft when changing contact mode or selecting a person', async () => {
  wrapper = makeForm({ passo: 1 });
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
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 1 });
  wrapper.vm.form.title = 'Sem vínculo';
  wrapper.vm.contact = { id: 42 };
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.find('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).not.toHaveProperty('contact_id');
  expect(wrapper.vm.summary).toBe('CRM_CARD.CRIAR.RESUMO_SEM');
});
it('blocks synchronous duplicate submissions and editing mode during the request', async () => {
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 2 });
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
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Em edição';
  wrapper.vm.contact = { id: 42 };
  await wrapper.setProps({ stages: [{ id: 10, name: 'Novo nome da etapa' }] });
  expect(wrapper.vm.form.title).toBe('Em edição');
  expect(wrapper.vm.contact.id).toBe(42);
});
it('does not accept a stage outside the selected pipeline', async () => {
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Inválida';
  wrapper.vm.changeMode('none');
  wrapper.vm.form.stageId = 999;
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')).toBeUndefined();
});
it('reveals invalid extra fields before native validation and does not submit', async () => {
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Inválido';
  wrapper.vm.changeMode('none');
  wrapper.vm.form.score = 101;
  await wrapper.vm.$nextTick();
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.vm.more).toBe(true);
  expect(wrapper.find('details').element.open).toBe(true);
  expect(wrapper.emitted('save')).toBeUndefined();
});
it('blocks creating when card management permission is absent', async () => {
  wrapper = makeForm({ passo: 2, canManage: false });
  wrapper.vm.form.title = 'Sem permissão';
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')).toBeUndefined();
});
it('accepts a pipeline ID supplied as a route string without sending the wrong stage', () => {
  wrapper = makeForm({ passo: 2, pipelineId: '1' });
  wrapper.vm.form.title = 'Rota';
  wrapper.vm.changeMode('none');
  expect(wrapper.vm.canSave).toBe(true);
});

it('submits one composed payload and keeps commercial fields independent of the new registration', async () => {
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Commercial intent';
  wrapper.vm.changeMode('new');
  Object.assign(wrapper.vm.registrationDraft, {
    name: 'Person',
    companyMode: 'new',
    companyName: 'Company',
  });
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  const payload = wrapper.emitted('save')[0][0];
  expect(payload.title).toBe('Commercial intent');
  expect(payload).not.toHaveProperty('contact_id');
  expect(payload.relationship.contact.name).toBe('Person');
  expect(payload.relationship.company.attributes.name).toBe('Company');
  expect(wrapper.vm.summary).toBe('CRM_CARD.CRIAR.RESUMO_COM');
});
it('preserves a new-person draft between modes but never submits its stale values for existing contact', async () => {
  wrapper = makeForm({ passo: 1 });
  wrapper.vm.form.title = 'Commercial';
  wrapper.vm.changeMode('new');
  wrapper.vm.registrationDraft.name = 'Draft person';
  wrapper.vm.changeMode('existing');
  wrapper.vm.contact = { id: 7 };
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')[0][0]).toMatchObject({
    title: 'Commercial',
    contact_id: 7,
  });
  expect(wrapper.emitted('save')[0][0]).not.toHaveProperty('relationship');
  expect(wrapper.vm.registrationDraft.name).toBe('Draft person');
});
it('retains new contact edits in dirty tracking even before a commercial title is entered', () => {
  wrapper = makeForm({ passo: 1 });
  expect(wrapper.vm.dirty).toBe(false);
  wrapper.vm.registrationDraft.name = 'Person';
  expect(wrapper.vm.dirty).toBe(true);
});
it('blocks synchronous second submission while validating the new registration', async () => {
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Commercial';
  wrapper.vm.changeMode('new');
  wrapper.vm.registrationDraft.name = 'Person';
  await wrapper.vm.$nextTick();
  let finish;
  wrapper.vm.registration.validate = () =>
    new Promise(resolve => {
      finish = resolve;
    });
  const first = wrapper.vm.submit();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')).toBeUndefined();
  finish(true);
  await first;
  expect(wrapper.emitted('save')).toHaveLength(1);
});
it('forwards authoritative contact errors without resetting either part of the draft', async () => {
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Commercial';
  wrapper.vm.changeMode('new');
  wrapper.vm.registrationDraft.name = 'Person';
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  const showError = vi.spyOn(wrapper.vm.registration, 'showError');
  const detail = {
    code: 'crm.opportunity.contact_exists',
    section: 'contact',
    fields: {},
    matches: [],
  };
  wrapper.emitted('save')[0][1]({ response: { data: { error: detail } } });
  expect(showError).toHaveBeenCalledWith(detail);
  expect(wrapper.emitted('passo')).toEqual([[1]]);
  expect(wrapper.vm.sending).toBe(false);
  expect(wrapper.vm.form.title).toBe('Commercial');
  expect(wrapper.vm.registrationDraft.name).toBe('Person');
});
it('keeps the same key and entire new registration for a retry after a lost response', async () => {
  wrapper = makeForm({ passo: 2 });
  wrapper.vm.form.title = 'Retry whole set';
  wrapper.vm.changeMode('new');
  wrapper.vm.registrationDraft.name = 'Person';
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  const [first, failed] = wrapper.emitted('save')[0];
  failed(new Error('Connection lost'));
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')[1][0]).toEqual(first);
});

it('separates new shared records from existing and standalone opportunities', async () => {
  wrapper = makeForm({ passo: 1, canCreateContact: false });
  wrapper.vm.changeMode('new');
  expect(wrapper.vm.mode).toBe('existing');
  wrapper.vm.form.title = 'Permitted negotiation';
  wrapper.vm.contact = { id: 42, name: 'Existing' };
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')[0][0]).toMatchObject({
    contact_id: 42,
    title: 'Permitted negotiation',
  });
  expect(wrapper.emitted('save')[0][0]).not.toHaveProperty('relationship');
  wrapper.emitted('save')[0][1](new Error('No write in component test'));
  wrapper.vm.changeMode('none');
  await wrapper.vm.$nextTick();
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')[1][0]).not.toHaveProperty('relationship');
  expect(wrapper.emitted('save')[1][0]).not.toHaveProperty('contact_id');
});
it('stops a new-record draft after record permission revocation without deleting it', async () => {
  wrapper = makeForm({ passo: 1 });
  wrapper.vm.changeMode('new');
  wrapper.vm.form.title = 'Keep draft';
  await wrapper.vm.$nextTick();
  await wrapper.setProps({ canCreateContact: false });
  expect(wrapper.vm.canSave).toBe(false);
  await wrapper.vm.submit();
  expect(wrapper.emitted('save')).toBeUndefined();
  expect(wrapper.vm.form.title).toBe('Keep draft');
});

it('offers as owner only who handles the pipeline in the chosen inbox', async () => {
  CrmKanbanAPI.getOwnerOptions.mockResolvedValue({
    data: { payload: { cards: {}, blocked: [8] } },
  });
  wrapper = makeForm({
    passo: 2,
    agents: [
      { id: 8, name: 'Sem o funil' },
      { id: 11, name: 'Com o funil' },
    ],
  });
  wrapper.vm.form.ownerId = 8;
  wrapper.vm.form.inboxId = 9;
  await flushPromises();

  expect(CrmKanbanAPI.getOwnerOptions).toHaveBeenCalledWith({
    pipelineId: 1,
    inboxId: 9,
  });
  expect(wrapper.vm.ownerOptions.map(option => option.value)).toEqual(['', 11]);
  expect(wrapper.vm.form.ownerId).toBe('');
});

describe('gaveta nova (#1423)', () => {
  it('passo 1: três escolhas grandes, sem o cabeçalho numerado antigo', async () => {
    wrapper = makeForm({ passo: 1 });
    expect(wrapper.findAll('[data-pessoa]')).toHaveLength(3);
    expect(wrapper.text()).not.toContain('CRM_KANBAN.OPPORTUNITY.RELATIONSHIP');
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.OPPORTUNITY.CONTINUE_NONE'
    );
    await wrapper.find('[data-pessoa="none"]').trigger('click');
    expect(wrapper.vm.mode).toBe('none');
    expect(wrapper.vm.summary).toBe('CRM_CARD.CRIAR.RESUMO_SEM');
  });

  it('passo 2: palavras do Negócio, moeda por escolha e sem campo de data nativo', () => {
    wrapper = makeForm({ passo: 2 });
    const texto = wrapper.text();
    expect(texto).toContain('CRM_CARD.NEGOCIO.NOME');
    expect(texto).not.toContain('CRM_KANBAN.OPPORTUNITY.OPPORTUNITY');
    expect(texto).not.toContain('CRM_KANBAN.DRAWER.VALUE_WITH_CURRENCY');
    expect(texto).not.toContain('CRM_KANBAN.OPPORTUNITY.CURRENCY');
    expect(wrapper.find('[data-campo-valor]').exists()).toBe(true);
    expect(wrapper.find('input[type="date"]').exists()).toBe(false);
    expect(wrapper.findAll('select')).toHaveLength(0);
  });

  it('passo 2: o aviso de nome vazio só aparece depois de mexer no campo', async () => {
    wrapper = makeForm({ passo: 2 });
    expect(wrapper.text()).not.toContain('CRM_CARD.NEGOCIO.TITULO_FALTA');
    const nome = wrapper.find('[data-negocio-titulo] input');
    await nome.setValue('Plano');
    await nome.setValue('');
    expect(wrapper.text()).toContain('CRM_CARD.NEGOCIO.TITULO_FALTA');
  });

  it('passo 2: cadastro novo inválido volta ao passo 1 sem enviar', async () => {
    wrapper = makeForm({ passo: 2 });
    wrapper.vm.form.title = 'Plano';
    wrapper.vm.changeMode('new');
    await wrapper.vm.$nextTick();
    wrapper.vm.registration.validate = () => false;
    await wrapper.vm.submit();
    expect(wrapper.emitted('save')).toBeUndefined();
    expect(wrapper.emitted('passo')).toEqual([[1]]);
  });

  it('passo 2: envia a moeda escolhida e o mesmo payload de sempre', async () => {
    wrapper = makeForm({ passo: 2 });
    await wrapper.vm.changeMode('none');
    wrapper.vm.form.title = 'Plano anual';
    wrapper.vm.form.valueAmount = '1200';
    wrapper.vm.form.currency = 'USD';
    await wrapper.vm.$nextTick();
    await wrapper.vm.submit();
    expect(wrapper.emitted('save')[0][0]).toMatchObject({
      title: 'Plano anual',
      value_cents: 120000,
      currency: 'USD',
      stage_id: 10,
    });
  });
});
