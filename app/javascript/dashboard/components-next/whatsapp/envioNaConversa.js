// O que a conversa precisa preencher num modelo antes de enviar (#1705, épico
// #1320), lido da estrutura do modelo da Meta, nunca do texto. Sem expressão
// regular. A regra do cupom e da validade é a mesma da campanha
// (formatoNaCampanha: oQuePedir, pendencias, extrasParaEnvio) e a do servidor
// (Whatsapp::Templates::SendableFormat, que o ConversationSendGuard aplica):
//   cupom (botão COPY_CODE) → o código, de 1 a 15 letras, no botão da mesma
//                             posição: { type: 'copy_code', parameter };
//   oferta com contagem     → até quando vale, em milissegundos e à frente:
//                             limited_time_offer.expiration_time_ms.
// O `isWhatsAppComplete` do @chatwoot/utils dá o modelo por pronto quando ele não
// tem campo no texto nem mídia no topo, mesmo com o cupom vazio: por isso a regra
// do botão fica aqui. Os exemplos que os dois lados leem estão em
// spec/fixtures/whatsapp_templates/formatos_da_conversa.json.
// Formato do envio: developers.facebook.com/documentation/business-messaging/
// whatsapp/templates/marketing-templates/limited-time-offer-templates
// (Updated Jun 17, 2026; HTML lido em 16/10/2026).
import { isWhatsAppComplete } from '@chatwoot/utils';
import {
  extrasParaEnvio,
  oQuePedir,
  pendencias,
} from 'dashboard/routes/dashboard/campaigns/modelos/helpers/formatoNaCampanha';

const maiusculo = valor => String(valor || '').toUpperCase();
const botoesDoModelo = template =>
  (template?.components || []).find(item => maiusculo(item?.type) === 'BUTTONS')
    ?.buttons || [];

// Só a parte da campanha que a conversa usa (sem topo, cartões nem produtos).
const SO_ISTO = { cartoes: [], produtos: null };
const pendente = (parte, valores, timeZone, agora = Date.now()) =>
  pendencias({ ...SO_ISTO, ...parte }, valores, { timeZone, agora });

// A oferta mostra a contagem (has_expiration): a validade vai em cada envio.
export const pedeValidade = template => oQuePedir(template).validade;

export const codigoValido = codigo =>
  pendente({ cupom: {} }, { cupom: String(codigo ?? '') }).length === 0;

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

// Todo botão que o envio leva preenchido (cupom, fim variável do endereço): o
// `isWhatsAppComplete` só confere botões quando há campo no texto ou mídia.
const botoesPreenchidos = params =>
  (Array.isArray(params?.buttons) ? params.buttons : []).every(
    botao => !botao || String(botao.parameter ?? '').trim().length > 0
  );

const validadeNoEnvio = (template, params, agora) => {
  if (!pedeValidade(template)) return true;
  const validade = Number(params?.limited_time_offer?.expiration_time_ms);
  return Number.isInteger(validade) && validade > agora;
};

// O envio da conversa pode sair com estes `processed_params`?
export const envioCompleto = (template, params = {}, agora = Date.now()) =>
  isWhatsAppComplete(template, params) &&
  botoesPreenchidos(params) &&
  cuponsPreenchidos(template, params) &&
  validadeNoEnvio(template, params, agora);

// A validade digitada (`2026-10-20T18:00`) vale no fuso da conta.
// '' = pronta; 'VALIDADE' = falta; 'VALIDADE_PASSADA' = já passou;
// 'SEM_FUSO' = a conta não tem fuso (a hora nunca é lida no do navegador).
export const validadeFaltando = (local, fuso, agora = Date.now()) => {
  if (!fuso) return 'SEM_FUSO';
  return (
    pendente({ validade: true }, { validade: local }, fuso, agora)[0] || ''
  );
};

// Os `processed_params` com a validade, no formato que o envio monta
// (Whatsapp::Templates::SendComponents). Sem validade a pedir ou digitada, iguais.
export const comValidade = (template, params, local, fuso) => {
  if (!pedeValidade(template)) return params;
  if (!['', 'VALIDADE_PASSADA'].includes(validadeFaltando(local, fuso))) {
    return params;
  }
  const { limited_time_offer: oferta } = extrasParaEnvio(
    { ...SO_ISTO, validade: true },
    { validade: local },
    { timeZone: fuso }
  );
  return { ...params, limited_time_offer: oferta };
};
