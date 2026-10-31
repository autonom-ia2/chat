import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import crmEn from 'dashboard/i18n/locale/en/crm.json';
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CrmPipelineDrawer from './CrmPipelineDrawer.vue';

// The drawer pulls global config + permissions; stub them so we can mount it in
// isolation and focus on the form-reset reactivity that the realtime-churn fix
// changed.
// #1548 (passo 2): o pacote da conta (`autonomia_pacote`) vem da conta atual.
const conta = vi.hoisted(() => ({ autonomia_pacote: null }));
vi.mock('vuex', () => ({
  useStore: () => ({
    getters: {
      getCurrentAccountId: 1,
      'accounts/getAccount': () => conta,
    },
  }),
}));
vi.mock('../composables/useCrmPermissions', () => ({
  useCrmPermissions: () => ({ canManageAi: ref(false) }),
}));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: () => {},
}));
// #2027: o link do Google pede token_manage; aqui a função tem a chave.
// #2414 F1.3: as ações da etapa pedem a chave das regras automáticas; aqui também tem.
vi.mock('dashboard/composables/useCanManage', () => ({
  usePermissionGranted: () => ref(true),
  useCanManage: () => ref(true),
}));
vi.mock('dashboard/api/crmGoogleConversionFeed', () => ({
  default: {
    create: vi.fn().mockResolvedValue({ data: { url: 'https://feed/x' } }),
  },
}));

// Fresh array + fresh objects every call: this is exactly what the Vuex board
// getter returns on each realtime card event / poll (board.stages is rebuilt).
const makeStages = () => [
  {
    id: 10,
    name: 'Novo',
    color: '#2563eb',
    win_probability: 10,
    wip_limit: '',
  },
  {
    id: 11,
    name: 'Em atendimento',
    color: '#0891b2',
    win_probability: 35,
    wip_limit: '',
  },
];

const mountDrawer = (props = {}) =>
  mount(CrmPipelineDrawer, {
    props: {
      show: true,
      mode: 'edit',
      pipeline: { id: 1, name: 'Funil' },
      stages: makeStages(),
      ...props,
    },
    global: {
      stubs: { CrmStageAutomationsPanel: true, CrmAiSettingsPanel: true },
    },
  });

describe('CrmPipelineDrawer form reset vs realtime churn', () => {
  it('keeps in-progress stage edits when props.stages churns with the same ids', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.form.stages[0].name = 'Novo Editado';
    await wrapper.vm.$nextTick();

    // Realtime event: same stages, brand-new array/object references.
    await wrapper.setProps({ stages: makeStages() });

    expect(wrapper.vm.form.stages[0].name).toBe('Novo Editado');
  });

  it('resets the form when the drawer opens', async () => {
    const wrapper = mountDrawer({ show: false });
    wrapper.vm.form.name = 'dirty';

    await wrapper.setProps({ show: true });

    expect(wrapper.vm.form.name).toBe('Funil');
  });

  it('resets the form when the target pipeline identity changes', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.form.name = 'dirty';

    await wrapper.setProps({ pipeline: { id: 2, name: 'Outro Funil' } });

    expect(wrapper.vm.form.name).toBe('Outro Funil');
  });

  it('drops a server-deleted stage while preserving edits to the survivors', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.form.stages[0].name = 'Novo Editado';
    await wrapper.vm.$nextTick();

    // Stage id 11 deleted server-side; the board refetch drops it from props.
    await wrapper.setProps({ stages: [makeStages()[0]] });

    expect(wrapper.vm.form.stages).toHaveLength(1);
    expect(wrapper.vm.form.stages[0].id).toBe(10);
    expect(wrapper.vm.form.stages[0].name).toBe('Novo Editado');
  });

  it('keeps the open stage to name, sentence and color, with remove in the footer', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.openStage(wrapper.vm.form.stages[1]);
    await wrapper.vm.$nextTick();

    // #1384: uma decisão por bloco; a Meta foi para Anúncios e tirar, para o rodapé.
    expect(wrapper.find('details').exists()).toBe(false);
    expect(wrapper.text()).toContain('CRM_FUNIL.ETAPA.COR');
    expect(wrapper.text()).not.toContain(
      'CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS'
    );
    expect(wrapper.get('footer [data-funil-tirar]').text()).toContain(
      'CRM_FUNIL.ETAPA.TIRAR'
    );
  });

  it('removes an unsaved stage from the footer and goes back', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    await wrapper.get('[data-tipo="VENDER"]').trigger('click');
    wrapper.vm.view = 'etapas';
    const total = wrapper.vm.form.stages.length;
    wrapper.vm.addStage();
    await wrapper.vm.$nextTick();
    expect(wrapper.vm.view).toBe('stage');

    await wrapper.get('[data-funil-tirar]').trigger('click');

    expect(wrapper.vm.form.stages).toHaveLength(total);
    expect(wrapper.vm.view).toBe('etapas');
  });

  it('keeps the drawer open when AI settings fail to save', async () => {
    const wrapper = mountDrawer();
    wrapper.vm.aiPanel = { saveSettings: vi.fn().mockResolvedValue(false) };
    await wrapper.vm.onSubmit();
    expect(wrapper.emitted('save')).toBeUndefined();
    wrapper.unmount();
  });
});

