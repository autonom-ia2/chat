// Conversa com a cara do canal (#1702, épico #1701). A "pele" é o visual do app do
// cliente aplicado à conversa e à caixa de resposta, sem mudar o que cada peça faz.
// Quem decide é a tela da conversa (MessagesView), que fornece a pele uma vez; as
// bolhas, a hora e a caixa de resposta só perguntam qual é. Sem pele, tudo como antes.
import { computed, inject, provide } from 'vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const PELES = { WHATSAPP: 'whatsapp' };

// Evento do aviso das 24 h: a caixa de resposta abre a escolha de modelo.
export const ABRIR_MODELOS_DO_WHATSAPP = 'conversaCanal:abrirModelos';

const CHAVE_PELE = Symbol('peleDaConversa');
const CHAVE_PRIMEIRAS = Symbol('primeirasDoGrupo');
const CHAVE_FUSO = Symbol('fusoDaConversa');

// WhatsApp oficial (inclui a caixa híbrida, que é uma oficial com conexão auxiliar)
// e a caixa API ligada ao WAHA. O WhatsApp do Twilio fica de fora: outro fornecedor,
// outros recursos.
export const peleDaCaixa = (inbox, ligada) => {
  if (!ligada || !inbox) return null;
  if (inbox.channel_type === INBOX_TYPES.WHATSAPP) return PELES.WHATSAPP;
  if (inbox.channel_type === INBOX_TYPES.API && inbox.waha_provider) {
    return PELES.WHATSAPP;
  }
  return null;
};

export const fornecerPele = pele => provide(CHAVE_PELE, pele);

// Fora da conversa (prévias, histórias, outras telas) não há pele.
export const usePele = () =>
  inject(
    CHAVE_PELE,
    computed(() => null)
  );

// O fuso da conta, lido uma vez pela tela da conversa (e não por mensagem).
export const fornecerFuso = fuso => provide(CHAVE_FUSO, fuso);

export const useFuso = () =>
  inject(
    CHAVE_FUSO,
    computed(() => undefined)
  );

export const fornecerPrimeiras = primeiras =>
  provide(CHAVE_PRIMEIRAS, primeiras);

export const usePrimeiras = () =>
  inject(
    CHAVE_PRIMEIRAS,
    computed(() => new Set())
  );
