// #2202 — o ícone da caixa no card da lista. O WhatsApp pelo celular é uma caixa API ligada ao WAHA:
// para a pessoa, é WhatsApp, então leva o ícone do WhatsApp (e não o "{ }" da API). Aceita a caixa
// como vem do servidor (snake_case) ou já em camelCase.
import { getInboxIconByType, tipoDoIconeDaCaixa } from 'dashboard/helper/inbox';

export const iconeDaCaixa = caixa => {
  if (!caixa) return '';
  return getInboxIconByType(tipoDoIconeDaCaixa(caixa), caixa.medium, 'line');
};
