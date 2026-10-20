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

  // #1874 — sem nenhuma ação em massa possível, a lista não tem seleção.
  it('drops the select column when nothing can be done in bulk', () => {
    const semSelecao = ids({ includeSelect: false });
    expect(ids()[0]).toBe('select');
    expect(semSelecao).not.toContain('select');
    expect(semSelecao.length).toBe(ids().length - 1);
  });
});
