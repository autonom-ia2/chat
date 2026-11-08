import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import {
  gettersDaMontagem,
  montagem,
} from '../../message/specs/montarMensagem';
import { PELES, fornecerFuso, fornecerPele, fornecerPrimeiras } from '../pele';
import { ORIGENS, origemDoEnvio } from '../origemDoEnvio';
import { continuaASequencia } from '../useSequenciaDaConversa';

// #2048: o balão do envio automático em nome de uma pessoa mostra o nome da origem, no
// lugar e na cor do "Agente de IA · Gabriela", sem o nome da pessoa. Só follow-up e aviso
// do Agendamento; o resto fica como estava.
vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));
vi.mock('dashboard/api/campaignJourney', () => ({
  default: {
    getCampaignNames: () => Promise.resolve({ data: { payload: {} } }),
  },
}));

const MARINA = {
  id: 5,
  name: 'Marina Souza',
  available_name: 'Marina',
  type: 'user',
};
const ROBO = { id: 8, name: 'Gabriela', type: 'agent_bot' };

const i18n = locale =>
  createI18n({
    legacy: false,
    locale,
    messages: { en, pt_BR: ptBR },
    missingWarn: false,
    fallbackWarn: false,
  });

const montar = (props = {}, { locale = 'pt_BR' } = {}) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => PELES.WHATSAPP));
        fornecerFuso(computed(() => 'America/Sao_Paulo'));
        fornecerPrimeiras(computed(() => new Set([1])));
        return () =>
          h(Message, {
            id: 1,
            messageType: MESSAGE_TYPES.OUTGOING,
            status: MESSAGE_STATUS.DELIVERED,
            content: 'Oi, tudo bem?',
            conversationId: 7,
            createdAt: 1760720400,
            currentUserId: 1,
            sender: MARINA,
            senderType: 'User',
            ...props,
          });
      },
    }),
    {
      global: {
        ...montagem,
        plugins: [
          createStore({
            getters: {
              ...gettersDaMontagem,
              'agents/getAgentById': () => () => ({}),
            },
          }),
          i18n(locale),
        ],
      },
    }
  );

// O nome em cima do balão: a mesma linha (e as mesmas classes) do "Agente de IA".
const remetente = balao => balao.find('.font-medium.text-\\[12\\.8px\\]');

describe('origemDoEnvio (#2048)', () => {
  it.each([
    [{ crmFollowUpId: 3 }, ORIGENS.FOLLOW_UP],
    [{ crmFollowUpId: 3, crmFollowUpOrigem: 'follow_up' }, ORIGENS.FOLLOW_UP],
    [{ crmFollowUpId: 3, crmFollowUpOrigem: 'outra' }, ORIGENS.FOLLOW_UP],
    [{ crmFollowUpId: 3, crmFollowUpOrigem: 'retorno' }, ORIGENS.RETORNO],
    [{ crm_follow_up_id: 3, crm_follow_up_origem: 'retorno' }, ORIGENS.RETORNO],
    [{ crmBookingNotice: true }, ORIGENS.AGENDAMENTO],
    [{ crm_booking_notice: true }, ORIGENS.AGENDAMENTO],
    [{ crmBookingInviteId: 9 }, null],
    [{ automationRuleId: 4 }, null],
    [{ externalEcho: true }, null],
    [{}, null],
    [null, null],
  ])('%o → %s', (atributos, esperado) => {
    expect(origemDoEnvio(atributos)).toBe(esperado);
  });
});

