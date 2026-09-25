// Estado do enriquecimento usado pelo card da busca e pela tela de listas
// (#678): na fila do servidor o lead continua em andamento.
import { isLeadEnriched, isLeadEnriching } from '../../utils/leadEnrichment';

describe('leadEnrichment', () => {
  it.each(['queued', 'running'])(
    'lead %s no servidor está em andamento mesmo sem pedido desta tela',
    status => {
      expect(isLeadEnriching({ id: 1, enrichment_status: status }, null)).toBe(
        true
      );
    }
  );

  it('o pedido que esta tela ainda espera também conta como em andamento', () => {
    expect(isLeadEnriching({ id: 7, enrichment_status: 'pending' }, 7)).toBe(
      true
    );
  });

  it.each(['pending', 'failed', 'completed', null])(
    'lead %s sem pedido desta tela não está em andamento',
    status => {
      expect(isLeadEnriching({ id: 1, enrichment_status: status }, 2)).toBe(
        false
      );
    }
  );

  it('só completed é enriquecido', () => {
    expect(isLeadEnriched({ enrichment_status: 'completed' })).toBe(true);
    expect(isLeadEnriched({ enrichment_status: 'failed' })).toBe(false);
    expect(isLeadEnriched(null)).toBe(false);
  });
});
