// Nota técnica antiga do conector WAHA (#1941, item 2). Quando uma mensagem do
// WhatsApp não chega depois das tentativas, o conector grava na conversa uma nota
// privada com um texto técnico que começa sempre pelo mesmo título. Na tela, ela vira
// a linha de aviso da conversa, com um texto curto para quem atende. As notas novas
// já chegam como aviso pelo servidor (#1951); esta peça cuida das que ficaram gravadas.
import { INBOX_TYPES } from 'dashboard/helper/inbox';

// O título exato que o conector escreve (o ⚠️ é U+26A0 U+FE0F).
export const PREFIXO_DA_NOTA_DO_CONECTOR =
  '⚠️ **Não foi possível receber uma mensagem do WhatsApp**';

const ehCaixaDoWaha = caixa =>
  caixa?.channel_type === INBOX_TYPES.API && Boolean(caixa?.waha_provider);

// Só a nota privada, numa caixa WAHA comum, que começa pelo título do conector.
// Mensagem do cliente ou nota de atendente com outro começo ficam como estão.
export const ehNotaDoConector = ({ caixa, privada, conteudo }) =>
  privada === true &&
  typeof conteudo === 'string' &&
  conteudo.startsWith(PREFIXO_DA_NOTA_DO_CONECTOR) &&
  ehCaixaDoWaha(caixa);
