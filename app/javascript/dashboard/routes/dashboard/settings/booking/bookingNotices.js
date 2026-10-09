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
// cancela e para os avisos. Variável além dessas, variável no topo ou botão
// com link variável a Meta recusa no envio (o aviso não as preenche).
const LINK_VARIABLE = '{{3}}';
const FILLED_VARIABLES = ['1', '2', '3'];

export const presetFor = key =>
  NOTICE_PRESETS.find(preset => preset.key === key) || NOTICE_PRESETS[0];

// Avisos que pedem modelo: os do jogo escolhido e o de "horário mudou".
export const templateKinds = presetKey => [
  ...presetFor(presetKey).kinds,
  RESCHEDULED_NOTICE,
];

const bodyText = template => findComponentByType(template, 'BODY')?.text || '';

// Nomes das variáveis do texto: o que vem entre `{{` e `}}` (sem regex).
const variablesOf = text =>
  String(text)
    .split('{{')
    .slice(1)
    .map(part => part.split('}}')[0].trim());

const asksMore = template => {
  const header = findComponentByType(template, 'HEADER');
  const buttons = findComponentByType(template, 'BUTTONS')?.buttons || [];
  return (
    String(header?.text || '').includes('{{') ||
    buttons.some(button => String(button?.url || '').includes('{{'))
  );
};

// Modelos que o aviso consegue usar: aprovados e enviáveis (a mesma regra da
// conversa), sem imagem ou documento no topo, com o link no texto e pedindo
// só o que o aviso preenche (a mesma regra do servidor ao salvar e ao enviar).
export const usableTemplates = templates =>
  (Array.isArray(templates) ? templates : []).filter(
    template =>
      isSendableTemplate(template) &&
      !hasMediaHeader(template) &&
      bodyText(template).includes(LINK_VARIABLE) &&
      variablesOf(bodyText(template)).every(name =>
        FILLED_VARIABLES.includes(name)
      ) &&
      !asksMore(template)
  );

// Como a mensagem chega, em uma linha: as variáveis trocadas por exemplos
// (troca de texto, sem regex) e cortada no tamanho de uma opção da lista.
const PREVIEW_LENGTH = 90;
export const templatePreview = (template, samples) => {
  const filled = [samples.name, samples.when, samples.link].reduce(
    (text, value, index) => text.split(`{{${index + 1}}}`).join(value),
    bodyText(template)
  );
  const line = filled.split('\n').join(' ').trim();
  return line.length > PREVIEW_LENGTH
    ? `${line.slice(0, PREVIEW_LENGTH - 1).trimEnd()}…`
    : line;
};

// Chave da escolha na lista: nome e idioma juntos identificam o modelo na Meta;
// no canal API de campanhas, o id do modelo do canal.
export const templateChoice = template => {
  if (!template) return '';
  if (template.id !== undefined && !template.language)
    return `id:${template.id}`;
  return `${template.name} · ${template.language}`;
};

// Caixa cujo aviso fora das 24 h depende de mensagem pronta escolhida aqui:
// WhatsApp oficial (aprovada na Meta) e canal API de campanhas (do canal).
export const templatesNeeded = inbox =>
  Boolean(inbox && (inbox.needs_templates || inbox.provider === 'api'));

// Avisos do jogo (e o de horário mudou) sem mensagem pronta: esses só saem
// para quem falou com a empresa nas últimas 24 horas.
export const kindsWithoutTemplate = (form, inbox) =>
  templatesNeeded(inbox)
    ? templateKinds(form.noticePreset).filter(
        kind => !form.noticeTemplates?.[kind]
      )
    : [];

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
