import {
  negocioDoCard,
  payloadDoNegocio,
  promessaDoCard,
} from '../useCardNegocio';

// #1498 — a promessa de pagamento da Cobrança vai e volta com o card.
describe('useCardNegocio promessa', () => {
  it('reads the promise from the card metadata', () => {
    const card = { metadata: { payment_promise_at: '2026-10-20' } };
    expect(promessaDoCard(card)).toBe('2026-10-20');
    expect(negocioDoCard(card).paymentPromiseAt).toBe('2026-10-20');
  });

  it('prefers the field just saved over the old metadata', () => {
    const card = {
      payment_promise_at: null,
      metadata: { payment_promise_at: '2026-10-20' },
    };
    expect(promessaDoCard(card)).toBe('');
  });

  it('sends the promise only for Collections, or null to clear it', () => {
    const form = negocioDoCard({ title: 'Mensalidade' });
    expect(payloadDoNegocio(form)).not.toHaveProperty('payment_promise_at');
    expect(
      payloadDoNegocio(form, { cobranca: true }).payment_promise_at
    ).toBeNull();
    expect(
      payloadDoNegocio(
        { ...form, paymentPromiseAt: '2026-10-20' },
        { cobranca: true }
      ).payment_promise_at
    ).toBe('2026-10-20');
  });
});

// #2075 — sem a chave de valores a pessoa não vê o valor: salvar não manda valor nem moeda.
describe('useCardNegocio valor oculto', () => {
  it('leaves value and currency out when the value is hidden', () => {
    const form = negocioDoCard({ title: 'Plano', value_cents: null });
    const payload = payloadDoNegocio(form, { valorOculto: true });
    expect(payload).not.toHaveProperty('value_cents');
    expect(payload).not.toHaveProperty('currency');
    expect(payload.title).toBe('Plano');
  });

  it('keeps sending the value when the person sees it', () => {
    const form = negocioDoCard({ title: 'Plano', value_cents: 150000 });
    expect(payloadDoNegocio(form)).toMatchObject({
      value_cents: 150000,
      currency: 'BRL',
    });
  });
});
