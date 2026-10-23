import { flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { usaGavetaNova, useMensagemMarcada } from '../useMensagemMarcada';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

const getFollowUpMessagingWindow = vi.fn();
vi.mock('dashboard/api/crmKanban', () => ({
  default: {
    getFollowUpMessagingWindow: (...args) =>
      getFollowUpMessagingWindow(...args),
  },
}));

const OFICIAL = {
  id: 7,
  name: 'WhatsApp da loja',
  channel_type: 'Channel::Whatsapp',
};
const API = { id: 8, name: 'Campanhas', channel_type: 'Channel::Api' };
const MODELO = { name: 'boas_vindas', language: 'pt_BR' };

const novaLoja = () => {
  const dispatch = vi.fn().mockResolvedValue({});
  const store = {
    getters: {
      'inboxes/getInboxes': [OFICIAL, API],
      'inboxes/getConversationWhatsAppTemplates': () => [MODELO],
    },
    dispatch,
  };
  return { store, dispatch };
};

const card = (extra = {}) => ({
  id: 3,
  title: 'Plano anual',
  conversation_id: 30,
  inbox_id: 7,
  contact: { name: 'Mariana Costa', phone_number: '+5511999990000' },
  owner: { name: 'Paula' },
  ...extra,
});

// Amanhã às 09:00 no fuso da conta: sempre no futuro.
const marcarAmanha = m => {
  m.quando.value = { dia: m.amanha(), hora: '09:00' };
};

describe('useMensagemMarcada', () => {
  beforeEach(() => {
    getFollowUpMessagingWindow.mockReset();
    getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: false, whatsapp_api_available: false },
    });
  });

  it('só a caixa oficial abre a gaveta nova; outra caixa ou sem conversa, não', () => {
    expect(usaGavetaNova(card(), [OFICIAL, API])).toBe(true);
    expect(usaGavetaNova(card({ inbox_id: 8 }), [OFICIAL, API])).toBe(false);
    expect(usaGavetaNova(card({ conversation_id: null }), [OFICIAL])).toBe(
      false
    );
  });

  it('o negócio vira alvo: cliente, negócio, telefone, caixa e dono', () => {
    const { store } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });

    expect(m.paraAlvo(card())).toMatchObject({
      nome: 'Mariana Costa',
      primeiroNome: 'Mariana',
      negocio: 'Plano anual',
      telefone: '+5511999990000',
      caixaNome: 'WhatsApp da loja',
      dono: 'Paula',
      conectada: true,
      oficial: true,
    });
    expect(m.paraAlvo(card({ inbox_id: 8 })).oficial).toBe(false);
  });

  it('escolher quem recebe leva ao "Quando"; outra caixa não avança', () => {
    const { store } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });

    m.escolherAlvo(card({ inbox_id: 8 }));
    expect(m.passo.value).toBe('para-quem');
    m.escolherAlvo(card());
    expect(m.passo.value).toBe('quando');
  });

  it('confere o WhatsApp na hora marcada, não agora', async () => {
    const { store } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    await flushPromises();

    expect(getFollowUpMessagingWindow).toHaveBeenCalledWith(30, m.dueAt.value);
    expect(m.dueAt.value).toMatch(/T12:00:00/);
  });

  it('horário que já passou trava o passo', () => {
    const { store } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    m.quando.value = { dia: '2020-01-01', hora: '09:00' };

    expect(m.faltaNoPasso.value).toBe('PASSADO');
  });

  it('fora das 24 h pede mensagem pronta e os campos dela', async () => {
    getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: true, whatsapp_api_available: false },
    });
    const { store } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    m.avancar();
    await flushPromises();

    expect(m.soPronta.value).toBe(true);
    expect(m.faltaNoPasso.value).toBe('PRONTA');
    m.mensagem.value = { texto: '', modelo: MODELO };
    expect(m.faltaNoPasso.value).toBe('CAMPOS');
    m.camposProntos.value = true;
    expect(m.faltaNoPasso.value).toBe('');
  });

  it('com o WhatsApp do celular, fora das 24 h vale texto livre', async () => {
    getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: true, whatsapp_api_available: true },
    });
    const { store } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    m.avancar();
    await flushPromises();

    expect(m.soPronta.value).toBe(false);
    expect(m.peloCelular.value).toBe(true);
    expect(m.faltaNoPasso.value).toBe('TEXTO');
  });

  it('marca a mensagem pronta com o texto preenchido e os campos', async () => {
    getFollowUpMessagingWindow.mockResolvedValue({
      data: { requires_template: true, whatsapp_api_available: false },
    });
    const { store, dispatch } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    await flushPromises();

    const foi = await m.criar({
      titulo: 'Mensagem para Mariana Costa',
      montada: {
        message: 'Olá, {{1}}!',
        pendingMessageContent: 'Olá, Mariana!',
        templateParams: {
          name: 'boas_vindas',
          language: 'pt_BR',
          processed_params: { body: { 1: 'Mariana' } },
        },
      },
    });

    expect(foi).toBe(true);
    expect(dispatch).toHaveBeenCalledWith(
      'crmKanban/createFollowUp',
      expect.objectContaining({
        card_id: 3,
        conversation_id: 30,
        automation_mode: 'auto_send_message',
        timezone: 'America/Sao_Paulo',
        due_at: m.dueAt.value,
        metadata: {
          message_body: 'Olá, Mariana!',
          template_name: 'boas_vindas',
          template_language: 'pt_BR',
          template_processed_params: { body: { 1: 'Mariana' } },
        },
      })
    );
  });

  it('o 422 de horário passado vira uma frase da tela', async () => {
    const { store, dispatch } = novaLoja();
    dispatch.mockRejectedValue({
      response: { data: { code: 'due_at_in_the_past' } },
    });
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    m.mensagem.value = { texto: 'Oi!', modelo: null };

    expect(await m.criar({ titulo: 'x' })).toBe(false);
    expect(m.erro.value).toBe('PASSADO');
    dispatch.mockRejectedValue(new Error('rede'));
    await m.criar({ titulo: 'x' });
    expect(m.erro.value).toBe('GERAL');
  });

  // #2130: card arquivado não recebe mensagem marcada; a tela diz o motivo.
  it('o 422 de card arquivado vira o erro ARQUIVADO, com texto em en e pt_BR', async () => {
    const { store, dispatch } = novaLoja();
    dispatch.mockRejectedValue({
      response: { status: 422, data: { code: 'card_archived' } },
    });
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    m.mensagem.value = { texto: 'Oi!', modelo: null };

    expect(await m.criar({ titulo: 'x' })).toBe(false);
    expect(m.erro.value).toBe('ARQUIVADO');
    [en, ptBR].forEach(catalogo =>
      expect(catalogo.CRM_MENSAGEM_MARCADA.CONFIRMAR.ERRO.ARQUIVADO).toContain(
        'card'
      )
    );
  });

  it('clique duplo em "Marcar mensagem" faz uma ida só ao servidor', async () => {
    const { store, dispatch } = novaLoja();
    const m = useMensagemMarcada({ store, fuso: ref('America/Sao_Paulo') });
    m.escolherAlvo(card());
    marcarAmanha(m);
    m.mensagem.value = { texto: 'Oi!', modelo: null };

    const [primeiro, segundo] = await Promise.all([
      m.criar({ titulo: 'x' }),
      m.criar({ titulo: 'x' }),
    ]);

    expect(primeiro).toBe(true);
    expect(segundo).toBe(false);
    const criacoes = dispatch.mock.calls.filter(
      ([tipo]) => tipo === 'crmKanban/createFollowUp'
    );
    expect(criacoes).toHaveLength(1);
  });
});
