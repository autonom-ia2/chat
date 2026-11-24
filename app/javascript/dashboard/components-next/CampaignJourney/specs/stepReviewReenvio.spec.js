import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import campaignJourney from 'dashboard/i18n/locale/en/campaignJourney.json';
import campanhaVendas from 'dashboard/i18n/locale/en/campanhaVendas.json';
import reenvioHorario from 'dashboard/i18n/locale/en/reenvioHorario.json';
import StepReview from '../StepReview.vue';
import { reenvioNovo } from '../reenvio/reenvio';

const en = { ...campaignJourney, ...campanhaVendas, ...reenvioHorario };
const R = reenvioHorario.REENVIO_HORARIO.REENVIO;

const montar = (draft, extra = {}) =>
  mount(StepReview, {
    props: {
      draft: { when: 'now', scheduledAt: '', ...draft },
      blocks: [],
      channelLabel: 'SMS',
      onChannelLabel: 'On SMS',
      crmTag: 'Campaign',
      timeZone: 'America/Sao_Paulo',
      reach: 30,
      ...extra,
    },
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      // A confirmação de verdade é um <dialog>; aqui só o que ela diz.
      stubs: {
        Dialog: {
          template: '<div data-dialog><slot name="description" /></div>',
          methods: { open() {}, close() {} },
        },
      },
    },
  });

const botaoDeEnviar = wrapper =>
  wrapper.find('[data-test="open-confirmation"]');

describe('StepReview with send again and best time (#3101)', () => {
  it('shows neither piece while the page does not offer them', () => {
    const wrapper = montar({});

    expect(wrapper.find('[data-reenvio]').exists()).toBe(false);
    expect(wrapper.find('[data-melhor-horario]').exists()).toBe(false);
  });

  it('holds the campaign while the second message is missing', () => {
    const wrapper = montar(
      { reenvio: reenvioNovo() },
      { reenvio: { canal: 'sms', modelos: [] } }
    );

    expect(botaoDeEnviar(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-test="review-falta-reenvio"]').text()).toBe(
      R.FALTA.SEM_TEXTO
    );
  });

  it('lets it go once the second message is written, and says so beside the count', () => {
    const wrapper = montar(
      { reenvio: { ...reenvioNovo(), texto: 'Still there?' } },
      { reenvio: { canal: 'sms', modelos: [] } }
    );

    expect(botaoDeEnviar(wrapper).attributes('disabled')).toBeUndefined();
    expect(wrapper.find('[data-test="review-reenvio"]').text()).toContain(
      '3 days later'
    );
  });

  it('holds the campaign again when the chosen template left the inbox', () => {
    const wrapper = montar(
      { reenvio: { ...reenvioNovo(), modeloId: 'apagado' } },
      {
        reenvio: {
          canal: 'whatsapp_official',
          modelos: [{ value: 'outro', label: 'Outro', variaveis: [] }],
        },
      }
    );

    expect(botaoDeEnviar(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.find('[data-test="review-falta-reenvio"]').text()).toBe(
      R.FALTA.SEM_MODELO
    );
  });

  it('tells in the confirmation when the days count from and for how many, one idea per line', () => {
    const wrapper = montar(
      { reenvio: { ...reenvioNovo(), texto: 'Still there?', dias: 2 } },
      { reenvio: { canal: 'sms', modelos: [] } }
    );

    const linhas = wrapper.findAll('[data-test="confirm-text"] p');
    expect(linhas).toHaveLength(2);
    expect(linhas[1].text()).toBe(
      "2 days after the first one finishes going out, people who didn't reply get the second message: up to 30 people."
    );
    expect(wrapper.text()).not.toContain(R.CONFIRM_PAGO);
  });

  it('says on WhatsApp Oficial that each second message is a paid template', () => {
    const wrapper = montar(
      { reenvio: { ...reenvioNovo(), modeloId: 'lembrete' } },
      {
        reenvio: {
          canal: 'whatsapp_official',
          modelos: [{ value: 'lembrete', label: 'Lembrete', variaveis: [] }],
        },
      }
    );

    const linhas = wrapper.findAll('[data-test="confirm-text"] p');
    expect(linhas).toHaveLength(3);
    expect(linhas[2].text()).toBe(R.CONFIRM_PAGO);
  });

  it('says the best time beside the count only when it is on', async () => {
    const wrapper = montar(
      { melhorHorario: false },
      { melhorHorario: { conhecidos: 20, horarioPermitido: '' } }
    );
    expect(wrapper.find('[data-test="review-melhor-horario"]').exists()).toBe(
      false
    );

    await wrapper.setProps({
      draft: { when: 'now', scheduledAt: '', melhorHorario: true },
    });
    expect(
      wrapper.find('[data-test="review-melhor-horario"]').text()
    ).toContain('24 h');
  });
});
