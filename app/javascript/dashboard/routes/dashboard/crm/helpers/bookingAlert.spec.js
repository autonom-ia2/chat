import { bookingAlert } from './bookingAlert';

describe('bookingAlert', () => {
  it('lembrete comum do CRM não é alerta do agendamento', () => {
    expect(bookingAlert({ id: 1, title: 'Retornar' })).toBeNull();
    expect(bookingAlert({ id: 1, metadata: { source: 'manual' } })).toBeNull();
    expect(bookingAlert(null)).toBeNull();
  });

  it('aviso que não saiu traz cliente, horário e o motivo conhecido', () => {
    const alert = bookingAlert({
      metadata: {
        source: 'booking_agent_alert',
        event: 'notice_failed',
        contact_name: 'Marcos',
        starts_at: '2026-10-20T13:00:00Z',
        reason: 'template_required',
      },
    });

    expect(alert).toEqual({
      isNoticeFailed: true,
      name: 'Marcos',
      startsAt: '2026-10-20T13:00:00Z',
      reasonKey: 'TEMPLATE_REQUIRED',
    });
  });

  it('erro do envio (classe do erro) e alerta antigo ficam sem motivo com texto', () => {
    const failed = bookingAlert({
      metadata: {
        source: 'booking_agent_alert',
        event: 'notice_failed',
        reason: 'Net::ReadTimeout',
      },
    });
    const old = bookingAlert({
      metadata: { source: 'booking_agent_alert', event: 'notice_failed' },
    });

    expect(failed.reasonKey).toBeNull();
    expect(old).toMatchObject({ isNoticeFailed: true, name: '', startsAt: '' });
    expect(old.reasonKey).toBeNull();
  });

  it('o que o cliente fez pela página é alerta, mas não é aviso que não saiu', () => {
    const alert = bookingAlert({
      metadata: { source: 'booking_agent_alert', event: 'canceled' },
    });

    expect(alert.isNoticeFailed).toBe(false);
  });
});
