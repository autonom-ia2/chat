import {
  criarRegistroDeBusca,
  filtrarFerramentas,
  semAcento,
} from '../../vitrine/busca';

// #2858 F2 — a busca da vitrine (trecho sem acento, sem regex) e o registro da busca sem resultado: uma vez por termo,
// depois de a pessoa parar de digitar.
const FERRAMENTAS = [
  { id: 'fipe', texto: 'Valor do carro tabela FIPE Veículos' },
  { id: 'cep', texto: 'Endereço pelo CEP Endereço e lugar' },
  { id: 'feriados', texto: 'Feriados e dias úteis Dinheiro e prazos' },
];
const textoDe = ferramenta => ferramenta.texto;
const ids = lista => lista.map(item => item.id);

describe('busca da vitrine', () => {
  it('ignores accents and case', () => {
    expect(semAcento('Endereço ÚTEIS')).toBe('endereco uteis');
    expect(ids(filtrarFerramentas(FERRAMENTAS, 'ENDERECO', textoDe))).toEqual([
      'cep',
    ]);
    expect(ids(filtrarFerramentas(FERRAMENTAS, 'dias uteis', textoDe))).toEqual(
      ['feriados']
    );
  });

  it('finds by a piece of a word, and every word must be there', () => {
    expect(ids(filtrarFerramentas(FERRAMENTAS, 'carr', textoDe))).toEqual([
      'fipe',
    ]);
    expect(filtrarFerramentas(FERRAMENTAS, 'carro cep', textoDe)).toEqual([]);
  });

  it('an empty search shows everything', () => {
    expect(filtrarFerramentas(FERRAMENTAS, '   ', textoDe)).toBe(FERRAMENTAS);
  });

  it('special characters are plain text, not a pattern', () => {
    expect(filtrarFerramentas(FERRAMENTAS, '.*', textoDe)).toEqual([]);
  });
});

describe('registro da busca sem resultado', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  const novo = () => {
    const registrar = vi.fn();
    return { registrar, registro: criarRegistroDeBusca({ registrar }) };
  };

  it('records only after the person stops typing', () => {
    const { registrar, registro } = novo();
    registro.observar('pas', true);
    vi.advanceTimersByTime(1000);
    registro.observar('passagem', true);
    vi.advanceTimersByTime(1499);
    expect(registrar).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1);
    expect(registrar).toHaveBeenCalledTimes(1);
    expect(registrar).toHaveBeenCalledWith('passagem');
  });

  it('records each term once', () => {
    const { registrar, registro } = novo();
    registro.observar('passagem', true);
    vi.advanceTimersByTime(1500);
    registro.observar('Passagem ', true);
    vi.advanceTimersByTime(1500);
    registro.observar('passágem', true);
    vi.advanceTimersByTime(1500);
    expect(registrar).toHaveBeenCalledTimes(1);
    registro.observar('barco', true);
    vi.advanceTimersByTime(1500);
    expect(registrar.mock.calls).toEqual([['passagem'], ['barco']]);
  });

  it('does not record short terms, or terms that found something', () => {
    const { registrar, registro } = novo();
    registro.observar('ab', true);
    vi.advanceTimersByTime(1500);
    registro.observar('carro', false);
    vi.advanceTimersByTime(1500);
    expect(registrar).not.toHaveBeenCalled();
  });

  it('typing a term that finds something cancels the pending record', () => {
    const { registrar, registro } = novo();
    registro.observar('carrx', true);
    vi.advanceTimersByTime(1000);
    registro.observar('carro', false);
    vi.advanceTimersByTime(1500);
    expect(registrar).not.toHaveBeenCalled();
  });

  it('leaving the screen cancels the pending record', () => {
    const { registrar, registro } = novo();
    registro.observar('passagem', true);
    registro.cancelar();
    vi.advanceTimersByTime(1500);
    expect(registrar).not.toHaveBeenCalled();
  });
});
