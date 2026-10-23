import { avisoAoSalvar } from '../avisoAoSalvar';

const t = key => key;
const falha = data => ({ response: { status: 422, data } });

it('shows the server reason when the card is archived', () => {
  const erro = falha({
    code: 'card_archived',
    message: 'Este card está arquivado. Restaure o card antes.',
  });
  expect(avisoAoSalvar(erro, t)).toBe(
    'Este card está arquivado. Restaure o card antes.'
  );
});

it('keeps the generic alert for any other failure', () => {
  expect(avisoAoSalvar(falha({ message: 'Ends on leaves no date' }), t)).toBe(
    'CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'
  );
  expect(avisoAoSalvar(new Error('network'), t)).toBe(
    'CRM_KANBAN.ALERTS.FOLLOW_UP_SAVE_ERROR'
  );
});
