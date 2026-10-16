// O que a conversa precisa preencher num modelo antes de enviar (#1705, épico
// #1320), lido da estrutura do modelo da Meta, nunca do texto. Sem expressão
// regular. Mesma regra do servidor (Whatsapp::Templates::SendableFormat, que o
// Whatsapp::Templates::ConversationSendGuard aplica no envio):
//   cupom (botão COPY_CODE) → o código, de 1 a 15 letras, no botão da mesma
//                             posição: { type: 'copy_code', parameter };
//   oferta com contagem     → até quando vale, em milissegundos e à frente:
//                             limited_time_offer.expiration_time_ms.
// O `isWhatsAppComplete` do @chatwoot/utils dá o modelo por pronto quando ele não
// tem campo no texto nem mídia no topo, mesmo com o cupom vazio: por isso a regra
// do botão fica aqui. Os exemplos que os dois lados leem estão em
// spec/fixtures/whatsapp_templates/formatos_da_conversa.json.
// Envio: developers.facebook.com/documentation/business-messaging/whatsapp/
// templates/marketing-templates/limited-time-offer-templates (Updated Jun 17,
// 2026; lida em 16/10/2026).
import { isWhatsAppComplete } from '@chatwoot/utils';
import {
  isFutureSchedule,
  scheduleToUtc,
} from 'dashboard/components-next/CampaignJourney/scheduleTime';
import { CODIGO_MAXIMO } from 'dashboard/routes/dashboard/campaigns/modelos/helpers/formatoNaCampanha';

const maiusculo = valor => String(valor || '').toUpperCase();
const componente = (template, tipo) =>
  (template?.components || []).find(item => maiusculo(item?.type) === tipo);
const botoesDoModelo = template =>
  componente(template, 'BUTTONS')?.buttons || [];

// A oferta mostra a contagem (has_expiration): a validade vai em cada envio.
export const pedeValidade = template =>
  componente(template, 'LIMITED_TIME_OFFER')?.limited_time_offer
    ?.has_expiration === true;

export const codigoValido = codigo => {
  const limpo = String(codigo ?? '').trim();
  return limpo.length >= 1 && limpo.length <= CODIGO_MAXIMO;
};

// Cada cupom do modelo com o código no botão da mesma posição.
export const cuponsPreenchidos = (template, params) => {
  const enviados = Array.isArray(params?.buttons) ? params.buttons : [];
  return botoesDoModelo(template).every((botao, indice) => {
    if (maiusculo(botao?.type) !== 'COPY_CODE') return true;
    const enviado = enviados[indice];
    return (
      maiusculo(enviado?.type) === 'COPY_CODE' &&
      codigoValido(enviado?.parameter)
    );
  });
};

const validadeNoEnvio = (template, params, agora) => {
  if (!pedeValidade(template)) return true;
  const validade = Number(params?.limited_time_offer?.expiration_time_ms);
  return Number.isInteger(validade) && validade > agora;
};

// O envio da conversa pode sair com estes `processed_params`?
export const envioCompleto = (template, params = {}, agora = Date.now()) =>
  isWhatsAppComplete(template, params) &&
  cuponsPreenchidos(template, params) &&
  validadeNoEnvio(template, params, agora);

// A validade digitada (`2026-10-20T18:00`) vale no fuso da conta.
// '' = pronta; 'VALIDADE' = falta; 'VALIDADE_PASSADA' = já passou.
export const validadeFaltando = (local, fuso, agora = Date.now()) => {
  if (!scheduleToUtc(local, fuso)) return 'VALIDADE';
  return isFutureSchedule(local, fuso, agora) ? '' : 'VALIDADE_PASSADA';
};

// Os `processed_params` com a validade, no formato que o envio monta
// (Whatsapp::Templates::SendComponents). Sem validade a pedir, iguais.
export const comValidade = (template, params, local, fuso) => {
  if (!pedeValidade(template)) return params;
  const iso = scheduleToUtc(local, fuso);
  if (!iso) return params;
  return {
    ...params,
    limited_time_offer: { expiration_time_ms: new Date(iso).getTime() },
  };
};
