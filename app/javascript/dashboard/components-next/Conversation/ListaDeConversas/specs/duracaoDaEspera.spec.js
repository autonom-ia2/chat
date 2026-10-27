import { FAIXA, duracaoDaEspera, faixaDaEspera } from '../duracaoDaEspera';
import { t } from './apoio';

const MIN = 60;
const HORA = 60 * MIN;
const DIA = 24 * HORA;
const d = s => duracaoDaEspera(s, t);

describe('duracaoDaEspera (#2202)', () => {
  it('não deixa buraco entre as faixas', () => {
    expect(d(59)).toBe('há menos de 1 min');
    expect(d(60)).toBe('há 1 min');
    expect(d(59 * MIN + 59)).toBe('há 59 min');
    expect(d(HORA)).toBe('há 1 hora');
    expect(d(23 * HORA + 59 * MIN)).toBe('há 23 horas');
    expect(d(DIA)).toBe('há 1 dia');
    expect(d(89 * DIA)).toBe('há 89 dias');
    expect(d(90 * DIA)).toBe('há 3 meses');
  });
});

describe('faixaDaEspera (#2202, decisão 6)', () => {
  it('bordas: 14:59/15:00, 1:59/2:00 e 6d23h/7d', () => {
    expect(faixaDaEspera(15 * MIN - 1)).toBe(FAIXA.CALMA);
    expect(faixaDaEspera(15 * MIN)).toBe(FAIXA.ATENCAO);
    expect(faixaDaEspera(2 * HORA - 1)).toBe(FAIXA.ATENCAO);
    expect(faixaDaEspera(2 * HORA)).toBe(FAIXA.URGENTE);
    expect(faixaDaEspera(7 * DIA - HORA)).toBe(FAIXA.URGENTE);
    expect(faixaDaEspera(7 * DIA)).toBe(FAIXA.PARADA);
  });
});
