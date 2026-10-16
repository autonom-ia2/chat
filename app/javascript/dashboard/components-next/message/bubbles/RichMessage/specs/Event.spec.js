import { defineComponent, ref } from 'vue';
import { config, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/richMessage.json';
import Event from '../types/Event.vue';
import { eventDateLabel, eventResponseCounts } from '../eventAnswer.js';
import { provideMessageContext } from '../../../provider.js';
import { MESSAGE_VARIANTS } from '../../../constants';

config.global.plugins = [
  createI18n({ legacy: false, locale: 'pt_BR', messages: { pt_BR: ptBR } }),
];

const CONVITE = {
  type: 'event',
  startAt: '2026-10-20T14:00:00-03:00',
  locationName: 'Av. Paulista, 1000',
  description: 'Vistoria do carro',
};

const resposta = (response, senderId = 5) => ({
  senderType: 'Contact',
  senderId,
  response,
  extraGuests: 0,
  at: '2026-10-16T10:00:00Z',
});

const montar = (eventResponses, timezone = 'America/Sao_Paulo') => {
  const store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      'accounts/getAccount': () => id => (id === 1 ? { id, timezone } : {}),
    },
  });
  const Host = defineComponent({
    components: { Event },
    setup() {
      provideMessageContext({
        id: ref(80),
        content: ref('Vistoria'),
        contentAttributes: ref({ richMessage: CONVITE, eventResponses }),
        variant: ref(MESSAGE_VARIANTS.AGENT),
      });
    },
    template: '<Event />',
  });
  return mount(Host, {
    global: {
      plugins: [store],
      directives: {
        dompurifyHtml: (el, { value }) => {
          el.innerHTML = value;
        },
      },
      stubs: { BaseBubble: { template: '<div><slot /></div>' } },
    },
  });
};

describe('bolha do convite de evento', () => {
  it('mostra nome, data no fuso da conta, local e descrição, sem resposta', () => {
    const wrapper = montar(undefined);

    expect(wrapper.text()).toContain('Vistoria');
    expect(wrapper.find('[data-event-when]').text()).toContain('14:00');
    expect(wrapper.find('[data-event-when]').text()).not.toContain('Brasília');
    expect(wrapper.find('[data-event-where]').text()).toBe(
      'Av. Paulista, 1000'
    );
    expect(wrapper.text()).toContain('Vistoria do carro');
    expect(wrapper.find('[data-event-responses]').text()).toBe('Sem resposta');
  });

  it('conta as respostas gravadas na mensagem', () => {
    const wrapper = montar([resposta('going'), resposta('not_going', 6)]);

    expect(wrapper.find('[data-event-responses]').text()).toBe(
      'Vou: 1 · Não vou: 1 · Talvez: 0'
    );
  });

  it('anuncia a resposta nova ao leitor de tela e esconde os ícones dele', () => {
    const wrapper = montar([resposta('going')]);

    expect(wrapper.find('[data-event-responses]').attributes('aria-live')).toBe(
      'polite'
    );
    const hidden = wrapper.findAll('[aria-hidden="true"]');
    expect(hidden).toHaveLength(2);
    expect(hidden.map(item => item.find('span').classes())).toEqual([
      expect.arrayContaining(['i-lucide-calendar']),
      expect.arrayContaining(['i-lucide-map-pin']),
    ]);
  });

  it('usa o fuso da conta, não o do navegador', () => {
    expect(montar([], 'Asia/Tokyo').find('[data-event-when]').text()).toContain(
      '02:00'
    );
  });
});

describe('eventAnswer', () => {
  it('ignora respostas desconhecidas e data inválida', () => {
    expect(
      eventResponseCounts([resposta('going'), resposta('talvez'), null])
    ).toEqual({ going: 1, not_going: 0, maybe: 0 });
    expect(eventDateLabel('não é data', 'UTC', 'pt-BR')).toBe('');
  });
});
