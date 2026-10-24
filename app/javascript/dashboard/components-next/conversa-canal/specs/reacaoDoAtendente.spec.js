import {
  REACOES_RAPIDAS,
  emojiParaEnviar,
  estadoDaReacao,
  proximoIndice,
  reacaoDaEquipe,
} from '../reacaoDoAtendente';

const CLOUD = { channel_type: 'Channel::Whatsapp', provider: 'whatsapp_cloud' };
const WAHA = { channel_type: 'Channel::Api', waha_provider: true };
const JANELA_ABERTA = { can_reply: true, whatsapp_api_reply: false };
const recebida = {
  messageType: 0,
  isPrivate: false,
  status: 'sent',
  sourceId: 'wamid.A',
};
const enviada = { ...recebida, messageType: 1 };

describe('reacaoDoAtendente', () => {
  it('tem os 6 rápidos do WhatsApp', () => {
    expect(REACOES_RAPIDAS).toEqual(['👍', '❤️', '😂', '😮', '😢', '🙏']);
  });

  it('acha a reação da empresa (qualquer atendente) e ignora a do cliente', () => {
    const reacoes = [
      { emoji: '🙏', sender_type: 'Contact' },
      { emoji: '👍', senderType: 'User' },
    ];
    expect(reacaoDaEquipe(reacoes)).toBe('👍');
    expect(reacaoDaEquipe([{ emoji: '🙏', sender_type: 'Contact' }])).toBe('');
  });

  it('o mesmo emoji de novo tira a reação', () => {
    expect(emojiParaEnviar('👍', '👍')).toBe('');
    expect(emojiParaEnviar('👍', '❤️')).toBe('❤️');
    expect(emojiParaEnviar('', '❤️')).toBe('❤️');
  });

  describe('estadoDaReacao', () => {
    const estado = (caixa, mensagem, conversa = JANELA_ABERTA) =>
      estadoDaReacao({ caixa, conversa, mensagem });

    it('oficial: reage à mensagem do cliente com a janela aberta', () => {
      expect(estado(CLOUD, recebida)).toEqual({
        visivel: true,
        bloqueado: false,
      });
    });

    it('não reage à mensagem apagada pelo cliente (o servidor recusa)', () => {
      const apagada = {
        ...recebida,
        contentAttributes: { deletedByContactAt: '2026-10-16T18:00:00Z' },
      };
      expect(estado(CLOUD, apagada).visivel).toBe(false);
    });

    it('oficial: não reage à mensagem enviada (a Meta só aceita a do cliente)', () => {
      expect(estado(CLOUD, enviada).visivel).toBe(false);
    });

    it('oficial fora das 24 h: botão bloqueado', () => {
      expect(estado(CLOUD, recebida, { can_reply: false }).bloqueado).toBe(
        true
      );
    });

    it('híbrido fora das 24 h (sai pelo número reserva): bloqueado', () => {
      const conversa = { can_reply: true, whatsapp_api_reply: true };
      expect(estado(CLOUD, recebida, conversa).bloqueado).toBe(true);
    });

    it('WAHA: recebida ou enviada, sem janela', () => {
      const semJanela = { can_reply: false };
      expect(estado(WAHA, enviada, semJanela)).toEqual({
        visivel: true,
        bloqueado: false,
      });
      expect(estado(WAHA, recebida, semJanela).visivel).toBe(true);
    });

    it('nota privada, apagada, sem id do WhatsApp ou ainda enviando: some', () => {
      expect(estado(CLOUD, { ...recebida, isPrivate: true }).visivel).toBe(
        false
      );
      expect(estado(CLOUD, { ...recebida, deleted: true }).visivel).toBe(false);
      expect(estado(CLOUD, { ...recebida, sourceId: '' }).visivel).toBe(false);
      expect(estado(WAHA, { ...enviada, status: 'progress' }).visivel).toBe(
        false
      );
      expect(estado(WAHA, { ...enviada, status: 'failed' }).visivel).toBe(
        false
      );
    });

    it('Instagram (#2113): só a mensagem do cliente, bloqueado fora da janela', () => {
      const INSTAGRAM = { channel_type: 'Channel::Instagram' };
      const doCliente = { ...recebida, sourceId: 'mid.A' };
      expect(estado(INSTAGRAM, doCliente)).toEqual({
        visivel: true,
        bloqueado: false,
      });
      expect(estado(INSTAGRAM, { ...doCliente, messageType: 1 }).visivel).toBe(
        false
      );
      expect(estado(INSTAGRAM, { ...doCliente, sourceId: '' }).visivel).toBe(
        false
      );
      expect(estado(INSTAGRAM, doCliente, { can_reply: false }).bloqueado).toBe(
        true
      );
    });

    it('Instagram (#2113): com o texto em 7 dias (HUMAN_AGENT), a reação fica nas 24 h', () => {
      const INSTAGRAM = { channel_type: 'Channel::Instagram' };
      const doCliente = { ...recebida, sourceId: 'mid.A' };
      const agora = 1_800_000_000;
      const conversa = horas => ({
        ...JANELA_ABERTA,
        messages: [
          { message_type: 0, created_at: agora - horas * 3600 },
          { message_type: 1, created_at: agora - 60 },
        ],
      });
      const bloqueado = horas =>
        estadoDaReacao({
          caixa: INSTAGRAM,
          conversa: conversa(horas),
          mensagem: doCliente,
          agora,
        }).bloqueado;

      expect(bloqueado(23)).toBe(false);
      expect(bloqueado(30)).toBe(true);
      expect(
        estadoDaReacao({
          caixa: CLOUD,
          conversa: conversa(30),
          mensagem: recebida,
          agora,
        }).bloqueado
      ).toBe(false);
    });

    it('a linha da reação que o agente da Autonomia leu não reage', () => {
      const INSTAGRAM = { channel_type: 'Channel::Instagram' };
      const sintetica = {
        ...recebida,
        sourceId: 'ig_reaction:mid.A:1792000000000',
        contentAttributes: { autonomiaReaction: { emoji: '❤️' } },
      };
      expect(estado(INSTAGRAM, sintetica).visivel).toBe(false);
    });

    it('Instagram por página do Facebook não reage pelo painel', () => {
      const pagina = { channel_type: 'Channel::FacebookPage' };
      expect(estado(pagina, recebida).visivel).toBe(false);
    });

    it('caixa que não é WhatsApp (nem 360dialog): some', () => {
      const dialog = { channel_type: 'Channel::Whatsapp', provider: 'default' };
      expect(estado(dialog, recebida).visivel).toBe(false);
      expect(estado({ channel_type: 'Channel::Api' }, recebida).visivel).toBe(
        false
      );
    });
  });

  it('setas andam na barra dando a volta; outra tecla não mexe', () => {
    expect(proximoIndice('ArrowRight', 6, 7)).toBe(0);
    expect(proximoIndice('ArrowLeft', 0, 7)).toBe(6);
    expect(proximoIndice('Home', 3, 7)).toBe(0);
    expect(proximoIndice('End', 3, 7)).toBe(6);
    expect(proximoIndice('a', 3, 7)).toBeNull();
  });
});
