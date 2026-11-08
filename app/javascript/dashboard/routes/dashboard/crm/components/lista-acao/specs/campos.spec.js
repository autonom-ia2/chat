import {
  CAMPOS,
  alternarCampo,
  camposDaLista,
  camposPadrao,
  camposVisiveis,
  guardarPreferencias,
  lerPreferencias,
  moverCampo,
  normalizarCampos,
} from '../campos';

describe('Escolher o que aparece (#2379)', () => {
  it('começa com situação, etapa, quem cuida e valor', () => {
    expect(camposVisiveis(camposPadrao())).toEqual([
      'situacao',
      'etapa',
      'quem_cuida',
      'valor',
    ]);
    expect(camposPadrao().map(campo => campo.chave)).toEqual(CAMPOS);
  });

  it('liga, desliga, sobe e desce sem mexer na lista de antes', () => {
    const antes = camposPadrao();
    const sem = alternarCampo(antes, 'valor');
    expect(camposVisiveis(sem)).not.toContain('valor');
    expect(camposVisiveis(antes)).toContain('valor');

    const subiu = moverCampo(antes, 'valor', -1);
    expect(subiu.map(campo => campo.chave).slice(0, 4)).toEqual([
      'situacao',
      'etapa',
      'valor',
      'quem_cuida',
    ]);
    expect(moverCampo(antes, 'situacao', -1)).toBe(antes);
    expect(moverCampo(antes, 'prioridade', 1)).toBe(antes);
  });

  it('descarta o desconhecido e repetido, e põe no fim, escondido, o que faltar', () => {
    const lista = normalizarCampos([
      { chave: 'valor', visivel: true },
      { chave: 'valor', visivel: false },
      { chave: 'inventado', visivel: true },
    ]);
    expect(lista[0]).toEqual({ chave: 'valor', visivel: true });
    expect(lista).toHaveLength(CAMPOS.length);
    expect(camposVisiveis(lista)).toEqual(['valor']);
    expect(normalizarCampos(null)).toEqual(camposPadrao());
  });

  it('guarda no navegador por funil e aguenta navegador sem armazenamento', () => {
    guardarPreferencias(5, { organizar: 'etapa', campos: camposPadrao() });
    expect(lerPreferencias(5).organizar).toBe('etapa');
    expect(lerPreferencias(6)).toEqual({
      organizar: undefined,
      campos: undefined,
    });
    const espiao = vi
      .spyOn(Storage.prototype, 'getItem')
      .mockImplementation(() => {
        throw new Error('bloqueado');
      });
    expect(lerPreferencias(5)).toEqual({});
    espiao.mockRestore();
  });

  it('abre as colunas de uma visualização salva antiga como campos', () => {
    const campos = camposDaLista({
      columns: {
        columnOrder: ['select', 'title', 'priority', 'stage', 'value', 'meta'],
        columnVisibility: { priority: true, stage: true, value: false },
      },
    });
    expect(camposVisiveis(campos)).toEqual(['situacao', 'prioridade', 'etapa']);
    expect(camposDaLista({ filters: {} })).toBeNull();
    expect(
      camposVisiveis(
        camposDaLista({
          columns: {},
          lista_acao: { campos: [{ chave: 'novidade', visivel: true }] },
        })
      )
    ).toEqual(['novidade']);
  });
});