describe('CrmPipelineDrawer website Pixel', () => {
  const metaPipeline = {
    id: 1,
    name: 'Viagem',
    metadata: {
      meta_sync: {
        enabled: true,
        dataset_id: '999',
        pixel_id: '2164882667623689',
      },
    },
  };

  it('loads the Pixel id and sends it in meta_sync', async () => {
    const wrapper = mountDrawer({ pipeline: metaPipeline });
    expect(wrapper.vm.form.metaSync.pixelId).toBe('2164882667623689');

    await wrapper.vm.onSubmit();

    const [[payload]] = wrapper.emitted('save');
    expect(payload.pipeline.meta_sync).toMatchObject({
      dataset_id: '999',
      pixel_id: '2164882667623689',
    });
  });

  it('keeps only digits, up to 20, when the Pixel id is typed or pasted', async () => {
    const wrapper = mountDrawer({ pipeline: metaPipeline });
    wrapper.vm.view = 'ads';
    await wrapper.vm.$nextTick();
    // O código do site fica na tela do Facebook e Instagram.
    await wrapper.get('[data-anuncio-alterar="facebook"]').trigger('click');
    expect(wrapper.vm.view).toBe('ads-facebook');
    await wrapper.get('[data-site]').trigger('click');

    const input = wrapper.get('input[inputmode="numeric"]');
    await input.setValue(' 2164 8826-6762 3689abc 12345678 ');

    expect(wrapper.vm.form.metaSync.pixelId).toBe('21648826676236891234');
    expect(input.element.value).toBe('21648826676236891234');
  });

  it('sends null when the Pixel id is empty', async () => {
    const wrapper = mountDrawer({
      pipeline: { id: 1, name: 'Funil', metadata: { meta_sync: {} } },
    });

    await wrapper.vm.onSubmit();

    const [[payload]] = wrapper.emitted('save');
    expect(payload.pipeline.meta_sync.pixel_id).toBeNull();
  });
});

