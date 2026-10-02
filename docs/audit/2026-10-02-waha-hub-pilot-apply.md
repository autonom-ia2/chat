# WAHA 2026.9.2 — APPLY do piloto Hub2You

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/865.
Continuação de [publicação do lote4](2026-10-02-waha-lote4-publication.md).
Estado: **piloto unitário validado nos casos exercitados; expansão não autorizada**.

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

## Aceites observados depois do APPLY

Rodrigo apresentou captura às 16:57 BRT com saídas do celular em balão normal e marca de leitura.
Consulta PostgreSQL somente leitura confirmou na conversa selecionada duas saídas externas públicas,
ambas status read, além de quatro recebimentos posteriores ao APPLY. Estes casos já cobrem saída normal,
recepção e leitura; não solicitar repetição desses casos. Sem conteúdo ou identidade de clientes neste registro.
SSM cb881382-166b-4618-8311-a4fd521737f3, Success/0, 19:58:52–19:59:03 UTC.

Consulta agregada na mesma Inbox, SSM 70913367-b744-4310-bd50-8a801fb56583, Success/0,
19:59:51–20:00:05 UTC: três saídas externas públicas (duas read, uma sent), seis recebimentos públicos,
nenhuma saída privada, nenhum envio público originado pela plataforma e nenhum evento de abrir/resolver
posterior ao APPLY. A conversa selecionada permanece aberta, sem marcador de novo ciclo.

Source IDs estão ausentes nessas mensagens; a contagem zero de IDs duplicados não comprova ausência
integral de duplicação/reenvio. Não fechar esse aceite só por essa consulta. A captura não prova teste
com variações 8/9 dígitos. Faltam envio pela plataforma, ciclo novo de resolver/reabrir/resolver e
convergência de número em contato controlado; esses passos aproveitam o piloto existente sem repetir chegada.
Nenhuma mensagem, resolução de conversa, configuração WAHA ou banco produtivo foi alterado nesta conferência.

## Conferência após os testes informados por Rodrigo

Rodrigo confirmou explicitamente que os três testes manuais passaram: chegada uma única vez,
reabertura da mesma conversa e convergência do contato com/sem nono dígito. Esses resultados manuais
não são apresentados como uma deduplicação por source_id observada no banco.

SSM somente leitura f4ccf98b-a209-47f1-9d66-7fa402125df7, Success/0, 20:03:43–20:03:55 UTC:
sessão WORKING e plano sem alterações. Dois envios públicos originados pela plataforma com status delivered,
nenhuma saída privada. Eventos mostram resolução seguida de abertura quatro segundos depois,
na mesma conversa e com somente uma conversa para aquele contato na Inbox.

A primeira resolução ainda corresponde ao ciclo legado sem marcador. A abertura posterior inicia
um novo atendimento, mas a conversa de teste permanece open e não há segunda resolução registrada.
Solicitado somente esse encerramento final para confirmar a duração do novo ciclo; não repetir mensagens
ou variantes já aceitas. Aceite de N2 em produção permanece pendente dessa evidência específica.
Sem nova escrita na produção, configuração WAHA, envio, QR, pareamento, merge/deploy ou expansão.

## Fechamento do novo ciclo e aceite do piloto

Rodrigo encerrou novamente a conversa de teste. SSM cdc2acbe-b827-4f76-96f3-0b5a8793f04d,
Success/0, 20:05:27–20:05:38 UTC, somente leitura: conversa resolved e uma única conversa para o contato.
Novo evento conversation_resolved: início 20:02:33 UTC, igual à abertura observada, fim 20:04:48 UTC,
value=135 segundos (2min15s). A mensagem recebida está dentro desse ciclo. O tempo não incorporou os dias
anteriores da conversa; N2 está observado em produção para esse novo ciclo completo.
Sessão WAHA WORKING, plano sem alterações e dois envios da plataforma continuam delivered.

Aceite dos casos solicitados: saída pelo celular pública/normal e leitura observadas; plataforma entregue
observada; ausência de entrega duplicada e convergência com/sem nono dígito confirmadas manualmente por Rodrigo;
mesma conversa reaberta e novo tempo de resolução confirmados nos registros. Não requer repetir esses testes.
Não foi forçada inversão de jobs, reconexão, QR ou concorrência na produção. A preservação de Apps extras
não foi exercitada neste alvo, que não os tinha. Esses limites permanecem explícitos, sem inferência de QA global.

Piloto unitário aceito para os casos exercitados. Expansão exige selecionar um próximo conjunto pequeno,
novo dry-run/backup e autorização própria. Autonom.ia precisa de seleção e piloto separados na sua WAHA.
A auditoria #866 permanece separada da aplicação; não há novo merge/deploy autorizado nesta etapa.
