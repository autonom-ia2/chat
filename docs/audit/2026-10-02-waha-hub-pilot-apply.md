# WAHA 2026.9.2 — APPLY do piloto Hub2You

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/865.
Continuação de [publicação do lote4](2026-10-02-waha-lote4-publication.md).
Estado: **APPLY unitário confirmado; aceites E2E e expansão pendentes**.

## Autorização e escopo

Rodrigo autorizou APPLY somente na caixa Hub2You selecionada anteriormente e confirmou a janela sem
escritores de Apps/configuração, incluindo eventual recuperação. Rodrigo responde pela decisão operacional
de restauração; Codex executa o procedimento documentado. IDs e dados da caixa ficam no registro privado.
Autonom.ia usa outra WAHA e ficou integralmente fora dos comandos deste piloto.
Nenhum novo merge/deploy, alteração de código, envio de teste, logout, QR ou pareamento foi executado.

## Preparação e backup

Conferência atual no M4: conta AWS Hub2You esperada, instância atual i-0f5f268683059c096 e target healthy.
Parâmetros runtime e SHA de web/worker conferidos contra d28a87ad9b7264042a92823c5b6f4d04831d1713.
Serviços ativos; frontend Hub2You e WAHA https://wa-hub.autonomia.site validados dentro do runner.
Filtro conjunto de conta/Inbox fixado, identidade local/remota correta e sessão WORKING.
Plano continuou com as quatro alterações revisadas: Chatwoot, resolver brasileiro, vínculo local e single_conversation.

Snapshot completo de sessão/config/Apps e atributos locais capturado antes da escrita sob transação
PostgreSQL read-only e bloqueio HTTP de mutações. Cópia persistida no host, fora do container e do Git,
com diretório 0700, arquivos 0600/root e hash igual ao original. Registro operacional privado no M4:
/Users/rodrigosilva/.codex/operations/waha-2026-10-02-lote4/pilot/backup-location.json.
Backup e estado posterior contêm dados sensíveis e não são anexados nesta auditoria ou no GitHub.
SSM do backup: 31ee02e3-25d9-418b-83aa-7abc1870b7d5, Success/0, 19:46:48–19:47:01 UTC.

O primeiro wrapper parou antes de invocar a task: datas eram serializadas por JSON.generate no backup
e attributes.to_json na comparação. Diagnóstico somente leitura confirmou igualdade integral usando
o formato do backup e divergência apenas de representação de created_at/updated_at no outro formato.
SSM interrompido a8aecadf-febc-4361-9f6c-cb3efea97582; diagnóstico e3d45fd2-fee6-4543-825d-65812d10d195, Success/0.
Comparação do wrapper corrigida para usar JSON.generate nos dois lados, sem ignorar qualquer atributo.
Não houve PUT nem escrita local nessa interrupção; nenhuma guarda do migrador foi relaxada.

## Aplicação e confirmação

Executada a task original waha:backfill_existing_inboxes com APPLY=true e os dois filtros privados.
Wrapper exigiu estado local integral igual ao backup e status/config/lista completa de Apps iguais ao backup
antes de entregar o plano ao executor. N1/R1 e as validações normais continuaram ativas.
SSM 1c0bf13d-919f-4f60-9bbe-49559ffabd36, Success/0, 19:48:33–19:48:57 UTC (16:48 BRT).

Resultado lido integralmente: total=1, would_update=1, updated=1, unchanged=0, skipped=0, failed=0,
recovered=0, recovery_failed=0, halted=false. Sem recuperação ou repetição de PUT após falha.
Confirmação remota/local: WORKING, session.config preservada, um resolver brasileiro habilitado,
vínculo local igual ao resolver e lock_to_single_conversation=true. Plano final sem alterações pendentes.
O snapshot inicial continha somente Chatwoot: não havia calls nem outro App independente para observar
preservação real neste alvo. O executor confirmou toda a lista desejada e não removeu nenhum App inicial.
Estado posterior também copiado ao armazenamento privado do host com hash verificado e permissões restritas.

Novo dry-run da mesma task/filtros: SSM dd3fd75f-1e34-4193-893c-bf41b9e1f6a0, Success/0, 19:49:11–19:49:24 UTC.
Resultado: total=1, would_update=0, updated=0, unchanged=1, skipped=0, failed=0, recovered=0,
recovery_failed=0, halted=false. Transação read-only e bloqueio HTTP de escrita ativos; hash local antes/depois igual.
Saúde pública Hub2You posterior: /api HTTP 200, versão 4.18.0, queue_services/data_services=ok.

## Limites e próxima etapa

Não houve alteração de produto neste trabalho: bateria de 5582 exemplos Ruby/1354 testes JS e RuboCop
continua vinculada ao lote publicado, não é reapresentada como uma nova execução deste piloto.
Ruby 3.4.4 verificou a sintaxe do runner privado. Auditoria passa por git diff --check e hooks normais.
Logs completos privados; nenhum secret, telefone, conteúdo de mensagem ou configuração completa publicado.

Faltam testes com contatos controlados autorizados: saída pelo celular, ausência de eco/duplicação,
envio pela plataforma, entrega/leitura, reabertura da mesma conversa e duração de um ciclo novo,
convergência brasileira de 8/9 dígitos e observação de reconexão sem forçar logout/QR.
Não expandir o backfill nem transportar IDs do Hub2You para Autonom.ia antes de concluir esses aceites.
Desfazer o piloto continua procedimento separado: comparar estado atual com o pós-piloto e aprovar ação
concreta antes de restaurar. Não aplicar PUT cego do backup antigo nem alterar dados locais primeiro.
