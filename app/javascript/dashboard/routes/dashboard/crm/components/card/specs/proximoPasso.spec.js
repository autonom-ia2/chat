import { passosDoCard } from '../proximoPasso';

const agora = new Date('2026-10-13T12:00:00');
const iso = texto => new Date(texto).toISOString();
const retorno = (id, quando, status = 'pending') => ({
  id,
  status,
  due_at: iso(quando),
});

describe('passosDoCard', () => {
  it('reunião de hoje vence o retorno atrasado', () => {
    const { principal, depois } = passosDoCard({
      agora,
      reuniao: { starts_at: iso('2026-10-13T15:00:00') },
      retornos: [retorno(1, '2026-10-12T10:00:00', 'overdue')],
    });
    expect(principal.tipo).toBe('reuniao_hoje');
    expect(depois.map(item => item.tipo)).toEqual(['retorno_atrasado']);
  });

  it('retorno atrasado vem antes do cliente esperando e da sugestão', () => {
    const { principal, depois } = passosDoCard({
      agora,
      retornos: [retorno(1, '2026-10-13T09:00:00')],
      esperaDesde: Math.floor(new Date('2026-10-13T10:00:00') / 1000),
      sugestao: { id: 9, to_stage_name: 'Proposta' },
    });
    expect(principal.tipo).toBe('retorno_atrasado');
    expect(depois.map(item => item.tipo)).toEqual(['espera', 'sugestao']);
  });

  it('cliente esperando resposta vira o próximo passo quando não há reunião nem atraso', () => {
    const { principal } = passosDoCard({
      agora,
      esperaDesde: Math.floor(new Date('2026-10-13T10:00:00') / 1000),
    });
    expect(principal.tipo).toBe('espera');
    expect(principal.quando.getHours()).toBe(10);
  });

  it('sugestão vence o retorno de hoje', () => {
    const { principal, depois } = passosDoCard({
      agora,
      sugestao: { id: 9, to_stage_name: 'Proposta' },
      retornos: [retorno(2, '2026-10-13T17:00:00')],
    });
    expect(principal.tipo).toBe('sugestao');
    expect(depois[0].tipo).toBe('retorno_hoje');
  });

  it('sem nada pendente, fica tudo em dia e mostra o que vem depois', () => {
    const { principal, depois } = passosDoCard({
      agora,
      reuniao: { starts_at: iso('2026-10-15T15:00:00') },
      retornos: [
        retorno(3, '2026-10-20T10:00:00'),
        retorno(4, '2026-10-10T10:00:00', 'done'),
      ],
    });
    expect(principal.tipo).toBe('em_dia');
    expect(depois.map(item => item.tipo)).toEqual([
      'reuniao_futura',
      'retorno_futuro',
    ]);
  });

  it('nunca passa de dois itens em "Depois disso"', () => {
    const { depois } = passosDoCard({
      agora,
      reuniao: { starts_at: iso('2026-10-13T15:00:00') },
      retornos: [
        retorno(1, '2026-10-12T10:00:00', 'overdue'),
        retorno(2, '2026-10-13T18:00:00'),
      ],
      esperaDesde: 1792000000,
      sugestao: { id: 9, to_stage_name: 'Proposta' },
    });
    expect(depois).toHaveLength(2);
  });

  it('ignora sugestão sem etapa e datas inválidas', () => {
    const { principal } = passosDoCard({
      agora,
      sugestao: { id: 9 },
      retornos: [{ id: 5, status: 'pending', due_at: 'x' }],
      reuniao: { starts_at: null },
    });
    expect(principal.tipo).toBe('em_dia');
  });

  it('negócio que terminou fica com "fechado" no destaque', () => {
    const { principal, depois } = passosDoCard({
      agora,
      status: 'won',
      retornos: [retorno(1, '2026-10-12T10:00:00', 'overdue')],
    });
    expect(principal.tipo).toBe('fechado');
    expect(depois[0].tipo).toBe('retorno_atrasado');
  });
});
