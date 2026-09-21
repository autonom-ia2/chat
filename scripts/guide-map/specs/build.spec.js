// @vitest-environment node
// O gerador roda no Node (usa Vite por dentro); o jsdom padrão da suíte quebra o
// esbuild que o Vite carrega.
import { lerPorques, prepararJanela } from '../build.mjs';

// O gerador lê o arquivo humano (porques.md). Estes testes cobrem o que dá errado
// escrevendo à mão — e o que não pode ser reformatado pelo caminho.
describe('leitura das explicações escritas à mão', () => {
  it('lê os campos de cada fluxo', () => {
    const fluxos = lerPorques(`### criar_funil
- titulo: Criar funil
- rota: crm_kanban_index
- gotchas: deletar etapa com cards falha
`);

    expect(fluxos.criar_funil).toEqual({
      titulo: 'Criar funil',
      rota: 'crm_kanban_index',
      gotchas: 'deletar etapa com cards falha',
    });
  });

  it('recusa blocos repetidos, em vez de perder um fluxo em silêncio', () => {
    const texto = `### criar_funil
- titulo: Criar funil

### criar_funil
- titulo: Colado sem renomear
`;

    expect(() => lerPorques(texto)).toThrow(/repetidos: criar_funil/);
  });

  it('não se confunde com um ### dentro do texto de um campo', () => {
    const fluxos = lerPorques(`### criar_funil
- titulo: Criar funil
- passos: 1. Abra o CRM; 2. Clique em Novo
`);

    expect(Object.keys(fluxos)).toEqual(['criar_funil']);
  });
});

// O CI roda Node 24, que já traz um `navigator` global SÓ DE LEITURA. O gerador
// passava em todo teste local (Node 20) e morria na primeira execução no CI.
// Este teste monta o `navigator` do jeito que o Node 24 monta — getter, sem
// setter —, então pega a regressão em qualquer versão do Node.
describe('o navegador de mentira do gerador', () => {
  const original = Object.getOwnPropertyDescriptor(globalThis, 'navigator');

  afterEach(() => {
    if (original) Object.defineProperty(globalThis, 'navigator', original);
    else delete globalThis.navigator;
  });

  it('substitui o navigator só de leitura que o Node 21+ já traz', () => {
    Object.defineProperty(globalThis, 'navigator', {
      get: () => ({ doNode: true }),
      configurable: true,
      enumerable: true,
    });

    expect(() => prepararJanela()).not.toThrow();
    expect(globalThis.navigator.doNode).toBeUndefined();
    expect(globalThis.navigator.userAgent).toContain('jsdom');
  });
});
