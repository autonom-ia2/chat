# #764 — interrupção do RDS durante a validação

## O que foi verificado

Durante a rodada de importação, o transporte de avaliação reutilizava o cliente e a chave guardados na instalação Hub2You, por SSM/Rails runner. Cada avaliação iniciava o Rails e lia a configuração/credencial; importações, campanhas e destinatários eram gravados exclusivamente no PostgreSQL local `127.0.0.1:55779`, banco `email764_acceptance`. Não foi programada migração, alteração de dados de cliente, reinício de serviço ou alteração do RDS.

O `SET default_transaction_read_only = on` do transporte original ocorria depois do boot do Rails. Isso limita as operações posteriores, mas não comprova que todos os inicializadores do boot tenham sido somente leitura. As leituras de configuração falharam com `PG::QueryCanceled` antes da avaliação do provedor em duas chamadas. Outra chamada expirou sem saída suficiente para determinar se houve avaliação; o orçamento conserva sua reserva máxima.

Ao Rodrigo relatar a queda, o runner local da rodada foi interrompido. Não foram encerrados processos do banco ou serviços produtivos. O transporte que repetia o boot e a consulta para cada arquivo foi suspenso.

## Registros da AWS

Consultas ao plano de controle da AWS, sem SQL adicional, identificaram o RDS `chatwoot-autonomia-prod` no perfil Hub2You, região `us-east-1`:

| Hora em São Paulo | Evento RDS |
| --- | --- |
| 12:39:54 | Recovery of the DB instance has started |
| 12:43:47 | DB instance restarted |
| 12:44:00 | Recovery of the DB instance is complete |

O log de sistema do PostgreSQL registra `received smart shutdown request` às 15:40:55 UTC, encerramento completo às 15:41:22 UTC e `database system is ready to accept connections` às 15:43:42 UTC. O CloudTrail consultado entre 15:00 e 16:00 UTC não retornou `RebootDBInstance` ou `ModifyDBInstance` referentes a esse banco. Essa ausência não estabelece quem ou o que iniciou a recuperação.

As métricas anteriores à interrupção mostravam cerca de 90–102 MB de memória livre e uso de swap, sem pico de CPU ou fila de disco nas amostras consultadas. Houve uma lacuna de métricas entre aproximadamente 12:28 e 12:43. Memória baixa e coincidência temporal são indícios, não prova de falta de memória nem de causalidade do teste. A causa da recuperação automática permanece não determinada por esta investigação.

Depois da recuperação, o endpoint público `/api` retornou HTTP 200; uma leitura posterior levou 0,677 segundo. Saúde pública recuperada não equivale a diagnóstico da causa.

## Contenção e conclusão da rodada

O transporte final passou a agrupar as consultas ao Jev em um único processo por lote. `PGOPTIONS` configura as sessões como somente leitura desde o boot. Depois da leitura da configuração e criação do cliente, `ActiveRecord::Base.connection_pool.disconnect!` encerra a conexão; a checagem de desconexão antecede toda avaliação. As chamadas seguintes usam apenas o provedor, com dados sintéticos e mascarados. A chave permanece no processo instalado, sem cópia para o ambiente local, scripts, Git ou evidências.

O primeiro lote de 21 avaliações confirmou 29 dos 30 casos da revisão. Ele expôs um problema ainda existente de confiança na coluna de uma lista com 119 endereços inválidos. Após separar sinais de coluna e qualidade das linhas, o lote final de 27 avaliações novas e o processamento local dos 30 arquivos tiveram todos os resultados esperados. As respostas do lote são vinculadas ao SHA-256 da requisição e do arquivo e consumidas uma única vez; esse procedimento não representa execução do worker produtivo.

Não foi feita alteração de infraestrutura para contornar a queda. A análise da causa do RDS continua separada da correção da importação. Não há evidência suficiente para afirmar que os testes causaram a interrupção ou para excluir contribuição das consultas anteriores.
