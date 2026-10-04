// @vitest-environment node
// O gerador roda no Node (usa Vite por dentro); o jsdom padrão da suíte quebra o
// esbuild que o Vite carrega.
import fs from 'fs';
import os from 'os';
import path from 'path';
import { lerPorques, prepararJanela, telasSemContexto } from '../build.mjs';

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
  // `prepararJanela` troca os QUATRO globais; devolver só o `navigator` deixaria
  // um jsdom velho em `window`, `document` e `location` para o próximo teste
  // deste arquivo (achado da revisão da #581).
  const GLOBAIS = ['window', 'document', 'navigator', 'location'];
  const originais = Object.fromEntries(
    GLOBAIS.map(nome => [
      nome,
      Object.getOwnPropertyDescriptor(globalThis, nome),
    ])
  );

  afterEach(() => {
    GLOBAIS.forEach(nome => {
      if (originais[nome]) {
        Object.defineProperty(globalThis, nome, originais[nome]);
      } else {
        delete globalThis[nome];
      }
    });
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

// #934 — o lembrete do build: tela com seleção em lote que não declara contexto.
describe('telas com seleção sem contexto para o Guia', () => {
  it('avisa só a tela que importa uma barra de lote e não declara', () => {
    const pasta = fs.mkdtempSync(path.join(os.tmpdir(), 'guia-contexto-'));
    const escrever = (nome, texto) =>
      fs.writeFileSync(path.join(pasta, nome), texto);
    escrever(
      'Esquecida.vue',
      "import BulkSelectBar from './BulkSelectBar.vue';\n"
    );
    escrever(
      'Declarada.vue',
      "import CrmBulkActionBar from './CrmBulkActionBar.vue';\ndeclararContexto({});\n"
    );
    escrever(
      'CrmBulkActionBar.vue',
      "import BulkActions from './BulkActions.vue';\n"
    );
    escrever('SemLote.vue', "import Button from './Button.vue';\n");

    expect(telasSemContexto(pasta)).toEqual(['Esquecida.vue']);
    fs.rmSync(pasta, { recursive: true });
  });
});