// #1384 — criar em dois passos, editar por partes e "Cancelar" que desfaz.
describe('CrmPipelineDrawer journey', () => {
  const principal = wrapper => wrapper.get('[data-funil-principal]');

  it('creates in three steps: name, stages, then review', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    expect(wrapper.vm.view).toBe('nome');
    // #1498: a primeira pergunta é o tipo; sem ela, nada de nome nem etapas.
    expect(wrapper.find('[data-funil-nome]').exists()).toBe(false);
    expect(wrapper.vm.form.stages).toHaveLength(0);
    expect(principal(wrapper).attributes('disabled')).toBeDefined();
    await wrapper.get('[data-tipo="VENDER"]').trigger('click');
    expect(wrapper.find('[data-funil-nome]').exists()).toBe(true);
    // Vender tem um modelo só: nada de escolher modelo.
    expect(wrapper.find('[data-modelo]').exists()).toBe(false);
    expect(principal(wrapper).text()).toContain('CRM_FUNIL.CONTINUAR');

    await principal(wrapper).trigger('click');
    expect(wrapper.vm.view).toBe('etapas');
    expect(wrapper.find('[data-funil-nome]').exists()).toBe(false);

    await principal(wrapper).trigger('click');

    expect(wrapper.vm.view).toBe('confira');
    expect(principal(wrapper).text()).toContain(
      'CRM_KANBAN.PIPELINE_DRAWER.CREATE'
    );
    await principal(wrapper).trigger('click');
    await flushPromises();
    const [[payload]] = wrapper.emitted('save');
    expect(payload.stages).toHaveLength(5);
    expect(payload.pipeline.counts_as_sale).toBe(true);
  });

  it('switches to a ready-made template with its own stages', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
    expect(
      wrapper
        .findAll('[data-modelo]')
        .map(item => item.attributes('data-modelo'))
    ).toEqual(['ATENDIMENTO', 'POS_VENDA', 'COBRANCA', 'AGENDAMENTOS']);
    await wrapper.get('[data-modelo="COBRANCA"]').trigger('click');
    expect(wrapper.vm.form.name).toBe('CRM_FUNIL.MODELOS.COBRANCA.NOME');
    await wrapper.get('[data-modelo="ATENDIMENTO"]').trigger('click');

    expect(wrapper.vm.form.stages.map(stage => stage.name)).toEqual([
      'CRM_FUNIL.MODELOS.ATENDIMENTO.E1',
      'CRM_FUNIL.MODELOS.ATENDIMENTO.E2',
      'CRM_FUNIL.MODELOS.ATENDIMENTO.E3',
      'CRM_FUNIL.MODELOS.ATENDIMENTO.E4',
    ]);
    expect(wrapper.vm.form.countsAsSale).toBe(false);
    expect(wrapper.vm.form.name).toBe('CRM_FUNIL.MODELOS.ATENDIMENTO.NOME');
  });

  it('asks before a template switch throws away edited stages', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    await wrapper.get('[data-tipo="VENDER"]').trigger('click');
    wrapper.vm.form.stages[0].name = 'Primeiro oi';
    await wrapper.get('[data-tipo="ATENDER"]').trigger('click');

    expect(wrapper.vm.form.stages[0].name).toBe('Primeiro oi');
    await wrapper.get('[data-funil-manter-modelo]').trigger('click');
    expect(wrapper.find('[data-funil-trocar-modelo]').exists()).toBe(false);
    expect(wrapper.vm.form.stages[0].name).toBe('Primeiro oi');

    await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
    await wrapper.get('[data-funil-confirmar-modelo]').trigger('click');
    expect(wrapper.vm.form.stages[0].name).toBe(
      'CRM_FUNIL.MODELOS.ATENDIMENTO.E1'
    );
  });

  it('opens a part from the summary and cancel puts everything back', async () => {
    const wrapper = mountDrawer();
    expect(wrapper.vm.view).toBe('home');
    await wrapper
      .get('[data-setting="sales"]')
      .findComponent(Button)
      .trigger('click');
    expect(wrapper.vm.view).toBe('sales');

    wrapper.vm.form.countsAsSale = false;
    wrapper.vm.form.monthlyTarget = 900;
    wrapper.vm.cancelar();
    await wrapper.vm.$nextTick();

    expect(wrapper.vm.view).toBe('home');
    expect(wrapper.vm.form.countsAsSale).toBe(true);
    expect(wrapper.vm.form.monthlyTarget).toBe('');
  });

  it('closes from the summary: each part saves on its own screen', async () => {
    const wrapper = mountDrawer();
    expect(principal(wrapper).text()).toContain('CRM_FUNIL.FECHAR');

    await principal(wrapper).trigger('click');
    expect(wrapper.emitted('close')).toHaveLength(1);
    expect(wrapper.emitted('save')).toBeUndefined();
  });

  it('starts the Sales template with the same stages the editor shows', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    await wrapper.get('[data-tipo="VENDER"]').trigger('click');
    expect(wrapper.vm.form.stages.map(stage => stage.name)).toEqual(
      [1, 2, 3, 4, 5].map(n => `CRM_FUNIL.MODELOS.VENDAS.E${n}`)
    );
    // "Quando usar" já vem pronto pelo modelo, com "Alterar" no Confira.
    expect(wrapper.vm.form.whenToUse).toBe('CRM_FUNIL.SOBRE.IDEIAS.PRECO');
  });

  it('shows the board preview from the same form state', async () => {
    const wrapper = mountDrawer();
    expect(
      wrapper.findAll('[data-coluna]').map(col => col.attributes('data-coluna'))
    ).toEqual(['Novo', 'Em atendimento']);

    wrapper.vm.form.stages[0].name = 'Primeiro oi';
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-coluna="Primeiro oi"]').exists()).toBe(true);
  });
});

