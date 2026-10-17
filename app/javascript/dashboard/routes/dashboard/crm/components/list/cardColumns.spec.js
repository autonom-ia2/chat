import { buildCrmCardColumns } from './cardColumns';

// #1498 — funil de Atender não tem a coluna Valor.
const t = chave => chave;
const ids = opcoes => buildCrmCardColumns({ t, ...opcoes }).map(c => c.id);

describe('buildCrmCardColumns', () => {
  it('keeps the value column by default', () => {
    expect(ids()).toContain('value');
  });

  it('drops the value column when the pipeline has no value', () => {
    const semValor = ids({ includeValue: false });
    expect(semValor).not.toContain('value');
    expect(semValor.length).toBe(ids().length - 1);
  });
});
