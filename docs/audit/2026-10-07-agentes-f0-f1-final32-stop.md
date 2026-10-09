# F0/F1 — STOP da única passagem final32

## Resultado e limite

**PARADO.** Rodrigo definiu uma revisão normal, correção, confirmação limitada, causa raiz e uma passagem final. A final32 encontrou erro concreto no estado vazio da primeira tela. Não corrigir nem iniciar outro ciclo sem nova orientação. Nenhum produto foi editado depois da falha; somente recibos e handoff foram atualizados. F2 não começou e nenhuma tela real foi aceita.

Snapshot `20261007-214937-532a5b7b-fe3bcb720e-3b740e77`, SHA-256 `fe3bcb720ead758c83aaafacb3b262a24277363fde5ea3af028261ee8bda79f1`, HEAD documental `532a5b7beb56902d2a0168013a3e8b657ba31488`. 14.858 arquivos/343.528.172 bytes. Duas réplicas verificadas antes/depois. Branch/worktree solicitadas preservadas.

## Provas que passaram

- Vitest job `m2-e96f647731d048a09a4bda1e14b9f8f8`: 38 arquivos, **224 testes passaram**, zero falhas/pendentes, exit 0. Relatório `/tmp/chat2you-agentes-f0-f1-final32.json`, SHA-256 `9e12233af5d4a60a3ba03cfae3e0a9c039e19908bc82e1c936ea91a219b546aa`. Saída lida: sem Unhandled; avisos Vue de mocks/registro de plugin, sourcemap ausente e Browserslist não foram ocultados.
- Revisão final produto/D9: os dois resíduos de integração foram fechados estaticamente (`revisoes/F0-F1-final-produto.md`); suíte confirma os casos. Isso não aprova o conjunto F1.
- Navegador real, desktop **1440×1080 claro**, lista com agentes: título/cartões/resumo, alvos verificados de 44 px, overflow horizontal e Axe sem violações serious/critical passaram. Somente esse cenário passou.

## Falha final e causa raiz

Playwright job `m2-9fa254c66a264561be46c7861b3835d3`: um cenário passou, **um falhou no estado vazio**, 26 não executaram por max-failures=1. Saída também informa um erro não associado a teste; não alegar matriz verde nem execução sem erro externo. Sem execução dos cenários de celular/escuro/viewer/diálogos/mutações nessa final.

Achado `F1-FINAL-01`: o H1 do hero vazio fica escuro (`#1c2024`) no azul-marinho (`#0d2344`), contraste **1,04:1**, abaixo dos 3:1 exigidos para seu tamanho. Axe `color-contrast` serious; captura confirma texto ilegível.

**Causa no código:** `assets/scss/_base.scss:5-11` aplica `text-n-slate-12` diretamente a todos os headings. `AgentsEmptyHero.vue` dá `text-white` apenas ao ancestral section, e seu H1 não tem cor explícita; a regra direta do heading prevalece sobre a herança. O mockup não usa esse stylesheet. As specs verificam texto/ações, não estilo computado. As duas execuções anteriores de navegador pararam na lista por outras falhas, antes de chegar ao vazio. O parecer estático do hero não conferiu a regra global do produto.

**Correção necessária, não aplicada após STOP:** classe Tailwind `text-white` diretamente no H1 do hero. Não mudar o stylesheet global. Antes de retomar, tratar a prioridade de captura dos estados de forma que falha na primeira tela não deixe o estado vazio fora da evidência; manter Axe e asserções completas. Qualquer retomada precisa ser explicitamente decidida por Rodrigo, sem simular uma rodada adicional como preflight.

## Capturas e cobertura

Imagens reais com contas/usuários/dados sintéticos, copiadas byte a byte do M2 e lidas pelo coordenador; nenhuma imagem editada ou mockup apresentado como produto:

- `.codex/preview/agents/screenshots/final32/lista-real-chromium-1440-light.png`: 167.791 bytes, SHA-256 `90309dd1d75687d6a1c801a0368ffac2d8c8a4a345c60f7ed277b2a7ebc4f206`.
- `.codex/preview/agents/screenshots/final32/vazio-falha-1440-light.png`: 137.181 bytes, SHA-256 `df259c2e0b3397b1688c4c2d43015e5d7aedf2c49f0b575f95cd13e73d3a2ef6`.
- `lista-real-lower` tem os mesmos bytes da primeira captura: o alvo “Sem canal” já estava visível. Não é prova dos cartões abaixo da dobra e não deve ser apresentado como captura adicional.

Nenhum novo lint/build/check amplo foi iniciado após a falha final. Lint31 anterior: uma infração corrigida no import, 847 avisos; não afirmar lint32 aprovado. Formatos28/Guia30 e Ruby26 são históricos, não prova combinada final do lote. CI do código local não existe ainda.

Runner encerrou somente seus quatro serviços; conferência read-only posterior não encontrou listeners 59720–59723. Bancos e fixtures locais preservados; nenhuma produção acessada. Sem commit/push/PR de implementação, merge, fila, deploy, migração nova ou produção.

Issue F1 #1130 atualizada com este resultado, sem alegação de aceite/CI:
https://github.com/autonom-ia2/chat/issues/1130#issuecomment-6049914665.
Project NextAction continua sem atualização verificável após os erros remotos
anteriores; não repetida a mutação que já falhou. PR documental #1115 congelado.
