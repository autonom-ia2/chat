// @vitest-environment node
// A trava da Central de Ajuda "Plataforma" no Pull Request (#614, etapa B). Reaproveita
// decidir/motivoDaDispensa de scripts/guide-map/trava.mjs (mesmo mecanismo do rótulo de
// dispensa), com o rótulo e a marca do motivo próprios da Central.
import {
  ROTULO_DISPENSA,
  MARCA_DO_COMENTARIO,
  decidir,
  novasSemArtigo,
  valoresI18n,
  valoresRemovidosDoI18n,
  valoresCitadosEmArtigos,
  comentarioDaTrava,
} from '../trava.mjs';

describe('decidir — reaproveita a decisão do Guia com o rótulo da Central', () => {
  it('libera quando não há tela nova sem artigo', () => {
    expect(decidir({ novas: [], rotulos: [], corpo: '' })).toEqual({
      bloqueia: false,
      situacao: 'em_dia',
    });
  });

  it('barra tela nova sem artigo', () => {
    expect(
      decidir({ novas: ['crm_relatorios'], rotulos: [], corpo: '' })
    ).toEqual({ bloqueia: true, situacao: 'sem_explicacao' });
  });

  it('dispensa com o rótulo da Central e o motivo no corpo', () => {
    expect(
      decidir({
        novas: ['tela_interna'],
        rotulos: [ROTULO_DISPENSA],
        corpo: 'Central não se aplica: redirecionamento puro',
      })
    ).toEqual({
      bloqueia: false,
      situacao: 'dispensada',
      motivo: 'redirecionamento puro',
    });
  });

  // O rótulo do Guia não dispensa a Central — são trilhas independentes.
  it('não dispensa com o rótulo do Guia', () => {
    expect(
      decidir({
        novas: ['tela_interna'],
        rotulos: ['guia-nao-se-aplica'],
        corpo: 'Guia não se aplica: motivo',
      }).bloqueia
    ).toBe(true);
  });
});

describe('novasSemArtigo — telas que entraram neste PR e ainda não têm artigo', () => {
  it('tela nova e sem cobertura aparece', () => {
    const resultado = novasSemArtigo({
      antes: ['inbox_list'],
      atual: new Set(['inbox_list', 'crm_relatorios']),
      cobertas: new Set(['inbox_list']),
    });

    expect(resultado).toEqual(['crm_relatorios']);
  });

  it('tela nova mas já coberta por um artigo não aparece', () => {
    const resultado = novasSemArtigo({
      antes: ['inbox_list'],
      atual: new Set(['inbox_list', 'crm_relatorios']),
      cobertas: new Set(['inbox_list', 'crm_relatorios']),
    });

    expect(resultado).toEqual([]);
  });

  it('tela antiga sem artigo não conta como nova', () => {
    const resultado = novasSemArtigo({
      antes: ['inbox_list', 'tela_antiga'],
      atual: new Set(['inbox_list', 'tela_antiga']),
      cobertas: new Set(['inbox_list']),
    });

    expect(resultado).toEqual([]);
  });
});

describe('valoresI18n — achata os valores-folha de um JSON de tradução', () => {
  it('pega string aninhada em objeto', () => {
    expect(valoresI18n({ A: { B: 'Texto do botão' } })).toEqual([
      'Texto do botão',
    ]);
  });

  it('ignora número e booleano, só string conta como texto de tela', () => {
    expect(valoresI18n({ A: 1, B: true, C: 'Texto' })).toEqual(['Texto']);
  });
});

describe('valoresRemovidosDoI18n — o que existia antes e não existe em lugar nenhum agora', () => {
  it('valor que sumiu de todos os arquivos aparece', () => {
    const antes = [{ A: 'Texto antigo' }, { B: 'Outro' }];
    const depois = [{ A: 'Texto novo' }, { B: 'Outro' }];

    expect(valoresRemovidosDoI18n(antes, depois)).toEqual(['Texto antigo']);
  });

  // Mudou de arquivo, mas continua existindo em algum lugar do i18n: não é "removido".
  it('valor que só mudou de arquivo não aparece', () => {
    const antes = [{ A: 'Texto' }, { B: 'Outro' }];
    const depois = [{ A: 'Outro' }, { B: 'Texto' }];

    expect(valoresRemovidosDoI18n(antes, depois)).toEqual([]);
  });
});

