import {
  findComponentByType,
  hasMediaHeader,
  isSendableTemplate,
} from '@chatwoot/utils';
import { NOTICE_PRESETS, RESCHEDULED_NOTICE } from './constants';

// Avisos no WhatsApp da página de agendamento (#1192, contrato F2-A). Funções
// puras: o passo de avisos, a prévia e o teste usam as mesmas regras.

// O modelo da Meta recebe {{1}} primeiro nome, {{2}} dia e hora e {{3}} o link
// de gestão. O link é obrigatório: é nele que o cliente confirma, muda,
// cancela e para os avisos.
const LINK_VARIABLE = '{{3}}';

export const presetFor = key =>
  NOTICE_PRESETS.find(preset => preset.key === key) || NOTICE_PRESETS[0];

// Avisos que pedem modelo: os do jogo escolhido e o de "horário mudou".
export const templateKinds = presetKey => [
  ...presetFor(presetKey).kinds,
  RESCHEDULED_NOTICE,
];

const bodyText = template => findComponentByType(template, 'BODY')?.text || '';

// Modelos que o aviso consegue usar: aprovados e enviáveis (a mesma regra da
// conversa), sem imagem ou documento no topo e com o link no texto.
export const usableTemplates = templates =>
  (Array.isArray(templates) ? templates : []).filter(
    template =>
      isSendableTemplate(template) &&
      !hasMediaHeader(template) &&
      bodyText(template).includes(LINK_VARIABLE)
  );

// Chave da escolha na lista: nome e idioma juntos identificam o modelo na Meta.
export const templateChoice = template =>
  template ? `${template.name} · ${template.language}` : '';

// Só os modelos dos avisos que o jogo usa; sem caixa de avisos, nenhum.
export const noticeTemplatesPayload = form => {
  if (!form.noticeInboxId) return {};
  return Object.fromEntries(
    templateKinds(form.noticePreset)
      .filter(kind => form.noticeTemplates[kind])
      .map(kind => [kind, form.noticeTemplates[kind]])
  );
};

// "Testar no meu WhatsApp": o código da recusa (422) vira a chave do aviso em
// BOOKING.NOTICES.TEST.ERRORS.
const TEST_ERRORS = {
  notice_inbox_missing: 'NO_INBOX',
  notice_inbox_forbidden: 'FORBIDDEN',
  page_not_published: 'NOT_PUBLISHED',
  invalid_phone: 'INVALID_PHONE',
};
const TEST_REASONS = {
  template_required: 'OUTSIDE_WINDOW',
  waha_outside_window: 'OUTSIDE_WINDOW',
  number_cap: 'NUMBER_CAP',
  stopped: 'STOPPED',
  conversation_forbidden: 'CONVERSATION_FORBIDDEN',
};

export const testInviteProblem = data => {
  if (TEST_REASONS[data?.reason]) return TEST_REASONS[data.reason];
  if (data?.error === 'cannot_send') return 'CANNOT_SEND';
  return TEST_ERRORS[data?.error] || 'FAILED';
};
