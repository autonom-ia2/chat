// A mensagem que a equipe apagou sumiu também do celular do cliente? (#1702)
// - Caixa WAHA (API ligada ao WAHA): o conector apaga no WhatsApp, como o app.
// - Oficial (Cloud, 360dialog), Twilio e híbrida: a API não apaga a mensagem no
//   WhatsApp; apagar no painel é só aqui, até o servidor gravar
//   content_attributes.revogada_no_canal (confirmação do canal), que vale em qualquer
//   caixa.
import { INBOX_TYPES } from 'dashboard/helper/inbox';

const ehCaixaDoWaha = caixa =>
  caixa?.channel_type === INBOX_TYPES.API && Boolean(caixa?.waha_provider);

export const apagadaParaTodos = ({ caixa, contentAttributes }) =>
  contentAttributes?.revogadaNoCanal === true || ehCaixaDoWaha(caixa);
