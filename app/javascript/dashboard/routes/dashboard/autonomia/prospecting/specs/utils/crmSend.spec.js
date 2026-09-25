// Envio ao CRM em lotes (#680): o servidor aceita até 30 leads por pedido e
// devolve o resultado de cada um. A tela junta os lotes num resumo só.
import {
  CRM_BATCH_SIZE,
  sendInBatches,
  sendOutcome,
} from '../../utils/crmSend';

const ids = count => Array.from({ length: count }, (_, index) => index + 1);

const createdFor = leadIds => ({
  data: {
    payload: {
      created: leadIds.map(leadId => ({
        lead_id: leadId,
        card_id: leadId * 10,
        contact_id: leadId * 100,
        company_id: 7,
      })),
      existing: [],
      failed: [],
    },
  },
});

describe('sendInBatches', () => {
  it('manda no máximo 30 leads por pedido, um lote depois do outro', async () => {
    const request = vi.fn(leadIds => Promise.resolve(createdFor(leadIds)));

    const summary = await sendInBatches(ids(65), request);

    expect(CRM_BATCH_SIZE).toBe(30);
    expect(request.mock.calls.map(([leadIds]) => leadIds.length)).toEqual([
      30, 30, 5,
    ]);
    expect(request.mock.calls[2][0]).toEqual([61, 62, 63, 64, 65]);
    expect(summary.created).toHaveLength(65);
    expect(summary.created[64]).toEqual({
      lead_id: 65,
      card_id: 650,
      contact_id: 6500,
      company_id: 7,
    });
  });

  it('junta criados, já existentes e falhas de todos os lotes', async () => {
    const request = vi
      .fn()
      .mockResolvedValueOnce({
        data: {
          payload: {
            created: [{ lead_id: 1, card_id: 10 }],
            existing: [{ lead_id: 2, card_id: 20 }],
            failed: [
              { lead_id: 3, reason_code: 'not_found', message: 'Sumiu' },
            ],
          },
        },
      })
      .mockResolvedValueOnce({
        data: {
          payload: {
            created: [],
            existing: [{ lead_id: 31, card_id: 310 }],
            failed: [],
          },
        },
      });

    const summary = await sendInBatches(ids(31), request);

    expect(summary).toEqual({
      created: [{ lead_id: 1, card_id: 10 }],
      existing: [
        { lead_id: 2, card_id: 20 },
        { lead_id: 31, card_id: 310 },
      ],
      failed: [{ lead_id: 3, reason_code: 'not_found', message: 'Sumiu' }],
    });
  });

  it('pedido recusado vira falha de cada lead do lote, com a mensagem do servidor, e os outros lotes seguem', async () => {
    const request = vi
      .fn()
      .mockRejectedValueOnce({
        response: { data: { error: 'Estágio não pertence ao funil' } },
      })
      .mockImplementationOnce(leadIds => Promise.resolve(createdFor(leadIds)));

    const summary = await sendInBatches(ids(32), request);

    expect(summary.failed).toHaveLength(30);
    expect(summary.failed[0]).toEqual({
      lead_id: 1,
      reason_code: 'request_failed',
      message: 'Estágio não pertence ao funil',
    });
    expect(summary.created.map(item => item.lead_id)).toEqual([31, 32]);
  });

  it('pedido sem resposta vira falha sem mensagem, para a tela usar o texto dela', async () => {
    const request = vi.fn().mockRejectedValue(new Error('Network Error'));

    const summary = await sendInBatches([5], request);

    expect(summary.failed).toEqual([
      { lead_id: 5, reason_code: 'request_failed', message: null },
    ]);
  });

  it('conta o andamento a cada lote', async () => {
    const request = vi.fn(leadIds => Promise.resolve(createdFor(leadIds)));
    const progress = vi.fn();

    await sendInBatches(ids(61), request, progress);

    expect(progress.mock.calls).toEqual([[30], [60], [61]]);
  });
});

describe('sendOutcome', () => {
  it('sucesso só quando nada falhou', () => {
    expect(sendOutcome({ created: [{}], existing: [{}], failed: [] })).toBe(
      'success'
    );
  });

  it('parcial quando algo foi e algo falhou', () => {
    expect(sendOutcome({ created: [], existing: [{}], failed: [{}] })).toBe(
      'partial'
    );
  });

  it('falha quando todos falharam', () => {
    expect(sendOutcome({ created: [], existing: [], failed: [{}] })).toBe(
      'failed'
    );
  });
});
