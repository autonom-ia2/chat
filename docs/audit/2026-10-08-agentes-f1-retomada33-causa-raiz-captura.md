# F1 — retomada33: causa raiz da captura branca de mutações

**Data:** 2026-10-08
**Escopo:** somente a captura `mutacoes-reais` do harness Playwright da primeira tela F1. Não é uma revisão do produto, não reabre a rodada e não altera o critério Axe.
**Execução informada pelo coordenador:** 8 cenários passaram, 17 falharam, 3 foram ignorados, exit 1. O cenário de mutação foi contabilizado como PASS, mas o artefato visual abaixo não é aceitável.

## Evidência

O arquivo `.codex/preview/agents/screenshots/retomada33/screenshots/mutacoes-reais-chromium-1440-light.png` tem 1440×1080 pixels, modo RGB, e foi inspecionado: todos os pixels são brancos. A captura não mostra lista, shell, loading, mensagem de erro ou qualquer estado do produto.

O problema está no trecho final de `tests/playwright/tests/agents/visual.spec.ts:471-494`:

1. o teste espera a resposta do DELETE e confirma o payload da lista sem o rascunho (`:471-486`);
2. chama `page.reload()` (`:487`), mas não espera o GET da lista disparado por essa nova montagem;
3. usa `toHaveCount(0)` para o rascunho (`:488`). Esse valor já é verdadeiro enquanto o DOM ainda está vazio, carregando ou antes de a lista ser montada;
4. executa overflow, captura e só depois Axe (`:489-494`).

As duas recargas anteriores usam uma condição positiva (`data-state=E6` e `data-state=E5`, `:384-387` e `:439-442`) e, por isso, aguardam a lista renderizada. A recarga final só espera a ausência de um seletor. O helper `gotoAgentsList` (`tests/playwright/fixtures/agents.ts:274-285`) também mostra o contrato necessário: registrar `waitForResponse` para o GET account-scoped, navegar e verificar resposta HTTP.

## Causa raiz

O harness confundiu uma pós-condição negativa — “o rascunho não está no DOM” — com prontidão da tela. `page.reload()` aguarda a navegação do documento, mas a aplicação ainda carrega a conta/lista de forma assíncrona. Como a ausência do seletor é satisfeita antes da hidratação, o screenshot roda em um documento sem conteúdo visível. `expectNoHorizontalOverflow` pode passar com esse corpo vazio, e `expectNoSeriousA11y` (`tests/playwright/helpers/expectNoSeriousA11y.ts:4-12`) apenas filtra violações Axe; ele não comprova que a tela real foi montada.

Essa é uma lacuna de sincronização do teste. A imagem branca não prova crash, erro de rota ou regressão do produto; o produto não foi diagnosticado como causa nesta análise.

## O que o PASS realmente prova

O cenário provou, até o ponto da captura:

- o PATCH de pausa enviou `status: paused` e `enabled: false` e retornou E6;
- a conversa foi devolvida sem responsável;
- o PATCH de religação enviou `status: active` e `enabled: true` e retornou E5;
- o DELETE respondeu 204 e o payload da resposta da lista não continha o rascunho.

Ele não provou que a última recarga terminou, que a lista pós-delete foi renderizada, que o rascunho continuava ausente no DOM hidratado ou que a captura representa uma tela real. Portanto, o screenshot não pode ser usado como evidência visual nem como aceite, mesmo com o teste marcado como PASS.

## Correção mínima futura

No próximo bloco autorizado do harness, registrar o `waitForResponse` do GET `agentsListPath(account.id)` antes de `page.reload()`, aguardar a resposta OK e uma condição positiva da tela — por exemplo, o heading/lista reais visíveis e o estado de loading encerrado — e somente então repetir `toHaveCount(0)`, overflow, screenshot e Axe. A ordem deve continuar permitindo capturar a tela antes de Axe, sem remover nenhuma asserção de API ou pós-condição.

Nenhum arquivo de harness ou produto foi alterado nesta análise. Não executei navegador, testes, banco ou serviço.

## Correção aplicada no harness (retomada autorizada)

Em 2026-10-08, após autorização explícita para corrigir somente o harness, o bloco final de mutação em `tests/playwright/tests/agents/visual.spec.ts` passou a registrar o `waitForResponse` do GET account-scoped antes de `page.reload()`. Depois da recarga, o teste verifica resposta HTTP OK, confirma novamente no payload que o rascunho não existe, espera o heading `Seus agentes`, a lista, o estado ativo de Clara e o encerramento de `aria-busy`. Só então executa a ausência do rascunho no DOM, overflow, screenshot e Axe.

A correção não adiciona espera temporal, retry, mock ou chamada de API fora do fluxo real. Neste turno foram feitos apenas Prettier e `git diff --check`; navegador, testes, banco e serviços continuam sem execução.

## Correção complementar dos diálogos

Na mesma retomada, o cenário existente de menu/confirmações passou a executar `expectNoSeriousA11y(page)` enquanto cada diálogo está aberto, imediatamente depois da captura e antes do cancelamento. Assim, as capturas `dialog-excluir-cancelar` e `dialog-pausar-interno-cancelar` têm uma verificação de acessibilidade do estado que mostram; a checagem final da página continua preservada após os diálogos fecharem.
