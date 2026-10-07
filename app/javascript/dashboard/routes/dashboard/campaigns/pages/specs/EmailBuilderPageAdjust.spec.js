import { shallowMount, config, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { nextTick, ref } from 'vue';
import en from 'dashboard/i18n/locale/en/campaign.json';

const editor = vi.hoisted(() => ({}));
vi.mock(
  'dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/composables/useEmailEditor',
  () => ({ useEmailEditor: () => editor.api })
);
const dispatch = vi.hoisted(() => vi.fn(() => Promise.resolve({})));
const campaigns = vi.hoisted(() => ({ list: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ dispatch }),
    useMapGetter: key =>
      computed(() => {
        if (key === 'emailCampaigns/getCampaigns') return campaigns.list.value;
        if (key === 'emailCampaigns/getUIFlags') return {};
        return { email: 'gestora@empresa.com.br' };
      }),
  };
});
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { ref: vueRef } = await import('vue');
  return { useCanManage: () => vueRef(true) };
});
vi.mock('dashboard/composables/useRecipientImportPolling', () => ({
  useRecipientImportPolling: vi.fn(),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1, campaignId: 7 }, query: {} }),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));
const api = vi.hoisted(() => ({
  status: vi.fn(),
  discardAdjustment: vi.fn(),
  applyAdjustment: vi.fn(),
  undoAdjustment: vi.fn(),
}));
vi.mock('dashboard/api/emailCampaignAi', () => ({ default: api }));
vi.mock('dashboard/api/emailCampaignTemplates', () => ({ default: {} }));

const { default: EmailBuilderPage } = await import('../EmailBuilderPage.vue');

const defaults = config.global.plugins;
beforeAll(() => {
  config.global.plugins = [];
});
afterAll(() => {
  config.global.plugins = defaults;
});

const FOOTER =
  '<mj-section css-class="footer-locked"><mj-column><mj-text>Sair</mj-text></mj-column></mj-section>';
const EMPTY = `<mjml><mj-body>${FOOTER}</mj-body></mjml>`;
const WITH_CONTENT = `<mjml><mj-body><mj-section><mj-column><mj-text>Promoção</mj-text></mj-column></mj-section>${FOOTER}</mj-body></mjml>`;

const setUp = ({ canvas = EMPTY, aiStatus = 'idle' } = {}) => {
  editor.canvas = canvas;
  editor.api = {
    isReady: ref(true),
    device: ref('desktop'),
    contentVersion: ref(0),
    selectedComponent: ref(null),
    isTextSelected: ref(false),
    getMjml: vi.fn(() => editor.canvas),
    getHtml: vi.fn(() => '<html></html>'),
    setMjml: vi.fn(mjml => {
      editor.canvas = mjml;
    }),
    compileMjml: vi.fn(mjml => `<html>${mjml}</html>`),
    setDevice: vi.fn(),
    setSelectedText: vi.fn(),
    adjustCanvasScroll: vi.fn(),
    setCanvasPreview: vi.fn(),
  };
  campaigns.list = ref([
    { id: 7, name: 'Outubro', body_mjml: canvas, ai_status: aiStatus },
  ]);
  return shallowMount(EmailBuilderPage, {
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: { AiAdjustPreview: false, Button: false },
    },
  });
};

const settle = async () => {
  await nextTick();
  vi.advanceTimersByTime(400);
  await flushPromises();
  await nextTick();
};
const aiButton = wrapper => wrapper.find('[data-test="ai-compose-button"]');

beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  vi.useRealTimers();
  vi.clearAllMocks();
});