// #1384 — Anúncios: um seletor só para a etapa e o Google em três passos.
describe('CrmPipelineDrawer ads', () => {
  const principal = wrapper => wrapper.get('[data-funil-principal]');
  const comAnuncios = {
    id: 1,
    name: 'Vendas',
    metadata: { meta_sync: { enabled: true } },
  };

  it('starts with only the sale made and tells about one stage at most, keeping other ad types', async () => {
    const wrapper = mountDrawer({
      pipeline: comAnuncios,
      stages: makeStages().map((stage, index) => ({
        ...stage,
        funnel_stage_type: index === 0 ? 'lead' : '',
      })),
    });
    expect(wrapper.vm.form.metaSync.events).toEqual({
      won: true,
      lost: false,
      moved: false,
    });

    const [, segunda] = wrapper.vm.form.stages;
    wrapper.vm.avisarNaEtapa(segunda.editorKey);

    expect(
      wrapper.vm.form.stages.map(stage => stage.funnel_stage_type)
    ).toEqual(['lead', 'qualified']);
    expect(wrapper.vm.etapaAvisada.editorKey).toBe(segunda.editorKey);
    wrapper.vm.avisarNaEtapa('');
    expect(
      wrapper.vm.form.stages.map(stage => stage.funnel_stage_type)
    ).toEqual(['lead', '']);
    expect(wrapper.vm.etapaAvisada).toBeNull();
  });

  it('turns Google on only at the end of the three steps; cancel leaves it off', async () => {
    const wrapper = mountDrawer({ pipeline: comAnuncios });
    wrapper.vm.view = 'ads';
    await wrapper.vm.$nextTick();
    wrapper.vm.abrirGoogle();
    await flushPromises();
    expect(wrapper.vm.view).toBe('ads-google');
    expect(wrapper.vm.form.googleSync.enabled).toBe(false);

    await principal(wrapper).trigger('click');
    await principal(wrapper).trigger('click');
    expect(wrapper.vm.passoGoogle).toBe(3);
    expect(principal(wrapper).text()).toContain(
      'CRM_FUNIL.ANUNCIOS.GOOGLE.LIGAR'
    );

    await principal(wrapper).trigger('click');
    expect(wrapper.vm.view).toBe('ads');
    expect(wrapper.vm.form.googleSync.enabled).toBe(true);

    wrapper.vm.form.googleSync.enabled = false;
    wrapper.vm.abrirGoogle();
    wrapper.vm.cancelar();
    expect(wrapper.vm.form.googleSync.enabled).toBe(false);
  });

  it('keeps Close neutral on the summary', () => {
    const wrapper = mountDrawer();
    const fechar = wrapper.get('[data-funil-principal]');
    expect(fechar.text()).toContain('CRM_FUNIL.FECHAR');
    expect(fechar.classes().join(' ')).toContain('bg-n-slate-9/10');
  });
});

