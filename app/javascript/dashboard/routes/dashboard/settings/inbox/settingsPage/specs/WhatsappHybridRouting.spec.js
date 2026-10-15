import { mount, flushPromises } from '@vue/test-utils';
import WhatsappHybridRouting from '../components/WhatsappHybridRouting.vue';

// Textos como "CHAVE|parâmetros", para o teste ver o que a tela escolheu dizer.
const translate = (key, params, plural) => {
  const values = params ? Object.values(params).join(',') : '';
  const count = plural === undefined ? '' : `#${plural}`;
  return values || count ? `${key}|${values}${count}` : key;
};

vi.mock('vue-i18n', async () => {
  const { ref } = await import('vue');
  return { useI18n: () => ({ t: translate, locale: ref('pt_BR') }) };
});

const R = 'INBOX_MGMT.WHATSAPP_HYBRID.ROUTING';

const ButtonStub = {
  props: ['label', 'disabled'],
  emits: ['click'],
  template:
    '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
};

// A gaveta: mostra o conteúdo e o rodapé só depois de aberta, como a real.
const SidePanelStub = {
  props: ['title'],
  data: () => ({ opened: false }),
  methods: {
    open() {
      this.opened = true;
    },
    close() {
      this.opened = false;
    },
  },
  template:
    '<div v-if="opened" data-test="drawer" :data-title="title"><slot /><slot name="footer" /></div>',
};

const baseState = {
  routing_enabled: true,
  disabled_origins: ['bot', 'automation', 'campaign'],
  rate_limit_per_minute: 20,
  campaign_rate_limit_per_minute: 10,
};

const mountRouting = state =>
  mount(WhatsappHybridRouting, {
    props: { state: { ...baseState, ...state } },
    global: {
      mocks: { $t: translate },
      stubs: { Button: ButtonStub, SidePanel: SidePanelStub },
    },
    attachTo: document.body,
  });

const buttonWith = (wrapper, label) =>
  wrapper.findAll('button').find(button => button.text() === label);

