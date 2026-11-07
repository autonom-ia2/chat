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
  it('quem busca vê só "Achar empresas" e "Suas buscas"; Configurações e "Para chamar" ficam fora', () => {
    expect(filhos(montar({ novaOn: true, podeBuscar: true }))).toEqual([
      'autonomia_prospecting_achar',
      'autonomia_prospecting_achar_buscas',
    ]);
  });

  it('quem só vê fica com "Suas buscas"', () => {
    expect(filhos(montar({ novaOn: true, podeBuscar: false }))).toEqual([
      'autonomia_prospecting_achar_buscas',
    ]);
  });

  it('sem a flag, o menu de hoje não muda', () => {
    expect(filhos(montar({ novaOn: false }))).toEqual([
      'autonomia_prospecting_search',
      'autonomia_prospecting_lists',
      'settings_prospecting_index',
    ]);
  });
});