// #1498 — Atender: sem Vendas e meta nem Anúncios; o resumo fala do jeito de atender.
describe('CrmPipelineDrawer Atender', () => {
  it('shows Sell or Serve first in the summary, and hides ads', () => {
    const wrapper = mountDrawer({
      pipeline: { id: 1, name: 'Suporte', counts_as_sale: false },
    });
    const [primeiro] = wrapper.findAll('[data-setting]');
    expect(primeiro.attributes('data-setting')).toBe('sales');
    expect(primeiro.text()).toContain('CRM_FUNIL.TIPO.ROTULO');
    expect(primeiro.text()).toContain('CRM_FUNIL.RESUMO.TIPO_ATENDER');
    expect(wrapper.find('[data-setting="ads"]').exists()).toBe(false);
  });

  it('switches an existing pipeline back to Sell from the same question', async () => {
    const wrapper = mountDrawer({
      pipeline: { id: 1, name: 'Suporte', counts_as_sale: false },
    });
    await wrapper
      .get('[data-setting="sales"]')
      .findComponent(Button)
      .trigger('click');
    await wrapper.get('[data-tipo="VENDER"]').trigger('click');
    await wrapper.get('[data-funil-principal]').trigger('click');
    await flushPromises();
    const [[payload]] = wrapper.emitted('save');
    expect(payload.pipeline.counts_as_sale).toBe(true);
    expect(payload.pipeline.template).toBeUndefined();
  });

  it('creates a Collections pipeline with its template, categories and "Paid"', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
    await wrapper.get('[data-modelo="COBRANCA"]').trigger('click');
    expect(wrapper.vm.form.outcomeLabels.success).toBe(
      'CRM_FUNIL.MODELOS.COBRANCA.SUCESSO'
    );
    wrapper.vm.view = 'confira';
    await wrapper.vm.$nextTick();
    await wrapper.get('[data-funil-principal]').trigger('click');
    await flushPromises();
    const [[payload]] = wrapper.emitted('save');
    expect(payload.pipeline.template).toBe('COBRANCA');
    expect(payload.pipeline.counts_as_sale).toBe(false);
    expect(payload.pipeline.outcome_labels.success).toBe(
      'CRM_FUNIL.MODELOS.COBRANCA.SUCESSO'
    );
    expect(payload.stages.map(stage => stage.category)).toEqual([
      'novo',
      'andamento',
      'espera',
      'resolvido',
    ]);
  });

  describe('variant by account type (#1548)', () => {
    afterEach(() => {
      conta.autonomia_pacote = null;
    });

    const categoriasCriadas = async chave => {
      const wrapper = mountDrawer({
        mode: 'create',
        pipeline: null,
        stages: [],
      });
      await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
      await wrapper.get(`[data-modelo="${chave}"]`).trigger('click');
      wrapper.vm.view = 'confira';
      await wrapper.vm.$nextTick();
      await wrapper.get('[data-funil-principal]').trigger('click');
      await flushPromises();
      const [[payload]] = wrapper.emitted('save');
      return payload.stages.map(stage => stage.category);
    };

    it('health account: Service E3 is in progress, not a pause', async () => {
      conta.autonomia_pacote = 'seguros.saude_beneficios';
      expect(await categoriasCriadas('ATENDIMENTO')).toEqual([
        'novo',
        'andamento',
        'andamento',
        'resolvido',
      ]);
    });

    it('health account: other Serve templates keep today categories', async () => {
      conta.autonomia_pacote = 'seguros.saude_beneficios';
      expect(await categoriasCriadas('POS_VENDA')).toEqual([
        'novo',
        'andamento',
        'espera',
        'resolvido',
      ]);
    });

    it('broker account or no package: Service keeps today categories', async () => {
      conta.autonomia_pacote = 'seguros.corretora';
      expect(await categoriasCriadas('ATENDIMENTO')).toEqual([
        'novo',
        'andamento',
        'espera',
        'resolvido',
      ]);
      conta.autonomia_pacote = null;
      expect(await categoriasCriadas('ATENDIMENTO')).toEqual([
        'novo',
        'andamento',
        'espera',
        'resolvido',
      ]);
    });
  });

  // #1802 — os funis da corretora.
  describe('broker templates (#1802)', () => {
    afterEach(() => {
      conta.autonomia_pacote = null;
    });

    const criar = () =>
      mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    const modelos = wrapper =>
      wrapper
        .findAll('[data-modelo]')
        .map(item => item.attributes('data-modelo'));
    const salvar = async wrapper => {
      wrapper.vm.view = 'confira';
      await wrapper.vm.$nextTick();
      await wrapper.get('[data-funil-principal]').trigger('click');
      await flushPromises();
      return wrapper.emitted('save')[0][0];
    };

    it('broker: Sell offers Sales and Renewal; Serve starts at Claim', async () => {
      conta.autonomia_pacote = 'seguros.corretora';
      const wrapper = criar();
      await wrapper.get('[data-tipo="VENDER"]').trigger('click');
      expect(modelos(wrapper)).toEqual(['VENDAS', 'RENOVACAO']);
      expect(wrapper.vm.modelo).toBe('VENDAS');
      expect(wrapper.get('#funil-modelos-titulo').text()).toBe(
        'CRM_FUNIL.TIPO.MODELO_VENDER'
      );

      await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
      expect(modelos(wrapper)).toEqual([
        'SINISTRO',
        'ENDOSSO',
        'ATENDIMENTO',
        'POS_VENDA',
        'COBRANCA',
        'AGENDAMENTOS',
      ]);
      expect(wrapper.vm.modelo).toBe('SINISTRO');
      expect(wrapper.get('#funil-modelos-titulo').text()).toBe(
        'CRM_FUNIL.TIPO.MODELO'
      );
    });

    it('broker: Renewal saves its template, five stages and "Renewed / Not renewed"', async () => {
      conta.autonomia_pacote = 'seguros.corretora';
      const wrapper = criar();
      await wrapper.get('[data-tipo="VENDER"]').trigger('click');
      await wrapper.get('[data-modelo="RENOVACAO"]').trigger('click');
      const payload = await salvar(wrapper);

      expect(payload.pipeline.template).toBe('RENOVACAO');
      expect(payload.pipeline.counts_as_sale).toBe(true);
      expect(payload.pipeline.name).toBe('CRM_FUNIL.MODELOS.RENOVACAO.NOME');
      expect(payload.pipeline.outcome_labels).toEqual({
        success: 'CRM_FUNIL.MODELOS.RENOVACAO.SUCESSO',
        failure: 'CRM_FUNIL.MODELOS.RENOVACAO.FALHA',
      });
      expect(payload.stages.map(stage => stage.name)).toEqual(
        [1, 2, 3, 4, 5].map(n => `CRM_FUNIL.MODELOS.RENOVACAO.E${n}`)
      );
    });

    it('broker: leaving Renewal gives both outcome names back, but keeps a typed one', async () => {
      conta.autonomia_pacote = 'seguros.corretora';
      const wrapper = criar();
      await wrapper.get('[data-tipo="VENDER"]').trigger('click');
      await wrapper.get('[data-modelo="RENOVACAO"]').trigger('click');
      wrapper.vm.form.outcomeLabels.success = 'Apólice renovada';
      await wrapper.get('[data-modelo="VENDAS"]').trigger('click');
      expect(wrapper.vm.form.outcomeLabels).toEqual({
        success: 'Apólice renovada',
        failure: '',
      });
    });

    it.each([null, 'seguros.corretora'])(
      'account %j: a failure name with only spaces stays when switching templates without one',
      async pacote => {
        conta.autonomia_pacote = pacote;
        const wrapper = criar();
        await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
        wrapper.vm.form.outcomeLabels.failure = '   ';
        await wrapper.get('[data-modelo="COBRANCA"]').trigger('click');
        await wrapper.get('[data-modelo="POS_VENDA"]').trigger('click');
        expect(wrapper.vm.form.outcomeLabels.failure).toBe('   ');
      }
    );

    it('broker: Claim is Serve, with positional categories and only its success name', async () => {
      conta.autonomia_pacote = 'seguros.corretora';
      const wrapper = criar();
      await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
      const payload = await salvar(wrapper);

      expect(payload.pipeline.template).toBe('SINISTRO');
      expect(payload.pipeline.counts_as_sale).toBe(false);
      expect(payload.pipeline.outcome_labels).toEqual({
        success: 'CRM_FUNIL.MODELOS.SINISTRO.SUCESSO',
        failure: '',
      });
      expect(payload.stages.map(stage => stage.category)).toEqual([
        'novo',
        'andamento',
        'espera',
        'resolvido',
      ]);
    });

    // #2083 — a saúde tem a Carteira primeiro no Atender e salva os nomes
    // "Renovado" / "Cancelado" do modelo.
    it('health: Serve starts at the Portfolio and saves its outcome names', async () => {
      conta.autonomia_pacote = 'seguros.saude_beneficios';
      const wrapper = criar();
      await wrapper.get('[data-tipo="VENDER"]').trigger('click');
      expect(wrapper.find('[data-modelo]').exists()).toBe(false);
      await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
      expect(modelos(wrapper)).toEqual([
        'CARTEIRA',
        'ATENDIMENTO',
        'POS_VENDA',
        'COBRANCA',
        'AGENDAMENTOS',
      ]);
      expect(wrapper.vm.modelo).toBe('CARTEIRA');
      const payload = await salvar(wrapper);
      expect(payload.pipeline.template).toBe('CARTEIRA');
      expect(payload.pipeline.outcome_labels).toEqual({
        success: 'CRM_FUNIL.MODELOS.CARTEIRA.SUCESSO',
        failure: 'CRM_FUNIL.MODELOS.CARTEIRA.FALHA',
      });
      expect(payload.stages.map(stage => stage.category)).toEqual([
        'novo',
        'andamento',
        'andamento',
        'resolvido',
      ]);
    });

    it.each([null, 'seguros', 'seguros.insurtech'])(
      'account %j: same journey as today, no broker template anywhere',
      async pacote => {
        conta.autonomia_pacote = pacote;
        const wrapper = criar();
        await wrapper.get('[data-tipo="VENDER"]').trigger('click');
        expect(wrapper.find('[data-modelo]').exists()).toBe(false);
        expect(wrapper.vm.modelo).toBe('VENDAS');
        await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
        expect(modelos(wrapper)).toEqual([
          'ATENDIMENTO',
          'POS_VENDA',
          'COBRANCA',
          'AGENDAMENTOS',
        ]);
        expect(wrapper.vm.modelo).toBe('ATENDIMENTO');
        expect(wrapper.vm.form.name).toBe('CRM_FUNIL.MODELOS.ATENDIMENTO.NOME');
        await wrapper.get('[data-tipo="VENDER"]').trigger('click');
        const payload = await salvar(wrapper);
        expect(payload.pipeline.template).toBe('VENDAS');
        expect(payload.pipeline.outcome_labels).toEqual({
          success: '',
          failure: '',
        });
      }
    );
  });

  it('gives "Paid" back when leaving Collections for another template', async () => {
    const wrapper = mountDrawer({ mode: 'create', pipeline: null, stages: [] });
    await wrapper.get('[data-tipo="ATENDER"]').trigger('click');
    await wrapper.get('[data-modelo="COBRANCA"]').trigger('click');
    await wrapper.get('[data-modelo="POS_VENDA"]').trigger('click');
    expect(wrapper.vm.form.outcomeLabels.success).toBe('');
  });
});

