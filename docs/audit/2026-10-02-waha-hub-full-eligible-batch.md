# WAHA 2026.9.2 — ampliação do lote elegível Hub2You

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/869.
Piloto aceito: #865/#866. Duas caixas anteriores concluídas: #867/#868.
Estado deste checkpoint: **22 alvos preparados; nenhuma escrita nesta ampliação ainda**.

## Autorização e limites

Rodrigo pediu ampliar para todo o lote e confirmou explicitamente que a janela sem outros escritores
cobre todas as sessões restantes desta conta durante aplicação e eventual recuperação.
Escopo concreto: somente mesma conta do piloto no Hub2You. Autonom.ia e outras contas excluídas.
Sem novo merge/deploy, logout, QR, pareamento, envio de mensagens extras ou edição de produto.
R1–R5/N1–N3 preservados. M4 identificado para toda operação com estado local.
Identidades exatas e configuração ficam privadas, fora de Git/GitHub.

Runtime atual verificado: AWS Hub2You, i-0f5f268683059c096, imagem e web/worker
no SHA d28a87ad9b7264042a92823c5b6f4d04831d1713. Frontend https://chat.hub2you.ai,
WAHA https://wa-hub.autonomia.site. Não transportar seleção ou configuração entre instalações.

## Inventário e dry-run

Inventário read-only SSM 8b143994-83b4-48e0-8550-e0f0aff6fc1d, Success/0,
21:39:52.965–21:40:46.965 UTC: 33 canais locais, 3 já conformes, 22 elegíveis restantes,
7 falhas Waha::Client::Error e 1 sessão FAILED. As oito exclusões não serão chamadas para APPLY
nem reparadas por este lote. A classe de erro não estabelece diagnóstico de autenticação.
Banco em transação read-only e cliente HTTP GET-only; hash de atributos locais permaneceu igual.

Seleção fixa, ordenada por Inbox, 22 sessões distintas WORKING, Chatwoot habilitado, identidade
consistente, módulo disponível, sem resolver existente. Em todas, somente quatro mudanças previstas:
configuração do Chatwoot, resolver brasileiro, referência local e lock_to_single_conversation.
Apps atuais contêm apenas Chatwoot; preservação de Apps extras não está exercitada neste lote real.

Dry-run individual com task original e ACCOUNT_ID + INBOX_ID para cada alvo:
SSM 02c3038c-21d0-43f9-99c2-304ad7c1b5fb, Success/0, 21:41:25.303–21:42:10.303 UTC.
Saída integral lida, por caixa: total=1, would_update=1, updated=0, unchanged=0,
skipped=0, failed=0, recovered=0, recovery_failed=0, halted=false. Sem escrita local/remota.

## Plano revisado para execução

Registro privado: /Users/rodrigosilva/.codex/operations/waha-2026-10-02-lote4/full-batch/.
Seleção, ordem, autorização, transporte, comandos/resultados e locais de backup ficam nesse registro.
44 runners Ruby têm o mesmo procedimento das duas caixas concluídas, mudando somente identidade
exata da Inbox; sintaxe validada com Ruby 3.4.4. Transporte muda lista permitida e regra de precedente.
Orquestrador privado conferido: exige autorização/janela/dry-run, fixa lista e para na primeira falha.

Por caixa, antes de seguir para a próxima:

1. Conferir identidade AWS, instância/imagem atuais, health e web/worker ativos no SHA publicado.
2. Backup fresco completo local/remoto, arquivo exclusivo, diretório 0700/arquivo 0600 e cópia
   persistente no host; exigir hash igual e permissões root antes de APPLY.
3. Exigir igualdade integral com backup e validade máxima de 15 minutos, invocar task original
   APPLY=true com ambos os filtros; preservar N1 antes da escrita e recuperação/fail-stop R1.
4. Exigir UPDATED=1, zero skips/falhas/recuperações, WORKING, sessão/configuração preservada,
   resolver único/habilitado, vínculo local correto e single-conversation; preservar after.json.
5. Dry-run GET-only e transação read-only: exigir unchanged=1, nenhuma escrita e hash local igual.

Comando já enviado não será repetido. Resultado desconhecido exige parar e consultar o mesmo comando.
Nenhum retry cego ou rollback global automático. Caixa anterior bem-sucedida não será desfeita se uma
seguinte falhar. Restauração necessária exige confrontar pós-estado e decisão concreta do Rodrigo.
GET/PUT WAHA não é atômico; comparação N1 não substitui a janela de exclusão confirmada.

## Validação e aceite

Somente auditoria em Git; git diff --check e hooks normais, sem --no-verify.
Sem mudança Ruby de produto, UI, schema, dependências, rotas ou Guia; nenhuma suíte ampla/RuboCop
local repetida ou apresentada como nova execução. Instalação local congelada somente para hooks.
E2E real aceito no piloto anterior não é presumido para as novas caixas. Esta ampliação verifica
configuração, preservação e idempotência; o uso normal deve ser acompanhado sem mensagens extras.