describe('valoresCitadosEmArtigos — só interessa o valor removido que algum artigo cita', () => {
  it('acha o valor em negrito no corpo do artigo, com includes', () => {
    const artigos = [
      { arquivo: '02.04-a.md', corpo: 'Clique em **Salvar alterações**.' },
      { arquivo: '02.05-b.md', corpo: 'Nada aqui.' },
    ];

    expect(
      valoresCitadosEmArtigos(['Salvar alterações', 'Sem uso'], artigos)
    ).toEqual([{ valor: 'Salvar alterações', artigos: ['02.04-a.md'] }]);
  });

  it('valor removido que nenhum artigo cita não aparece', () => {
    const artigos = [{ arquivo: '02.04-a.md', corpo: 'Nada relacionado.' }];

    expect(valoresCitadosEmArtigos(['Texto qualquer'], artigos)).toEqual([]);
  });
});

describe('comentarioDaTrava — o comentário no PR', () => {
  it('sempre leva a marca que o workflow procura', () => {
    const comentario = comentarioDaTrava({
      estrutura: [],
      decisao: { situacao: 'em_dia', bloqueia: false },
      novas: [],
      paraRevisao: [],
      i18nCitado: [],
    });

    expect(comentario.startsWith(MARCA_DO_COMENTARIO)).toBe(true);
    expect(comentario).toContain('Central em dia');
  });

  it('estrutura quebrada aparece sempre, sem menção a dispensa', () => {
    const comentario = comentarioDaTrava({
      estrutura: ['Artigo no disco sem entrada no mapa:', '  - 09.99-orfao.md'],
      decisao: { situacao: 'em_dia', bloqueia: false },
      novas: [],
      paraRevisao: [],
      i18nCitado: [],
    });

    expect(comentario).toContain('estrutura quebrada');
    expect(comentario).toContain('09.99-orfao.md');
  });

  it('lista as telas novas sem artigo e as duas saídas', () => {
    const comentario = comentarioDaTrava({
      estrutura: [],
      decisao: { situacao: 'sem_explicacao', bloqueia: true },
      novas: ['crm_relatorios'],
      paraRevisao: [],
      i18nCitado: [],
    });

    expect(comentario).toContain('crm_relatorios');
    expect(comentario).toContain(ROTULO_DISPENSA);
    expect(comentario).toContain('Central não se aplica: <motivo>');
  });

  it('pede o motivo quando o rótulo veio sem ele', () => {
    const comentario = comentarioDaTrava({
      estrutura: [],
      decisao: { situacao: 'dispensa_sem_motivo', bloqueia: true },
      novas: ['crm_relatorios'],
      paraRevisao: [],
      i18nCitado: [],
    });

    expect(comentario).toContain('falta o motivo');
  });

  // Evidência para revisão e i18n mudado NUNCA bloqueiam — só aparecem como aviso.
  it('mostra evidências para revisão e i18n mudado, sem bloquear', () => {
    const comentario = comentarioDaTrava({
      estrutura: [],
      decisao: { situacao: 'em_dia', bloqueia: false },
      novas: [],
      paraRevisao: [
        { artigo: '02.06-a.md', caminho: 'app/models/user.rb', numero: 12 },
      ],
      i18nCitado: [{ valor: 'Salvar alterações', artigos: ['02.04-a.md'] }],
    });

    expect(comentario).toContain('02.06-a.md');
    expect(comentario).toContain('app/models/user.rb:12');
    expect(comentario).toContain('Salvar alterações');
    expect(comentario).toContain('02.04-a.md');
    expect(comentario).toContain('não bloqueia');
  });
});