describe('nome da origem no balão com a pele (#2048)', () => {
  it.each([
    [{ crmFollowUpId: 3 }, 'Follow-up automático'],
    [
      { crmFollowUpId: 3, crmFollowUpOrigem: 'follow_up' },
      'Follow-up automático',
    ],
    [{ crmFollowUpId: 3, crmFollowUpOrigem: 'retorno' }, 'Retorno automático'],
    [{ crmBookingNotice: true }, 'Agendamento automático'],
  ])('%o mostra "%s", sem o nome da pessoa', (contentAttributes, nome) => {
    const balao = montar({ contentAttributes });

    expect(remetente(balao).text()).toBe(nome);
    expect(balao.text()).not.toContain('Marina');
    expect(balao.text()).not.toContain('automático ·');
    expect(balao.text()).toContain('Oi, tudo bem?');
  });

  it('robô com marca de follow-up segue "Agente de IA · Gabriela"', () => {
    const balao = montar({
      sender: ROBO,
      senderType: 'AgentBot',
      contentAttributes: { crmFollowUpId: 3 },
    });

    expect(remetente(balao).text()).toBe('Agente de IA · Gabriela');
  });

  it('em inglês, o catálogo en', () => {
    const balao = montar(
      { contentAttributes: { crmFollowUpId: 3, crmFollowUpOrigem: 'retorno' } },
      { locale: 'en' }
    );

    expect(remetente(balao).text()).toBe('Automatic callback');
  });

  it('origem mesmo sem remetente com nome', () => {
    const balao = montar({
      contentAttributes: { crmBookingNotice: true },
      sender: { id: 5, name: '', type: 'user' },
    });

    expect(remetente(balao).text()).toBe('Agendamento automático');
  });

  it('aviso pelo Híbrido, que sai sem remetente, também leva a origem', () => {
    const balao = montar({
      contentAttributes: { crmBookingNotice: true },
      sender: null,
      senderType: null,
    });

    expect(remetente(balao).text()).toBe('Agendamento automático');
  });

  it('robô só com o sender_type cru (sem objeto sender) não ganha origem', () => {
    const balao = montar({
      sender: null,
      senderType: 'AgentBot',
      contentAttributes: { crmFollowUpId: 3 },
    });

    expect(remetente(balao).text()).toBe('Agente de IA');
  });

  it('mesma linha e cor do "Agente de IA · Gabriela"', () => {
    const origem = remetente(
      montar({ contentAttributes: { crmFollowUpId: 3 } })
    );
    const agente = remetente(
      montar({ sender: ROBO, senderType: 'AgentBot', contentAttributes: {} })
    );

    expect(agente.text()).toBe('Agente de IA · Gabriela');
    expect(origem.classes()).toEqual(agente.classes());
  });

  it.each([
    ['convite do Agendamento', { crmBookingInviteId: 9 }],
    ['regra de automação', { automationRuleId: 4 }],
    ['resposta digitada', {}],
  ])('%s: só o nome da pessoa, sem "automático"', (_, contentAttributes) => {
    const balao = montar({ contentAttributes });

    expect(remetente(balao).text()).toBe('Marina');
    expect(balao.text()).not.toContain('automático');
  });

  it('campanha: o nome da pessoa e nada de origem no balão', () => {
    const balao = montar({
      contentAttributes: {},
      additionalAttributes: { campaignId: 2 },
    });

    expect(remetente(balao).text()).toBe('Marina');
    expect(balao.text()).not.toContain('Campanha ·');
  });

  it('balão que não é o 1º da sequência não repete a origem', () => {
    const balao = montar({ id: 2, contentAttributes: { crmFollowUpId: 3 } });

    expect(balao.text()).not.toContain('Follow-up automático');
  });
});

describe('sequência da conversa com origem (#2048)', () => {
  const daMarina = contentAttributes => ({
    messageType: MESSAGE_TYPES.OUTGOING,
    status: 'delivered',
    createdAt: 1760720400,
    sender: { id: 5, type: 'User' },
    senderId: 5,
    contentAttributes,
  });

  it('resposta da pessoa e follow-up em nome dela não se juntam', () => {
    expect(
      continuaASequencia(daMarina({}), daMarina({ crmFollowUpId: 3 }), 'UTC')
    ).toBe(false);
    expect(
      continuaASequencia(daMarina({ crmFollowUpId: 3 }), daMarina({}), 'UTC')
    ).toBe(false);
  });

  it('follow-up e retorno abrem sequências diferentes', () => {
    expect(
      continuaASequencia(
        daMarina({ crmFollowUpId: 3 }),
        daMarina({ crmFollowUpId: 4, crmFollowUpOrigem: 'retorno' }),
        'UTC'
      )
    ).toBe(false);
  });

  it('dois follow-ups seguidos ficam na mesma sequência', () => {
    expect(
      continuaASequencia(
        daMarina({ crmFollowUpId: 3 }),
        daMarina({ crmFollowUpId: 4 }),
        'UTC'
      )
    ).toBe(true);
  });

  it('robô com marca segue a sequência dele (nada muda para o Agente de IA)', () => {
    const doRobo = contentAttributes => ({
      ...daMarina(contentAttributes),
      sender: { id: 8, type: 'agent_bot' },
      senderId: 8,
    });
    expect(
      continuaASequencia(doRobo({}), doRobo({ crmFollowUpId: 3 }), 'UTC')
    ).toBe(true);
  });

  it('aviso sem remetente não se junta à resposta da pessoa', () => {
    const semRemetente = {
      ...daMarina({ crmBookingNotice: true }),
      sender: null,
      senderType: null,
      senderId: null,
    };
    expect(continuaASequencia(daMarina({}), semRemetente, 'UTC')).toBe(false);
    expect(continuaASequencia(semRemetente, daMarina({}), 'UTC')).toBe(false);
  });

  it('convite do Agendamento segue com a resposta da pessoa', () => {
    expect(
      continuaASequencia(
        daMarina({}),
        daMarina({ crmBookingInviteId: 9 }),
        'UTC'
      )
    ).toBe(true);
  });
});
