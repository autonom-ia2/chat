/* eslint-disable vue/one-component-per-file */
import { computed, defineComponent, h, ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ConversaCanalAPI from 'dashboard/api/conversaCanal';
import { useReacaoDoAtendente } from '../useReacaoDoAtendente';
import { PELES, fornecerPele } from '../pele';

vi.mock('dashboard/api/conversaCanal', () => ({
  default: { reagir: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed: calculado } = await import('vue');
  const CAIXA = {
    channel_type: 'Channel::Whatsapp',
    provider: 'whatsapp_cloud',
  };
  const getters = {
    getSelectedChat: { can_reply: true, whatsapp_api_reply: false },
    'inboxes/getInbox': () => CAIXA,
  };
  return { useMapGetter: nome => calculado(() => getters[nome]) };
});

// A reação do atendente sai na hora; o selo espera o eco (message.updated).
const montar = () => {
  const atributos = ref({ reactions: [] });
  let reacao;
  const Balao = defineComponent({
    setup() {
      reacao = useReacaoDoAtendente(
        computed(() => ({
          id: 5,
          conversationId: 9,
          inboxId: 1,
          messageType: 0,
          isPrivate: false,
          status: 'sent',
          sourceId: 'wamid.A',
          contentAttributes: atributos.value,
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
  return { reacao, atributos };
};

describe('useReacaoDoAtendente: estado até o eco (#1702)', () => {
  beforeEach(() => {
    ConversaCanalAPI.reagir.mockReset().mockResolvedValue({});
  });

  it('clicar duas vezes no mesmo emoji antes do eco tira, não manda de novo', async () => {
    const { reacao } = montar();
    await reacao.reagir('👍');
    await flushPromises();
    expect(reacao.atual.value).toBe('👍');
    await reacao.reagir('👍');
    expect(ConversaCanalAPI.reagir.mock.calls).toEqual([
      [9, 5, '👍'],
      [9, 5, ''],
    ]);
    expect(reacao.atual.value).toBe('');
  });

  it('o eco confirma e passa a valer o que veio da conversa', async () => {
    const { reacao, atributos } = montar();
    await reacao.reagir('👍');
    atributos.value = { reactions: [{ emoji: '❤️', senderType: 'User' }] };
    await flushPromises();
    expect(reacao.atual.value).toBe('❤️');
  });

  it('falhou: nada muda na tela', async () => {
    ConversaCanalAPI.reagir.mockRejectedValue(new Error('rede'));
    const { reacao } = montar();
    await reacao.reagir('👍');
    expect(reacao.atual.value).toBe('');
  });
});
