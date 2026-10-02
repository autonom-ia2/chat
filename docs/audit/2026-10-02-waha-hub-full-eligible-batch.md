# WAHA 2026.9.2 — ampliação do lote elegível Hub2You

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/869.
Piloto aceito: #865/#866. Duas caixas anteriores concluídas: #867/#868.
Estado atualizado: **retomada autorizada concluída; 21 caixas restantes aplicadas e confirmadas, total de 25 elegíveis conformes no Hub2You. As oito excluídas permanecem sem APPLY**.
Os blocos anteriores registram a interrupção e a revalidação; a conclusão está no bloco de retomada abaixo.

## Autorização e limites

Rodrigo pediu ampliar para todo o lote e confirmou explicitamente que a janela sem outros escritores
cobre todas as sessões restantes desta conta durante aplicação e eventual recuperação.
Escopo concreto: somente mesma conta do piloto no Hub2You. Autonom.ia e outras contas excluídas.
Na ampliação original não houve novo merge/deploy, logout, QR, pareamento, envio de mensagens extras ou edição de produto.
A autorização posterior para publicar a correção permanente de Status está registrada no bloco de retomada.
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

## Interrupção por regressão reportada

Rodrigo reportou publicações de Status do WhatsApp aparecendo como conversas e pediu bloqueio ou
controle opcional. O orquestrador foi interrompido antes de qualquer alvo seguinte. A primeira caixa
já tinha APPLY SSM em andamento; esse comando foi consultado, sem repeti-lo nem desfazer a caixa.

SSM backup 92da71f9-a3b4-4cf9-9a54-64e8a2abfdfe, Success/0, 21:44:07.693–21:44:18.693 UTC.
SSM APPLY e80fc1b8-20c7-4c2a-a7a2-f1938d9c1438, Success/0, 21:44:28.041–21:44:50.041 UTC:
updated=1; zero skips/falhas/recuperações; WORKING; configuração da sessão preservada;
resolver/vínculo/trava locais conferidos. Cópias before/after persistidas com hashes iguais e 0700/0600 root.
SSM confirmação read-only 42923f9c-88c6-4f96-bbe7-51cebf5b8b53, Success/0,
21:45:09.804–21:45:22.804 UTC: unchanged=1, would_update=0, zero falhas, hash local igual.

Somente um dos 22 alvos foi alterado. Os 21 restantes não receberam backup/APPLY nem foram substituídos
por outros alvos. A parada foi decisão operacional diante do relato, sem afirmar causa ainda não provada.
Não houve rollback, alteração adicional de produção, mensagens extras ou operações na Autonom.ia.
Investigar config.ignore.status e distinguir Stories de confirmação de entrega/leitura; bloquear expansão
até corrigir o comportamento. O plano anterior não habilita retry ou retomada automática após a parada.

## Filtro corrigido e restante revalidado

A operação autorizada de #871/#872 ativou e confirmou o filtro de Status nas quatro sessões já aplicadas, todas WORKING, preservando Apps, configuração não relacionada, estado local e histórico. Não houve merge/deploy nessa intervenção; o código permanente da PR #872 ainda não foi publicado. Evidência: [auditoria do filtro](https://github.com/autonom-ia2/chat/blob/e50b96b50ae89d8fd4933d6b500d64db6b0c4597/docs/audit/2026-10-02-waha-status-filter.md), commit e50b96b.

Em resposta à consulta sobre tombamento/backfill, o restante foi revalidado em modo somente leitura: SSM `5ee3d640-6efb-4718-9001-a1dc409c1da0`, Success/0, 2026-10-02 19:18:07–19:18:49 de Brasília. As 21 caixas restantes estão WORKING, em sessões distintas, com `ignore.status=true` e exatamente as quatro mudanças esperadas do plano original. Total=21, would_update=21, updated=0; zero skips/falhas/recuperações. Hash local antes/depois igual; banco em READ ONLY e cliente HTTP somente GET.

