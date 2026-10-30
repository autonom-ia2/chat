import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  DESTINOS,
  chaveDaEscolha,
  chaveDaSituacao,
  conversaDeDestino,
  conversaDoCanal,
  conversaOculta,
  reabreAoEscrever,
  tipoAoContinuar,
} from '../continuarConversa';
import { TIPOS, oQueFalta } from '../novaConversa';

// #1505 — continuar a conversa que o contato já tem na caixa.
const ABERTA = { displayId: 61, status: 'open', locked: false, visible: true };
const TRAVADA = {
  displayId: 70,
  status: 'resolved',
  locked: true,
  visible: true,
};
const OCULTA = { displayId: null, status: null, locked: true, visible: false };
const comConversa = (conversa, dados = {}) => ({
  id: 1,
  channelType: INBOX_TYPES.API,
  conversationToContinue: conversa,
  ...dados,
});
const WHATSAPP = { id: 2, channelType: INBOX_TYPES.WHATSAPP };
const TWILIO = { id: 3, channelType: INBOX_TYPES.TWILIO, medium: 'whatsapp' };
const EMAIL = { id: 4, channelType: INBOX_TYPES.EMAIL };

describe('continuarConversa', () => {
  describe('conversaDoCanal e conversaOculta', () => {
    it('sem conversa do servidor, não há o que continuar', () => {
      expect(conversaDoCanal({ id: 1 })).toBeNull();
      expect(conversaDoCanal(null)).toBeNull();
      expect(conversaOculta({ id: 1, conversationToContinue: null })).toBe(
        false
      );
    });

    it('marca a conversa que a pessoa não pode ver', () => {
      expect(conversaOculta(comConversa(OCULTA))).toBe(true);
      expect(conversaOculta(comConversa(TRAVADA))).toBe(false);
    });
  });

  describe('conversaDeDestino', () => {
    it('com a regra "Reabrir", entra na conversa qualquer que seja a escolha', () => {
      const canal = comConversa(TRAVADA);
      expect(conversaDeDestino({ canal, destino: DESTINOS.NOVA })).toBe(
        TRAVADA
      );
    });

    it('com "Criar novas", segue a escolha', () => {
      const canal = comConversa(ABERTA);
      expect(conversaDeDestino({ canal, destino: DESTINOS.CONTINUAR })).toBe(
        ABERTA
      );
      expect(conversaDeDestino({ canal, destino: DESTINOS.NOVA })).toBeNull();
    });

    it('conversa oculta vai pela criação', () => {
      expect(
        conversaDeDestino({
          canal: comConversa(OCULTA),
          destino: DESTINOS.CONTINUAR,
        })
      ).toBeNull();
    });

    it('sem conversa, sempre cria', () => {
      expect(
        conversaDeDestino({ canal: { id: 1 }, destino: DESTINOS.CONTINUAR })
      ).toBeNull();
    });
  });

  describe('tipoAoContinuar', () => {
    it('WhatsApp: texto livre só quando a conversa aceita resposta', () => {
      expect(tipoAoContinuar({ canal: WHATSAPP, podeResponder: true })).toBe(
        TIPOS.WHATSAPP_LIVRE
      );
      expect(tipoAoContinuar({ canal: WHATSAPP, podeResponder: false })).toBe(
        TIPOS.WHATSAPP_PRONTA
      );
    });

    it('WhatsApp pelo Twilio: escreve dentro da janela, seletor fora dela', () => {
      expect(tipoAoContinuar({ canal: TWILIO, podeResponder: true })).toBe(
        TIPOS.TEXTO
      );
      expect(tipoAoContinuar({ canal: TWILIO, podeResponder: false })).toBe(
        TIPOS.WHATSAPP_TWILIO
      );
    });

    it('os outros canais ficam como são', () => {
      expect(tipoAoContinuar({ canal: EMAIL, podeResponder: false })).toBe(
        TIPOS.EMAIL
      );
    });
  });

  describe('chaveDaSituacao', () => {
    it('traduz cada situação e trata o desconhecido como aberta', () => {
      expect(chaveDaSituacao('open')).toBe('ABERTA');
      expect(chaveDaSituacao('pending')).toBe('PENDENTE');
      expect(chaveDaSituacao('snoozed')).toBe('ADIADA');
      expect(chaveDaSituacao('resolved')).toBe('RESOLVIDA');
      expect(chaveDaSituacao('outro')).toBe('ABERTA');
    });
  });

  describe('chaveDaEscolha', () => {
    it('muda com o contato, o canal ou a conversa encontrada', () => {
      const base = chaveDaEscolha({
        contato: { id: 9 },
        canal: comConversa(ABERTA),
      });
      expect(base).toBe('9|1|61');
      expect(
        chaveDaEscolha({ contato: { id: 10 }, canal: comConversa(ABERTA) })
      ).not.toBe(base);
      expect(
        chaveDaEscolha({ contato: { id: 9 }, canal: comConversa(TRAVADA) })
      ).not.toBe(base);
      expect(chaveDaEscolha({ contato: null, canal: null })).toBe('||');
    });

    it('é a mesma quando os canais só são recarregados', () => {
      const antes = chaveDaEscolha({
        contato: { id: 9 },
        canal: comConversa(ABERTA),
      });
      const depois = chaveDaEscolha({
        contato: { id: 9 },
        canal: comConversa({ ...ABERTA }),
      });
      expect(depois).toBe(antes);
    });
  });

  describe('oQueFalta ao continuar', () => {
    const ANA = { id: 1 };

    it('o tipo dado pela conversa manda: fora da janela, pede o modelo', () => {
      expect(
        oQueFalta({
          contato: ANA,
          canal: { ...WHATSAPP, whatsappApiStart: true },
          tipo: TIPOS.WHATSAPP_PRONTA,
          mensagem: 'Oi',
        })
      ).toBe('MODELO');
    });

    it('e-mail continuado não pede assunto', () => {
      expect(oQueFalta({ contato: ANA, canal: EMAIL, mensagem: 'Oi' })).toBe(
        'ASSUNTO'
      );
      expect(
        oQueFalta({
          contato: ANA,
          canal: EMAIL,
          mensagem: 'Oi',
          comAssunto: false,
        })
      ).toBe('');
    });
  });

  // #2216: pela API de mensagem, o sinal vai só para a conversa visível de caixa
  // com "Reabrir a mesma conversa"; a oculta vai pela criação e não reabre.
  describe('reabreAoEscrever', () => {
    const sinal = (conversa, destino) =>
      reabreAoEscrever(
        conversaDeDestino({ canal: comConversa(conversa), destino })
      );

    it('conversa visível de caixa com "Reabrir a mesma conversa": leva o sinal', () => {
      expect(sinal(TRAVADA, DESTINOS.CONTINUAR)).toBe(true);
      expect(sinal(TRAVADA, DESTINOS.NOVA)).toBe(true);
    });

    it('conversa oculta: não há mensagem na conversa, vai pela criação', () => {
      expect(sinal(OCULTA, DESTINOS.CONTINUAR)).toBe(false);
    });

    it('"Continuar" em caixa que cria conversas novas: sem o sinal', () => {
      expect(sinal(ABERTA, DESTINOS.CONTINUAR)).toBe(false);
      expect(sinal({ ...ABERTA, status: 'snoozed' }, DESTINOS.CONTINUAR)).toBe(
        false
      );
    });

    it('conversa nova ou sem conversa: sem o sinal', () => {
      expect(sinal(ABERTA, DESTINOS.NOVA)).toBe(false);
      expect(reabreAoEscrever(null)).toBe(false);
    });
  });
});
