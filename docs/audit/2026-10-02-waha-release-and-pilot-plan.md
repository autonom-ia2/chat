# WAHA 2026.9.2 — candidato, deploy e piloto

Data: 2026-10-02
Issue: https://github.com/autonom-ia2/chat/issues/846
PR de origem: https://github.com/autonom-ia2/chat/pull/842
Status: **BLOQUEADO — dois P1 novos na revisão do migrador**

## Limite desta etapa

Preparação e revisão somente. Nenhum merge, deploy, backfill real, escrita em banco de produção,
alteração de sessão WAHA, logout ou pareamento foi autorizado nesta etapa. As autorizações de N1, N2 e N3
cobriram implementação, testes, commit e push. A aprovação do candidato não autoriza por si só aplicar o piloto.

Fonte de verdade histórica: [handoff](2026-10-02-waha-2026-9-2-post-review-handoff.md).
Procedimento do migrador: [backfill](../waha_2026_9_2_existing_inboxes.md).
Achados e decisão: [revisão independente](2026-10-02-waha-independent-release-review.md).

## Candidato isolado

- Branch de origem preservada: `feat/waha-2026-9-2-chatwoot-sync`.
- HEAD de origem: `ff0f05293271c3d9c2d9fa25ef228188ace86b2d`.
- Base conferida: `43901a40c2eb6ef43cf3e5052c297879e0abdbd4` (`main`).
- Branch de preparação: `codex/waha-release-candidate-2026-10-02`.
- Worktree separado: `/Users/rodrigosilva/.codex/worktrees/waha-release-2026-10-02/chat2you`.
- O patch completo do WAHA foi aplicado sem conflito sobre a base. Antes de acrescentar este plano,
  `git write-tree` coincidiu com a árvore da origem: `1b8622a2dba1e1c0f70ab0637bb285fb86b13e26`.
- Uma única correção de formatação no candidato remove dois espaços finais da linha `Data` do handoff,
  detectados por `git diff --check`. Nenhuma alteração funcional adicional; a origem permanece intacta.
- Nenhuma migration, alteração de UI, dependência versionada ou workflow faz parte deste candidato.

