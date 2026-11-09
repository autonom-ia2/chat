import { prospectingSidebarItems } from '../../utils/prospectingSidebar';

const montar = opcoes =>
  prospectingSidebarItems({
    isVisible: true,
    t: chave => chave,
    accountScopedRoute: name => ({ name }),
    ...opcoes,
  });

const filhos = itens => itens[0].children.map(filho => filho.to.name);

describe('menu Prospecção com a flag prospeccao_nova', () => {
  it('quem busca vê "Achar empresas", "Suas buscas" e "Para chamar" (#2697); Listas (#2775) e Configurações ficam fora', () => {
    expect(filhos(montar({ novaOn: true, podeBuscar: true }))).toEqual([
      'autonomia_prospecting_achar',
      'autonomia_prospecting_achar_buscas',
      'autonomia_prospecting_para_chamar',
    ]);
  });

  it('quem só vê fica com "Suas buscas" e "Para chamar"', () => {
    expect(filhos(montar({ novaOn: true, podeBuscar: false }))).toEqual([
      'autonomia_prospecting_achar_buscas',
      'autonomia_prospecting_para_chamar',
    ]);
  });

  it('a aba "Suas listas" e a lista aberta marcam "Suas buscas" (#2775)', () => {
    const [, buscas] = montar({ novaOn: true, podeBuscar: true })[0].children;

    expect(buscas.activeOn).toEqual(
      expect.arrayContaining([
        'autonomia_prospecting_achar_listas',
        'autonomia_prospecting_achar_lista',
      ])
    );
  });

  it('sem a flag, o menu de hoje não muda', () => {
    expect(filhos(montar({ novaOn: false }))).toEqual([
      'autonomia_prospecting_search',
      'autonomia_prospecting_lists',
      'settings_prospecting_index',
    ]);
  });

  it('a lista logo depois de buscar marca "Achar empresas"; aberta pelas buscas, marca "Buscas"', () => {
    const [achar, buscas] = montar({ novaOn: true, podeBuscar: true })[0]
      .children;

    expect(achar.activeOn).toContain('autonomia_prospecting_achar_nova');
    expect(buscas.activeOn).toContain('autonomia_prospecting_achar_busca');
    expect(buscas.activeOn).not.toContain('autonomia_prospecting_achar_nova');
  });
});
