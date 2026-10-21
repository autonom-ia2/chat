import {
  dividirIgualmente,
  doServidor,
  invalido,
  numero,
  paraOServidor,
  repetirAnterior,
  somaDiferente,
  temErro,
} from './metasDaGaveta';

// Regras da gaveta "Metas do mês" (#1991): campos em texto, vazio = sem meta,
// atalhos que só preenchem e o aviso de soma diferente da meta do funil.
const funil = (metaFunil, pessoas) => ({ id: 1, metaFunil, pessoas });
const p = (id, meta, extra = {}) => ({ id, nome: `P${id}`, meta, ...extra });

describe('metasDaGaveta', () => {
  it('aceita só inteiros de 0 em diante; vazio é sem meta', () => {
    expect(numero('')).toBeNull();
    expect(numero('8000')).toBe(8000);
    expect(numero('0')).toBe(0);
    ['1.5', '-1', 'abc', '8.000'].forEach(texto =>
      expect(invalido(texto)).toBe(true)
    );
  });

  it('vai e volta do servidor: null vira campo vazio e campo vazio vira null', () => {
    const campos = doServidor([
      {
        id: 1,
        metaFunil: 20000,
        pessoas: [
          { id: 2, meta: 8000 },
          { id: 3, meta: null },
        ],
      },
    ]);
    expect(campos[0]).toMatchObject({
      metaFunil: '20000',
      pessoas: [
        { id: 2, meta: '8000' },
        { id: 3, meta: '' },
      ],
    });
    // A meta do funil só volta se mudar (a do painel pode ter centavos).
    expect(paraOServidor(campos)).toEqual([
      {
        id: 1,
        pessoas: [
          { id: 2, meta: 8000 },
          { id: 3, meta: null },
        ],
      },
    ]);
    const semMetaDoFunil = [{ ...campos[0], metaFunil: '' }];
    expect(paraOServidor(semMetaDoFunil)[0].metaFunil).toBeNull();
  });

  it('"Repetir" copia a meta do mês anterior; quem não tinha fica como está', () => {
    const novo = repetirAnterior(
      funil('', [p(1, '', { anterior: 6000 }), p(2, '9', { anterior: null })])
    );
    expect(novo.pessoas.map(x => x.meta)).toEqual(['6000', '9']);
  });

  it('"Dividir igualmente" reparte de 100 em 100 e a sobra vai para a primeira', () => {
    const novo = dividirIgualmente(
      funil('20000', [p(1, ''), p(2, ''), p(3, '')])
    );
    expect(novo.pessoas.map(x => x.meta)).toEqual(['6800', '6600', '6600']);
    expect(dividirIgualmente(funil('100', []))).toEqual(funil('100', []));
    // Parte menor que 100: divide de 1 em 1. Sem meta do funil: nada muda.
    expect(
      dividirIgualmente(
        funil('50', [p(1, ''), p(2, ''), p(3, '')])
      ).pessoas.map(x => x.meta)
    ).toEqual(['18', '16', '16']);
    const semMeta = funil('', [p(1, '5')]);
    expect(dividirIgualmente(semMeta)).toBe(semMeta);
  });

  it('avisa quando a soma das pessoas é diferente da meta do funil', () => {
    expect(somaDiferente(funil('20000', [p(1, '8000'), p(2, '6000')]))).toEqual(
      { soma: 14000, meta: 20000 }
    );
    expect(
      somaDiferente(funil('14000', [p(1, '8000'), p(2, '6000')]))
    ).toBeNull();
    expect(somaDiferente(funil('', [p(1, '8000')]))).toBeNull();
  });

  it('um campo inválido em qualquer funil trava o salvar', () => {
    expect(temErro([funil('10', [p(1, '5')])])).toBe(false);
    expect(temErro([funil('10', [p(1, '5')]), funil('x', [])])).toBe(true);
  });
});