Há outro lote aberto, `release/2026-10-02-lote3`, com o zoom do Kanban (PR de lote #847;
PR #840 já integrado nesse lote). Ele foi preservado. Este candidato não abre um segundo lote operacional
e não será integrado ao lote do Kanban. A política permite um lote aberto por vez e exige validação do
anterior antes do próximo. Após o fechamento e a aceitação do lote anterior, conferir a nova `main`, montar
o lote exclusivo do WAHA e repetir a união dos testes sobre sua árvore final. Os resultados deste candidato
não certificam uma base que tenha mudado posteriormente.

## Conferência operacional somente leitura

Em 2026-10-02, os últimos deploys bem-sucedidos consultados no GitHub apontaram
`eda6f1f22fd5e90573f3cd6b10b06b10c9d0fe6b`:

- Hub2You: run `36992660196`.
- Autonom.ia: run `36992660215`.

No Hub2You, o parâmetro SSM de imagem correspondeu a esse SHA. A instância corrente
`i-04c8e3b417cbe2533` estava `running`; a anterior `i-006f22e2f0182fc45` estava `stopped`.
Isso confirma os metadados e a existência da instância anterior, não a imagem efetivamente executada dentro
dos containers nem a saúde funcional. Nenhum comando foi executado nas instâncias nesta etapa.

A credencial AWS local `default` retornou `InvalidClientTokenId`. O runtime e a instância de rollback da
Autonom.ia não puderam ser conferidos. Não houve login, troca de credenciais ou alteração de autenticação.
Antes de aprovar o deploy WAHA, obter evidência dessas informações por um acesso autorizado já válido.

Esses dados são uma fotografia anterior ao próximo lote. Revalidar os dois ambientes e os dois caminhos
de rollback imediatamente antes da autorização de merge/deploy do WAHA.

## Sequência para publicação

1. Concluir a revisão independente do migrador e das métricas; fechar todo achado bloqueante.
2. Fechar e validar o lote anterior. Montar o lote exclusivo WAHA a partir da `main` atual, preservando R1–R5
   e N1–N3 e sem trazer o zoom ou outros trabalhos para o escopo WAHA.
3. Executar a bateria fixa do processo de release e a união dos specs afetados; ler os resultados, lint e
   arquivos gerados. Registrar a árvore/HEAD final e deixar o PR do lote revisável.
4. Conferir somente leitura: versões/configuração WAHA, módulo `brazilian-phone-numbers` carregado,
   sessões operacionais, imagens web/worker e rollback das duas instalações. O handoff registra
   `WAHA_APPS_ON` e sua persistência; esse registro histórico não substitui a conferência atual.
5. Solicitar autorização explícita de Rodrigo para o merge e o deploy daquele SHA. Merge de código na
   `main` dispara automaticamente o blue-green nas duas stacks; a decisão deve considerar ambos os ambientes.
6. Após autorização, fazer um único merge do lote, acompanhar ambos os workflows e conferir diretamente
   imagem/SHA dos containers web e worker, target saudável, serviços ativos e saúde pública.
7. Garantir que todos os workers que processarão o piloto já executem o código novo. Eventos antigos,
   sem timestamp capturado, mantêm a métrica legada; ciclos já abertos antes do deploy também. Não recalcular
   histórico nem prometer correção retroativa. Validar N2 em uma nova reabertura após o deploy.
8. Com instalação, conta e Inbox selecionadas, executar o dry-run restrito. Só apresentar a aplicação para
   autorização depois de obter `total=1` e revisar as mudanças dessa sessão.
9. Executar uma única aplicação autorizada e a aceitação abaixo. Só depois decidir sobre um próximo lote
   pequeno de caixas, com nova autorização operacional e sem aplicar todas de uma vez.

## Piloto restrito — ainda sem instalação/IDs escolhidos

Solicitada a Rodrigo a instalação inicial (Hub2You ou Autonom.ia), `ACCOUNT_ID` e `INBOX_ID`.
Enquanto não forem definidos, nenhuma caixa é elegível para execução. Os comandos abaixo são modelos;
as variáveis devem ser preenchidas com IDs internos revisados da mesma instalação. Não registrar tokens,
telefones, configuração completa de Apps ou dados de clientes no GitHub ou neste repositório.

Antes de aplicar, reservar uma janela sem outros escritores de Apps/configuração da sessão, inclusive
durante eventual recuperação. N1 detecta alterações entre o planejamento e a última leitura, mas a WAHA
não oferece, neste fluxo, PUT condicional atômico. Um escritor após a última leitura ainda pode ser afetado.
Se não for possível impedir esses escritores durante o piloto, não autorizar sua execução.
Também manter o provider WAHA e `lock_to_single_conversation=true` sem mudanças até o processamento dos
eventos e a aceitação: o listener reavalia essa condição quando consome o evento de resolução.

Capturar, em armazenamento operacional privado e com acesso restrito, o estado local e a sessão/lista
completa de Apps antes do piloto. Definir quem poderá restaurar esses dados, evitando imprimir secrets.
Esse backup é necessário para desfazer uma migração bem-sucedida; R1 cobre falhas de aplicação e não
substitui um rollback operacional posterior.

Dry-run explícito, no container da aplicação da instalação selecionada:

```bash
APPLY=false ACCOUNT_ID="$WAHA_PILOT_ACCOUNT_ID" INBOX_ID="$WAHA_PILOT_INBOX_ID" \
  bundle exec rails waha:backfill_existing_inboxes
```

Exigir `total=1`, `failed=0`, `skipped=0`, `recovery_failed=0` e `halted=false`.
Para caixa a migrar, `would_update=1`; `unchanged=1` indica caixa já compatível e não comprova uma nova migração.
`total=0` exige corrigir/revisar a seleção, sem ampliar filtros. Confirmar identidade do App Chatwoot,
conta, Inbox, instalação e sessão `WORKING` antes de propor a aplicação.

Aplicação somente com autorização explícita, usando os mesmos IDs:

```bash
APPLY=true ACCOUNT_ID="$WAHA_PILOT_ACCOUNT_ID" INBOX_ID="$WAHA_PILOT_INBOX_ID" \
  bundle exec rails waha:backfill_existing_inboxes
```

Qualquer `SKIP`, `FAILED`, `RECOVERED`, `CRITICAL` ou `halted=true` encerra o piloto e o lote.
Não realizar retry cego, merge silencioso de configuração ou novo pareamento. Confirmar a recuperação por
leitura antes de qualquer nova decisão. Mesmo recuperada, a sessão não autoriza continuar automaticamente.

## Aceitação da única caixa

- Relatório: `total=1`, `updated=1`, `failed=0`, `skipped=0`, `recovered=0`, `recovery_failed=0`, `halted=false`.
- Sessão voltou a `WORKING` sem logout, novo QR ou perda de autenticação.
- Apps não relacionados e suas configurações foram preservados; Chatwoot e o resolver têm o estado previsto.
  Exatamente um `brazilian-phone-numbers` habilitado; vínculo local corresponde ao App confirmado remotamente.
- Repetir o dry-run restrito: `total=1`, `unchanged=1`, `would_update=0`, sem erro.
- Mensagem real pelo celular aparece como saída normal; mensagem pela plataforma chega ao contato correto,
  com entregue/lido quando disponível. Validar sem duplicação/eco e usando contatos de teste autorizados.
- Resolver, receber mensagem do mesmo contato e confirmar reabertura da mesma conversa. Resolver de novo e
  conferir a duração do novo ciclo, inclusive processamento atrasado dos eventos, sem somar o ciclo anterior.
- Conferir variação brasileira de número 8/9 dígitos no chat correto com um contato de teste controlado.
- Registrar resultado, horário, SHA da aplicação e IDs internos em auditoria sem conteúdo de mensagens.

Aceitação incompleta não libera expansão. Operações reais de mensagem e leitura de dados de cliente ficam
dentro do escopo explicitamente aprovado para o piloto; esta preparação não as executa.

## Rollback — aplicação e migração têm estados diferentes

Para falha da aplicação, após autorização operacional, usar `workflow_dispatch` na branch `main`,
`action=rollback` e `confirm_production=true` em:

- `.github/workflows/deploy-hub2you-blue-green.yml`.
- `.github/workflows/deploy-autonomia-blue-green.yml`.

Escolher o ambiente afetado e avaliar o outro antes de executar qualquer ação. Conferir que a instância
anterior ainda existe e corresponde à imagem esperada; o rollback oficial retorna só um deploy.
Após rollback, conferir web/worker, target e saúde. Interromper novas aplicações do migrador. Não há migration
de schema neste candidato; ele altera atributos de canais/conversas durante o uso e configuração remota
durante o backfill, que não desaparecem ao voltar a imagem.

Para falha durante o PUT, deixar R1 restaurar e confirmar a sessão; `RECOVERED` ainda exige parada e revisão.
Se houver `CRITICAL/recovery_failed`, tratar a recuperação da sessão como incidente, preservar evidências
privadas e obter autorização para a ação concreta. Não substituir por logout ou novo pareamento.

Para desfazer um piloto bem-sucedido, o rollback da aplicação sozinho é insuficiente. Restaurar configuração
WAHA e atributos locais exige procedimento operacional separado e aprovado: comparar o estado atual com
o estado pós-piloto, detectar intervenções posteriores e preservar Apps/configuração novos. Não fazer PUT
cego do backup anterior nem atualizar o banco antes de confirmar o resultado remoto. Se houver mudança
posterior, parar e preparar uma restauração específica, sem merge silencioso. Não há um comando automático
de rollback de migração aprovado neste candidato.

## Pendências antes de liberar o merge/deploy

- Resultado da revisão independente e da bateria completa registrado no relatório de preparação.
- Lote anterior fechado e aceito; base final do lote WAHA revalidada.
- Evidência atual de runtime/rollback das duas instalações, com a pendência de acesso da Autonom.ia resolvida
  por um acesso autorizado, sem alteração de autenticação nesta etapa.
- Instalação, conta e Inbox do piloto escolhidas; janela sem escritores e guarda privada dos snapshots definidas.
- Aprovação explícita de merge/deploy do SHA final. Aprovação separada da execução do piloto após seu dry-run.
