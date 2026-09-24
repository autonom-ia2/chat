// Trava do tamanho dos arquivos da Prospecção (#677). Arquivo grande junta
// frentes diferentes e faz agentes em paralelo conflitarem em série; acima do
// teto, o arquivo tem de ser dividido por assunto antes de crescer.
const MAX_LINES = 600;

// Legado fora do escopo da quebra da tela de busca; tem issue própria.
const LEGACY_FILES = ['../pages/ProspectingListsPage.vue'];

const sources = import.meta.glob('../**/*.{js,vue}', {
  query: '?raw',
  import: 'default',
  eager: true,
});

describe('Prospecção · tamanho dos arquivos', () => {
  it(`nenhum arquivo passa de ${MAX_LINES} linhas`, () => {
    const oversized = Object.entries(sources)
      .filter(([path]) => !LEGACY_FILES.includes(path))
      .map(([path, source]) => [path, source.split('\n').length])
      .filter(([, lines]) => lines > MAX_LINES);

    expect(Object.keys(sources).length).toBeGreaterThan(40);
    expect(oversized).toEqual([]);
  });
});