Esse backfill configura caixas existentes; não importa, apaga ou recalcula mensagens/histórico. O código base d28a87ad9b já está publicado no Hub2You. O resultado permite preparar a retomada das 21 caixas, com novos backups antes de cada aplicação, comparação N1 e parada R1, mantendo o filtro ligado. Nenhum APPLY novo foi feito após a revalidação; não reutilizar o orquestrador interrompido nem o backup antigo do primeiro alvo. Autonom.ia e as oito caixas excluídas permanecem fora deste lote. A consulta sobre prontidão não foi tratada como autorização de novo merge/deploy nas duas instalações.

## Retomada autorizada — lote concluído

Rodrigo autorizou seguir completo e com segurança após a revalidação. A execução manteve a janela
confirmada sem outros escritores e a seleção fixa do Hub2You. A publicação autorizada da correção
permanente de Status nas duas instalações segue #872/#873; isso não autoriza backfill na Autonom.ia.

Novo registro privado: `/Users/rodrigosilva/.codex/operations/waha-2026-10-02-lote4/full-batch-resume/`.
Não foi reutilizado o orquestrador interrompido. Os 42 runners Ruby da retomada passaram na verificação
de sintaxe com Ruby 3.4.4. Antes de cada APPLY, houve backup completo fresco e confronto com o estado
original; a escrita usou a task publicada com ACCOUNT_ID e INBOX_ID, preservando N1/R1.
Cada próximo alvo só começou depois da confirmação separada da caixa anterior.

Execução: 2026-10-02 19:27:44–19:54:17 de Brasília (22:27:44–22:54:17 UTC).
Resultado: **21 UPDATED, 63 comandos SSM Success/0**, zero skips/falhas/recuperações.
Cada uma das 21 sessões ficou WORKING, filtro de Status ligado, configuração não relacionada preservada,
resolver único habilitado e vínculo/trava locais corretos. Todos os dry-runs posteriores retornaram
unchanged=1, would_update=0, sem escrita, com hash local antes/depois igual.
Os IDs e resultados integrais dos 63 comandos ficam privados no resumo de conclusão.

Conferência agregada anterior à publicação: SSM `27feb719-5876-4a7c-bdfd-7302333c1fb0`, Success/0,
2026-10-02 19:54:48–19:55:36 de Brasília. As **25 caixas elegíveis** estão conformes, WORKING, em sessões
distintas, com ignore.status=true, plano vazio e unchanged=1 por caixa. Cliente HTTP GET-only e banco
em transação READ ONLY; nenhuma alteração de estado local. Nas janelas posteriores à aplicação/filtro
de cada caixa, observaram-se **5 mensagens comuns e 0 mensagens de Status**. Esse tráfego não estabelece
E2E completo nas 25 caixas; nas demais não houve tráfego novo naquela janela.

Os **50 arquivos before/after** das quatro correções de filtro e das 21 aplicações foram transferidos
cifrados para armazenamento privado fora da instância antes do deploy. SSM de selagem
`93b95666-6035-4e2d-84a0-105e98724ff0`, Success/0. AES-256-GCM autenticado, chave encapsulada com
RSA-OAEP; hash do arquivo cifrado conferido, cada hash interno conferido e comparação final contra os
hashes originais emitidos nas operações. Diretórios 0700/arquivos 0600. Teste local com 50 arquivos
sintéticos passou; arquivo adulterado foi rejeitado antes de gravar qualquer arquivo.
Também foram preservados e conferidos os oito arquivos before/after originais do piloto e das três
primeiras caixas ampliadas: **58 arquivos protegidos no total**, fora da instância, todos iguais aos
hashes das operações originais. Selagem adicional SSM `123fd3e1-b442-4655-8d68-37a8a3c04934`, Success/0.
Um erro inicial do conferidor local selecionava somente a última linha JSON da operação, que não
continha hash; foi corrigido para verificar todas as linhas e o sha256sum. Nenhuma divergência de dados
foi encontrada e nenhuma aplicação foi repetida.

Não houve importação, exclusão ou recálculo de mensagens/histórico, envios pelo operador, logout, alteração de
QR ou pareamento. As oito caixas excluídas continuam sem APPLY e exigem diagnóstico separado.
A Autonom.ia não recebeu backfill. O runtime usado nas operações foi d28a87ad9b; a publicação posterior
será registrada separadamente na auditoria do release; este documento de aplicação não comprova deploy.
