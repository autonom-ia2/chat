// Com 'react' nas ações da conversa (#1709), a reação da pele vai pelo cliente do
// #1709 (wahaMessageActions.react: POST .../messages/:id/reaction), sem exigir sourceId.
/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import WahaMessageActionsAPI from 'dashboard/api/wahaMessageActions';
import { useAlert } from 'dashboard/composables';
import { useReacaoDoAtendente } from '../useReacaoDoAtendente';
import { PELES, fornecerPele } from '../pele';

vi.mock('dashboard/api/conversaCanal', () => ({
  default: { reagir: vi.fn() },
}));
vi.mock('dashboard/api/wahaMessageActions', () => ({
  default: { react: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const WAHA = { channel_type: 'Channel::Api', waha_provider: 'waha' };
const CLOUD = { channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' };
// Cada teste escolhe a caixa e a conversa (a de sempre: WAHA com 'react').
const loja = vi.hoisted(() => ({ conversa: null, caixa: null }));
vi.mock('dashboard/composables/store', async () => {
  const { computed: calculado } = await import('vue');
  const getters = {
    getSelectedChat: () => loja.conversa,
    'inboxes/getInbox': () => () => loja.caixa,
  };
  return { useMapGetter: nome => calculado(getters[nome]) };
});

// Mesmo formato que o Message.vue passa: isPrivate vem de props.private e a apagada
// de contentAttributes.deleted (o hook a leva para o topo).
const montar = (extras = {}) => {
  let reacao;
  const Balao = defineComponent({
    setup() {
      reacao = useReacaoDoAtendente(
        computed(() => ({
          id: 5,
          conversationId: 9,
          inboxId: 1,
          messageType: 1,
          isPrivate: false,
          status: 'sent',
          sourceId: null,
          contentAttributes: { reactions: [] },
          ...extras,
        }))
      );
      return () => null;
    },
  });
  const Conversa = defineComponent({
    setup() {
      fornecerPele(computed(() => PELES.WHATSAPP));
      return () => h(Balao);
    },
  });
  const i18n = createI18n({ legacy: false, locale: 'en', messages: {} });
  mount(Conversa, { global: { plugins: [i18n] } });
  return reacao;
};

describe('useReacaoDoAtendente pela caixa (#1709)', () => {
  beforeEach(() => {
    loja.conversa = { whatsapp_api_message_actions: ['react'] };
    loja.caixa = WAHA;
    ConversaCanalAPI.reagir.mockReset().mockResolvedValue({});
    WahaMessageActionsAPI.react.mockReset().mockResolvedValue({});
    useAlert.mockReset();
  });

  it('mostra o botão sem sourceId e manda pela rota da mensagem', async () => {
    const reacao = montar();
    expect(reacao.visivel.value).toBe(true);
    await reacao.reagir('👍');
    await flushPromises();
    expect(WahaMessageActionsAPI.react).toHaveBeenCalledWith(9, 5, '👍');
    expect(ConversaCanalAPI.reagir).not.toHaveBeenCalled();
    expect(reacao.atual.value).toBe('👍');
  });

  it('nota privada não tem botão de reagir', () => {
    expect(montar({ isPrivate: true }).visivel.value).toBe(false);
  });

  it('mensagem apagada (contentAttributes.deleted) não tem botão de reagir', () => {
    const reacao = montar({
      contentAttributes: { reactions: [], deleted: true },
    });
    expect(reacao.visivel.value).toBe(false);
  });

  it('recusa (422) vira aviso com o motivo do servidor', async () => {
    WahaMessageActionsAPI.react.mockRejectedValue({
      response: { status: 422, data: { error: 'Reação inválida' } },
    });
    const reacao = montar();
    await reacao.reagir('👍');
    expect(useAlert).toHaveBeenCalledWith('Reação inválida');
    expect(reacao.atual.value).toBe('');
  });

  it('o mesmo emoji de novo tira a reação: manda vazio pela caixa', async () => {
    const reacao = montar({
      contentAttributes: {
        reactions: [{ emoji: '👍', senderType: 'User', senderId: 1 }],
      },
    });
    expect(reacao.atual.value).toBe('👍');
    await reacao.reagir('👍');
    await flushPromises();
    expect(WahaMessageActionsAPI.react).toHaveBeenCalledWith(9, 5, '');
    expect(reacao.atual.value).toBe('');
  });

  it('mensagem apagada pelo cliente (deletedByContactAt) não tem botão de reagir', () => {
    const reacao = montar({
      contentAttributes: { reactions: [], deletedByContactAt: 1760000000 },
    });
    expect(reacao.visivel.value).toBe(false);
  });

  it('na Cloud a reação vai pela rota de sempre, nunca pela caixa', async () => {
    loja.conversa = { can_reply: true };
    loja.caixa = CLOUD;
    const reacao = montar({ messageType: 0, sourceId: 'wamid.abc' });
    expect(reacao.visivel.value).toBe(true);
    await reacao.reagir('❤️');
    await flushPromises();
    expect(ConversaCanalAPI.reagir).toHaveBeenCalledWith(9, 5, '❤️');
    expect(WahaMessageActionsAPI.react).not.toHaveBeenCalled();
  });
});
