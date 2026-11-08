import { flushPromises, mount } from '@vue/test-utils';
import { computed } from 'vue';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/campaignJourney.json';
import EmailCampaignReview from '../EmailCampaignReview.vue';

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn().mockResolvedValue({ missing: [] }) }),
}));
vi.mock('dashboard/composables/useCanManage', () => ({
  useCanManage: () => computed(() => true),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock(
  'dashboard/components-next/CampaignJourney/prontasParaDisparar',
  () => ({
    guardarPronta: vi.fn(),
    listarProntas: vi.fn().mockResolvedValue([]),
  })
);

// #2717: disparar a campanha de e-mail aberta é consentir com todo envio futuro. Quem dispara
// vê isso na prontidão e na confirmação do disparo.
const AVISO = en.CAMPAIGN_JOURNEY.NEW_CAMPAIGN.EMAIL.AUDIENCE_MODE_DISPARO;

const montar = aberta =>
  mount(EmailCampaignReview, {
    props: {
      campaign: {
        id: 7,
        name: 'Manutenção',
        subject: 'Hora da manutenção',
        aberta,
        send_readiness: { can_send: true, eligible_recipients: 0, checks: {} },
      },
    },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en },
          missingWarn: false,
          fallbackWarn: false,
        }),
      ],
      stubs: {
        Dialog: {
          template: '<div data-test="confirmacao"><slot /></div>',
          methods: { open() {}, close() {} },
        },
        Spinner: true,
        RecipientImportStatus: true,
      },
    },
  });

describe('EmailCampaignReview open campaign (#2717)', () => {
  it('shows the open campaign in the readiness and in the send confirmation', async () => {
    const wrapper = montar(true);
    await flushPromises();

    const avisos = wrapper.findAll('[data-test="aviso-aberta"]');
    expect(avisos).toHaveLength(2);
    expect(avisos[0].text()).toBe(AVISO);
    expect(
      wrapper
        .find('[data-test="confirmacao"] [data-test="aviso-aberta"]')
        .exists()
    ).toBe(true);
  });

  it('a closed campaign shows no open-campaign notice', async () => {
    const wrapper = montar(false);
    await flushPromises();

    expect(wrapper.find('[data-test="aviso-aberta"]').exists()).toBe(false);
  });
});
