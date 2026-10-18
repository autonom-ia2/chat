// Com 'react' nas ações da conversa (#1709), a reação da pele vai pela rota da
// mensagem (POST .../messages/:id/reaction), sem exigir sourceId.
/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import { useAlert } from 'dashboard/composables';
import { useReacaoDoAtendente } from '../useReacaoDoAtendente';
import { PELES, fornecerPele } from '../pele';

vi.mock('dashboard/api/conversaCanal', () => ({
  default: { reagir: vi.fn(), reagirPelaCaixa: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed: calculado } = await import('vue');
  const getters = {
    getSelectedChat: { whatsapp_api_message_actions: ['react'] },
    'inboxes/getInbox': () => ({
      channel_type: 'Channel::Api',
      waha_provider: 'waha',
    }),
  };
  return { useMapGetter: nome => calculado(() => getters[nome]) };
});

const montar = () => {
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
    ConversaCanalAPI.reagir.mockReset();
    ConversaCanalAPI.reagirPelaCaixa.mockReset().mockResolvedValue({});
    useAlert.mockReset();
  });

  it('mostra o botão sem sourceId e manda pela rota da mensagem', async () => {
    const reacao = montar();
    expect(reacao.visivel.value).toBe(true);
    await reacao.reagir('👍');
    await flushPromises();
    expect(ConversaCanalAPI.reagirPelaCaixa).toHaveBeenCalledWith(9, 5, '👍');
    expect(ConversaCanalAPI.reagir).not.toHaveBeenCalled();
    expect(reacao.atual.value).toBe('👍');
  });

  it('recusa (422) vira aviso com o motivo do servidor', async () => {
    ConversaCanalAPI.reagirPelaCaixa.mockRejectedValue({
      response: { status: 422, data: { error: 'Reação inválida' } },
    });
    const reacao = montar();
    await reacao.reagir('👍');
    expect(useAlert).toHaveBeenCalledWith('Reação inválida');
    expect(reacao.atual.value).toBe('');
  });
});
