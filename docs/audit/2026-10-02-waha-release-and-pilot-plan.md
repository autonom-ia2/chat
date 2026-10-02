# WAHA 2026.9.2 — candidato, publicação e piloto

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/846.
Origem: PR #842, `62af5b0493dda09aba9c764e9e62f58197895f34`.
Estado final/evidências: [fechamento do candidato](2026-10-02-waha-final-candidate-readiness.md).

## Autorização e candidato

Rodrigo autorizou continuar a preparação até estar pronto para avaliar merge, deploy e backfill.
Isso inclui código, testes, revisão, commit/push e conferência somente leitura. Não inclui executar
merge/deploy/backfill real, escrever no banco produtivo, alterar sessões, logout, QR, pareamento ou auth.
A branch obrigatória de origem foi preservada; correções isoladas #850/#851/#852 fecham os três achados
reproduzidos do migrador. R1–R5/N1–N3 e as quarentenas permanecem intactos.

Candidato atualizado: `codex/waha-final-candidate-2026-10-02`, worktree
`/Users/rodrigosilva/.codex/worktrees/waha-final-candidate-2026-10-02/chat2you`, sobre main
`ffa7ce96920687f3d4d7d43124b78063006b407e`. Patch dos 30 caminhos da origem aplicado sem conflito;
conteúdo conferido arquivo a arquivo. Só o handoff copiado tem dois espaços finais removidos.
Nenhum merge, rebase, reset, force push ou alteração do checkout principal foi realizado.

O candidato anterior #848 fica como histórico: não contém as correções novas nem a base final.
A bateria antiga de 5566 exemplos Ruby/1354 JS não certifica este candidato.
A main atual contém a auditoria de encerramento #849 do Kanban #847: deploys concluídos nas duas stacks,
web/worker, imagens e assets publicados conferidos, limites de QA produtivo documentados. Sem outro
branch `release/` nos 32 PRs abertos consultados. Este candidato não abre um lote operacional antes de OK.

## Conferência atual somente leitura

Consultas em 2026-10-02, aproximadamente 17:37–17:43 UTC, sem alteração operacional:

- AWS: perfis já existentes `hub2you` (conta 354307071110) e `financial` (conta 140023375763).
  Nenhuma credencial/autenticação alterada. O erro antigo do perfil default não impede esse acesso válido.
- Ambas as imagens runtime SSM e os containers web/worker apontam para
  `ab84a219bdd30f287ed0011ed61d62ec43f1fab4`, o último deploy do Kanban. Serviços ativos,
  containers running e `.git_sha` web/worker iguais ao merge. HTTP local/público `/api`: 200.
- Hub2You: atual `i-07e5bc744c4ccda52` running/target healthy, anterior `i-04c8e3b417cbe2533` stopped.
- Autonom.ia: atual `i-018b5c54bf4f35421` running/target healthy, anterior `i-031d9fbcd7b197437` stopped.
  Target groups anteriores existem nas duas stacks.
- SSM somente leitura, resposta Success/0: Hub2You `b597fbc2-3eac-4ca7-b29a-de8289008b55`;
  Autonom.ia `bcc14b3a-3da4-4820-af85-c3905215177e`. Apenas is-active, inspect, cat do SHA e HTTP de saúde.
- WAHA de hubsegs e autonomia: GET `/api/version` confirma **2026.9.2**; processo usa
  `WAHA_APPS_ON=calls,chatwoot,mcp,brazilian-phone-numbers`. GET da rota cache/stats com nome sintético
  confirma módulo carregado (404 estruturado de App não habilitado nessa sessão inexistente).
  Não consultou mensagens, não criou App/sessão, não iniciou/parou sessão e não leu QR.
- GET agregado de sessões: Hub2You 34 (32 WORKING, 2 FAILED); Autonom.ia 11 (2 WORKING, 9 FAILED).
  Esses estados já existem antes da publicação WAHA. Não houve tentativa de reparo; o piloto precisa
  selecionar uma sessão WORKING. A contagem não comprova identidade nem elegibilidade de uma caixa.

Para o próximo deploy, a imagem de retorno esperada é `ab84a219bd`, a ativa hoje; os parâmetros de
anterior serão atualizados pelo workflow. A instância anterior atual ainda corresponde ao degrau anterior
`eda6f1f22f` e não deve ser confundida com o retorno após publicar WAHA.
Revalidar imagem, instâncias/targets, ausência de outro deploy e main imediatamente antes de autorização.

## Merge e deploy após aprovação

1. Fechar bateria/revisão do candidato e registrar SHA/árvore finais, sem claims de E2E real baseado em mocks.
2. Apresentar PR, escopo e SHA para aprovação explícita de Rodrigo de merge/deploy das duas stacks.
3. Com o OK, montar o lote exclusivo a partir dessa main, respeitando `docs/processo-de-release.md`.
   A árvore de produto deve coincidir com a validada. Se base/código mudarem, repetir a união da bateria.
   Integrar somente WAHA e abrir o PR de lote, sem publicação antecipada.
4. Realizar um único merge commit do lote na main, somente autorizado. Código dispara automaticamente
   os dois blue-green; não duplicar com workflow_dispatch de deploy.
5. Acompanhar os dois workflows até completed/success e conferir diretamente imagem/SHA de web e worker,
   serviços ativos, targets healthy e HTTP. Resultado de CI isolado não comprova publicação.