// #1149 (R16): caixa que saiu do CRM guarda o vínculo, mas não aparece como
// ligada no funil (nem no resumo, nem em "Ligado em").
describe('CrmPipelineDrawer — inboxes are read only', () => {
  it('shows only the inboxes with the CRM on', async () => {
    const wrapper = mount(CrmPipelineDrawer, {
      props: {
        show: true,
        mode: 'edit',
        pipeline: { id: 1, name: 'Funil' },
        stages: makeStages(),
        pipelineInboxes: [
          { inbox_id: 2, inbox: { name: 'WhatsApp' }, caixa_no_crm: true },
          {
            inbox_id: 3,
            inbox: { name: 'Old site chat' },
            caixa_no_crm: false,
          },
        ],
      },
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'en', messages: { en: crmEn } }),
        ],
        stubs: {
          CrmStageAutomationsPanel: true,
          CrmAiSettingsPanel: true,
          RouterLink: RouterLinkStub,
          CaixaIcone: true,
        },
      },
    });

    const resumo = wrapper.get('[data-setting="inboxes"]');
    expect(resumo.text()).toContain('WhatsApp');
    expect(resumo.text()).not.toContain('Old site chat');

    await resumo.get('button').trigger('click');
    await flushPromises();

    expect(
      wrapper.findAll('[data-caixa]').map(item => item.attributes('data-caixa'))
    ).toEqual(['WhatsApp']);
    wrapper.unmount();
  });
});