// #1095: "Criar com IA" / "Ajustar com IA", before/after, apply with undo, discard.
describe('EmailBuilderPage — Ajustar com IA', () => {
  it('says "Create with AI" on an empty canvas and "Adjust with AI" once it has content', async () => {
    const wrapper = setUp();
    await settle();
    expect(aiButton(wrapper).text()).toBe('Create with AI');

    editor.canvas = WITH_CONTENT;
    editor.api.contentVersion.value += 1;
    await settle();

    expect(aiButton(wrapper).text()).toBe('Adjust with AI');
  });

  it('opens the composer in adjust mode with the live canvas reader', async () => {
    const wrapper = setUp({ canvas: WITH_CONTENT });
    await settle();

    await aiButton(wrapper).trigger('click');
    const composer = wrapper.findComponent({ name: 'AiComposerDialog' });

    expect(composer.props('canAdjust')).toBe(true);
    expect(composer.props('readCurrentMjml')()).toBe(WITH_CONTENT);
  });

  const proposal = {
    status: 'proposed',
    base: WITH_CONTENT,
    mjml: '<mjml>novo</mjml>',
    summary: 'Troquei o título.',
  };

  it('shows the before/after of a proposal waiting from an earlier visit, and applies it with undo', async () => {
    api.status.mockResolvedValue({
      data: { ai_status: 'ready', ai_adjustment: proposal },
    });
    // #1111: the server records the identity before the save, whose answer brings it back.
    let savedBeforeApply = null;
    api.applyAdjustment.mockImplementation(async () => {
      savedBeforeApply = dispatch.mock.calls.some(
        ([action]) => action === 'emailCampaigns/update'
      );
      return { data: { brand_identity: {} } };
    });
    api.discardAdjustment.mockResolvedValue({});
    const wrapper = setUp({ canvas: WITH_CONTENT, aiStatus: 'ready' });
    await settle();

    const preview = wrapper.findComponent({ name: 'AiAdjustPreview' });
    expect(preview.props()).toMatchObject({
      beforeHtml: `<html>${WITH_CONTENT}</html>`,
      afterHtml: '<html><mjml>novo</mjml></html>',
      summary: 'Troquei o título.',
    });
    expect(editor.api.setMjml).not.toHaveBeenCalled();

    preview.vm.$emit('apply');
    await settle();

    expect(editor.api.setMjml).toHaveBeenCalledWith('<mjml>novo</mjml>');
    expect(dispatch).toHaveBeenCalledWith(
      'emailCampaigns/update',
      expect.objectContaining({ id: 7, body_mjml: '<mjml>novo</mjml>' })
    );
    expect(api.applyAdjustment).toHaveBeenCalledWith(7);
    expect(savedBeforeApply).toBe(false);
    expect(api.discardAdjustment).not.toHaveBeenCalled();
    expect(wrapper.findComponent({ name: 'AiAdjustPreview' }).exists()).toBe(
      false
    );

    // Desfazer restores the identity on the server before saving the old body (#1111).
    const savesBeforeUndo = dispatch.mock.calls.length;
    let savedBeforeIdentity = null;
    api.undoAdjustment.mockImplementation(async () => {
      savedBeforeIdentity = dispatch.mock.calls.length > savesBeforeUndo;
      return { data: { brand_identity: {} } };
    });
    await wrapper.find('[data-test="ai-adjust-undo-button"]').trigger('click');
    await settle();

    expect(editor.api.setMjml).toHaveBeenLastCalledWith(WITH_CONTENT);
    expect(api.undoAdjustment).toHaveBeenCalledWith(7);
    expect(savedBeforeIdentity).toBe(false);
    expect(dispatch).toHaveBeenLastCalledWith(
      'emailCampaigns/update',
      expect.objectContaining({ id: 7, body_mjml: WITH_CONTENT })
    );
    expect(wrapper.find('[data-test="ai-adjust-undo"]').exists()).toBe(false);
  });

  it('discards a proposal without touching the canvas', async () => {
    api.status.mockResolvedValue({
      data: { ai_status: 'ready', ai_adjustment: proposal },
    });
    api.discardAdjustment.mockResolvedValue({});
    const wrapper = setUp({ canvas: WITH_CONTENT, aiStatus: 'ready' });
    await settle();

    wrapper.findComponent({ name: 'AiAdjustPreview' }).vm.$emit('discard');
    await settle();

    expect(editor.api.setMjml).not.toHaveBeenCalled();
    expect(api.discardAdjustment).toHaveBeenCalledWith(7);
    expect(wrapper.findComponent({ name: 'AiAdjustPreview' }).exists()).toBe(
      false
    );
  });
});