describe('WhatsappHybridRouting (chat#1487)', () => {
  it('shows three questions as summary cards, with no table and no loose number field', () => {
    const wrapper = mountRouting();

    expect(
      wrapper
        .findAll('[data-summary-card]')
        .map(card => card.attributes('data-summary-card'))
    ).toEqual(['way', 'who', 'pace']);
    expect(wrapper.find('table').exists()).toBe(false);
    expect(wrapper.find('input[type="number"]').exists()).toBe(false);
    expect(wrapper.find('[data-summary-card="who"]').text()).toContain(
      `${R}.WHO.SUMMARY|Atendentes e Lembretes do CRM#2`.replace(
        'Atendentes e Lembretes do CRM',
        `${R}.WHO.ORIGINS.HUMAN.SHORT e ${R}.WHO.ORIGINS.CRM_FOLLOW_UP.SHORT`
      )
    );
    expect(wrapper.find('[data-summary-card="pace"]').text()).toContain(
      `${R}.PACE.SUMMARY|20`
    );
    wrapper.unmount();
  });

  it('turns the general switch off: only templates after 24 h, the other cards dimmed', async () => {
    const wrapper = mountRouting();
    await wrapper.find('[data-routing-switch] input').setValue(false);

    expect(wrapper.emitted('save')).toEqual([[{ routing_enabled: false }]]);

    await wrapper.setProps({ state: { ...baseState, routing_enabled: false } });
    expect(wrapper.find('[data-way-outside]').text()).toBe(
      `${R}.WAY.OUTSIDE_OFF`
    );
    ['who', 'pace'].forEach(name => {
      const card = wrapper.find(`[data-summary-card="${name}"]`);
      expect(card.attributes('aria-disabled')).toBe('true');
      expect(card.text()).toContain(`${R}.OFF_HINT`);
      expect(card.text()).not.toContain(`${R}.EDIT`);
    });
    wrapper.unmount();
  });

  it('edits who can use it in a drawer, with the preview following the choices, and saves the same backend field', async () => {
    const wrapper = mountRouting();
    await buttonWith(wrapper, `${R}.EDIT`).trigger('click');

    const drawer = wrapper.find('[data-test="drawer"]');
    expect(
      drawer.find('[data-case="crm_follow_up"]').attributes('data-web')
    ).toBe('true');
    expect(drawer.find('[data-origin="campaign"] [data-risk]').exists()).toBe(
      true
    );
    // Uma coluna em todas as larguras: a gaveta divide o espaço com a prévia.
    expect(
      drawer.find('[data-origin="human"]').element.parentElement.className
    ).not.toContain('grid-cols-2');
    expect(drawer.find('[data-risk]').classes()).toEqual(
      expect.arrayContaining(['inline-flex', 'w-fit', 'items-center'])
    );

    await drawer.find('[data-origin="crm_follow_up"] input').setValue(false);
    await drawer.find('[data-origin="bot"] input').setValue(true);
    expect(drawer.find('[data-case="crm_follow_up"]').text()).toBe(
      `${R}.PREVIEW.FOLLOW_UP_TEMPLATE`
    );

    await buttonWith(wrapper, `${R}.SAVE`).trigger('click');
    expect(wrapper.emitted('save')).toEqual([
      [{ disabled_origins: ['automation', 'crm_follow_up', 'campaign'] }],
    ]);
    wrapper.unmount();
  });

  it('chooses the pace in the sentence and saves it', async () => {
    const wrapper = mountRouting();
    const editButtons = wrapper
      .findAll('button')
      .filter(button => button.text() === `${R}.EDIT`);
    await editButtons[1].trigger('click');

    const drawer = wrapper.find('[data-test="drawer"]');
    expect(drawer.find('[data-campaign-cap]').text()).toBe(
      `${R}.PACE.CAMPAIGNS|10`
    );
    await drawer.find('[data-choice="30"]').trigger('click');
    await flushPromises();
    expect(drawer.find('[data-case="pace"]').text()).toBe(
      `${R}.PREVIEW.PACE|30`
    );

    await buttonWith(wrapper, `${R}.SAVE`).trigger('click');
    expect(wrapper.emitted('save')).toEqual([[{ rate_limit_per_minute: 30 }]]);
    wrapper.unmount();
  });

  it('opens on "Other" with a saved pace outside 10/20/30 and blocks an invalid number', async () => {
    const wrapper = mountRouting({ rate_limit_per_minute: 45 });
    const editButtons = wrapper
      .findAll('button')
      .filter(button => button.text() === `${R}.EDIT`);
    await editButtons[1].trigger('click');

    const drawer = wrapper.find('[data-test="drawer"]');
    expect(
      drawer.find('[data-choice="other"]').attributes('aria-checked')
    ).toBe('true');
    expect(drawer.find('#hybrid-pace-other').element.value).toBe('45');

    await drawer.find('#hybrid-pace-other').setValue('500');
    await flushPromises();
    expect(drawer.find('[role="alert"]').text()).toBe(
      `${R}.PACE.INVALID|1,120`
    );
    // O contorno vermelho do Input do components-next (o estilo global cobria a borda) e o campo marcado inválido.
    const field = drawer.find('#hybrid-pace-other');
    expect(field.classes()).toContain('outline-n-ruby-8');
    expect(field.attributes('aria-invalid')).toBe('true');
    expect(field.attributes('max')).toBe('120');
    expect(
      buttonWith(wrapper, `${R}.SAVE`).attributes('disabled')
    ).toBeDefined();

    await drawer.find('#hybrid-pace-other').setValue('15');
    await flushPromises();
    await buttonWith(wrapper, `${R}.SAVE`).trigger('click');
    expect(wrapper.emitted('save')).toEqual([[{ rate_limit_per_minute: 15 }]]);
    wrapper.unmount();
  });

  it('waits for the person to type before showing the number error, with Save locked meanwhile', async () => {
    const wrapper = mountRouting();
    const editButtons = wrapper
      .findAll('button')
      .filter(button => button.text() === `${R}.EDIT`);
    await editButtons[1].trigger('click');

    const drawer = wrapper.find('[data-test="drawer"]');
    await drawer.find('[data-choice="other"]').trigger('click');
    await flushPromises();

    expect(drawer.find('#hybrid-pace-other').exists()).toBe(true);
    expect(drawer.find('[role="alert"]').exists()).toBe(false);
    expect(
      buttonWith(wrapper, `${R}.SAVE`).attributes('disabled')
    ).toBeDefined();

    await drawer.find('#hybrid-pace-other').trigger('blur');
    expect(drawer.find('[role="alert"]').exists()).toBe(true);
    wrapper.unmount();
  });

  it('uses a short drawer title, so it fits at 390 px', async () => {
    const wrapper = mountRouting();
    await buttonWith(wrapper, `${R}.EDIT`).trigger('click');

    expect(wrapper.find('[data-test="drawer"]').attributes('data-title')).toBe(
      `${R}.WHO.DRAWER_TITLE`
    );
    wrapper.unmount();
  });
});