6. Todos os workers devem executar o código novo antes do piloto. Iniciar um ciclo novo após o deploy.
   Jobs antigos/ciclos sem marcador continuam legados; não há recálculo histórico.

## Definição e preparação do piloto

Instalação, ACCOUNT_ID e INBOX_ID ainda aguardam a escolha de Rodrigo. Não adivinhar IDs nem ampliar o
filtro para compensar `total=0`. O rake roda no container da aplicação que possui o banco daquela instalação.
Nenhum dry-run produtivo foi executado nesta preparação.

Antes da aplicação autorizada:

- Reservar janela sem escritores de Apps/configuração daquela sessão, incluindo manutenção, outras
  execuções do migrador e intervenções pelo painel/integrações. A janela inclui eventual recuperação R1.
  N1 detecta mudanças observadas antes do PUT; GET/PUT não são atômicos. Sem essa exclusão, não aplicar.
- Manter provider WAHA e lock da conversa estáveis até escoar os eventos/fechar aceites; o listener
  reavalia o escopo no consumo. Confirmar workers novos e começar nova reabertura após o deploy.
- Capturar snapshot local (lock/vínculo do resolver) e remoto (sessão/config/lista completa de Apps) em
  armazenamento privado operacional, com acesso restrito. Não colocar tokens, telefones, config completa
  ou conteúdo de cliente em Git/GitHub. Definir responsável por restauração antes de APPLY.

Dry-run explicitamente sem escrita, com IDs escolhidos e revisados da mesma instalação:

```bash
APPLY=false ACCOUNT_ID="$WAHA_PILOT_ACCOUNT_ID" INBOX_ID="$WAHA_PILOT_INBOX_ID" \
  bundle exec rails waha:backfill_existing_inboxes
```

Exigir `total=1`, `failed=0`, `skipped=0`, `recovery_failed=0`, `halted=false` e `would_update=1` para
caixa a migrar. `unchanged=1` é caixa já compatível; `total=0` não comprova migração. Revisar identidade
instalação/conta/Inbox/App, WORKING, módulo e ausência de resolver duplicado. Divergência de representação
entre GET individual/lista ou normalização legítima deve ser investigada sem relaxar checks automaticamente.

Apresentar o resultado concreto desse dry-run para autorização separada do piloto. Somente depois:

```bash
APPLY=true ACCOUNT_ID="$WAHA_PILOT_ACCOUNT_ID" INBOX_ID="$WAHA_PILOT_INBOX_ID" \
  bundle exec rails waha:backfill_existing_inboxes
```

Qualquer SKIP, FAILED, RECOVERED, CRITICAL ou `halted=true` encerra piloto/lote. Não repetir cegamente,
escolher um resolver duplicado, mesclar configuração nem recriar Inbox/sessão como fallback.

## Aceites antes de expandir

1. Resultado exato: total=1, updated=1, failed/skipped/recovered/recovery_failed=0, halted=false.
2. WORKING também na confirmação final, sem logout/novo QR/perda de autenticação. Preservar Apps não
   relacionados/configurações. Exatamente um resolver habilitado e vínculo local igual ao remoto.
3. Dry-run dos mesmos IDs retorna total=1, unchanged=1, would_update=0, sem erro.
4. Com contatos de teste autorizados: saída pelo celular aparece normal, sem eco/reenvio/duplicação;
   mensagem pela plataforma chega ao contato correto e entregue/lido sincronizam quando disponíveis.
5. Resolver, receber nova mensagem do mesmo contato e confirmar reabertura da mesma conversa; resolver
   de novo e conferir duração do novo ciclo, inclusive consumo atrasado, sem somar ciclo anterior.
6. Variações brasileiras de número 8/9 dígitos convergem para o mesmo chat controlado.
7. Reconexão observada sem forçar logout/QR/pareamento; grupos fora do escopo WhatsApp API padrão.
8. Registrar horário/SHA/IDs internos e resultados sem conteúdo de mensagens; aceitação incompleta
   não libera expansão. Próximo conjunto pequeno de caixas precisa de decisão operacional própria.

## Rollback separado para aplicação e dados do backfill

Aplicação: somente com aprovação operacional, `workflow_dispatch` na main, `action=rollback`,
`confirm_production=true` em deploy-hub2you-blue-green.yml e/ou deploy-autonomia-blue-green.yml,
conforme ambiente afetado. Reconfirmar instância/imagem anterior, web/worker, targets e saúde depois.
Há apenas um degrau de rollback; outro deploy pode consumir a janela. Sem migration de schema no candidato.
Voltar a imagem não reverte atributos locais nem configuração WAHA modificados pelo backfill.

Falha durante PUT: R1 restaura o snapshot e confirma WORKING/config/Apps. RECOVERED ainda exige parada.
CRITICAL/recovery_failed é incidente: preservar evidência privada e aprovar uma ação concreta; não usar logout.

Desfazer piloto bem-sucedido: procedimento separado e aprovado. Comparar estado atual com o pós-piloto;
se houve intervenção posterior, parar e preparar restauração específica. Não aplicar PUT cego do backup
antigo, apagar Apps novos ou sobrescrever configuração nova. Confirmar restauração remota antes de escrever
atributos locais. Não existe comando automático de rollback de migração aprovado neste candidato.
