import { flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import MessageApi from 'dashboard/api/inbox/message';
import { useVisorDaConversa } from '../conversa/useVisorDaConversa';

vi.mock('dashboard/api/inbox/conversation', () => ({
  default: { show: vi.fn() },
}));
vi.mock('dashboard/api/inbox/message', () => ({
  default: { getPreviousMessages: vi.fn() },
}));

const mensagens = (de, ate) =>
  Array.from({ length: ate - de + 1 }, (_, i) => ({
    id: de + i,
    created_at: 1000 + de + i,
    attachments: de + i === ate ? [{ id: 7, file_type: 'image' }] : [],
  }));

describe('useVisorDaConversa (#3165)', () => {
  beforeEach(() => {
    ConversationAPI.show.mockReset();
    MessageApi.getPreviousMessages.mockReset();
  });

  it('carrega a conversa e as últimas mensagens, em ordem, com os anexos', async () => {
    ConversationAPI.show.mockResolvedValue({ data: { id: 94, inbox_id: 1 } });
    MessageApi.getPreviousMessages.mockResolvedValue({
      data: { payload: mensagens(21, 40).reverse() },
    });
    const visor = useVisorDaConversa(ref(94));
    await flushPromises();
    expect(ConversationAPI.show).toHaveBeenCalledWith(94);
    expect(MessageApi.getPreviousMessages).toHaveBeenCalledWith({
      conversationId: 94,
    });
    expect(visor.mensagens.value.map(m => m.id)[0]).toBe(21);
    expect(visor.conversa.value.messages).toHaveLength(20);
    expect(visor.conversa.value.inbox_id).toBe(1);
    expect(visor.anexos.value).toEqual([
      expect.objectContaining({ id: 7, message_id: 40 }),
    ]);
    expect(visor.temAntigas.value).toBe(true);
  });

  it('puxa as antigas antes da primeira e para quando acabam', async () => {
    ConversationAPI.show.mockResolvedValue({ data: { id: 94 } });
    MessageApi.getPreviousMessages
      .mockResolvedValueOnce({ data: { payload: mensagens(21, 40) } })
      .mockResolvedValueOnce({ data: { payload: mensagens(15, 20) } });
    const visor = useVisorDaConversa(ref(94));
    await flushPromises();
    await expect(visor.carregarAntigas()).resolves.toBe(true);
    expect(MessageApi.getPreviousMessages).toHaveBeenLastCalledWith({
      conversationId: 94,
      before: 21,
    });
    expect(visor.mensagens.value).toHaveLength(26);
    expect(visor.mensagens.value[0].id).toBe(15);
    expect(visor.temAntigas.value).toBe(false);
    await expect(visor.carregarAntigas()).resolves.toBe(false);
    expect(MessageApi.getPreviousMessages).toHaveBeenCalledTimes(2);
  });

  it('trocar de conversa no meio descarta a resposta da anterior', async () => {
    let soltar;
    ConversationAPI.show
      .mockImplementationOnce(
        () =>
          new Promise(resolver => {
            soltar = () => resolver({ data: { id: 1 } });
          })
      )
      .mockResolvedValueOnce({ data: { id: 2 } });
    MessageApi.getPreviousMessages.mockResolvedValue({
      data: { payload: [] },
    });
    const numero = ref(1);
    const visor = useVisorDaConversa(numero);
    numero.value = 2;
    await flushPromises();
    soltar();
    await flushPromises();
    expect(visor.conversa.value.id).toBe(2);
  });

  it('falha nas antigas vira aviso e não apaga o que já veio', async () => {
    ConversationAPI.show.mockResolvedValue({ data: { id: 94 } });
    MessageApi.getPreviousMessages
      .mockResolvedValueOnce({ data: { payload: mensagens(21, 40) } })
      .mockRejectedValueOnce(new Error('500'));
    const visor = useVisorDaConversa(ref(94));
    await flushPromises();
    await expect(visor.carregarAntigas()).resolves.toBe(false);
    expect(visor.erroAntigas.value).toBe(true);
    expect(visor.carregandoAntigas.value).toBe(false);
    expect(visor.mensagens.value).toHaveLength(20);
  });

  it('erro na busca vira aviso, sem conversa', async () => {
    ConversationAPI.show.mockRejectedValue(new Error('403'));
    MessageApi.getPreviousMessages.mockResolvedValue({ data: { payload: [] } });
    const visor = useVisorDaConversa(ref(94));
    await flushPromises();
    expect(visor.erro.value).toBe(true);
    expect(visor.conversa.value).toBeNull();
    expect(visor.carregando.value).toBe(false);
  });
});
