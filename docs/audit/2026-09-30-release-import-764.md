# Liberação da importação com Jev — #764 — 30/09/2026

## Escopo e autorização

Rodrigo autorizou merge/deploy quando implementação, revisão e testes estivessem verdes e confirmou continuar/finalizar com cuidado após a interrupção do RDS. O lote exclusivo `release/2026-09-30-lote2` contém somente o PR #796: leitura com Jev antes dos aliases duplicados, distinção entre identificação da coluna e qualidade das linhas, privacidade dos exemplos e recuperação utilizável no editor. Não inclui outras frentes abertas. PR de liberação: #797.

Sem migration, dependência nova, mudança de política SES ou alteração de credenciais. O deploy utiliza o processo blue-green existente; suas etapas normais incluem preparação do banco, mas esta alteração não introduz novo schema. Até a autorização adicional registrada abaixo, a validação de publicação foi somente de leitura. Nenhum envio de e-mail faz parte desta entrega.

## Evidências anteriores à integração

- Commit revisado `254c173726de00a1004fbdde553de05e29b60e78`. Revisão independente concluída, sem bloqueador remanescente.
- CI completo desse commit aprovado: Email [36743157692](https://github.com/autonom-ia2/chat/actions/runs/36743157692), Relacionamentos/imagem Linux [36743157710](https://github.com/autonom-ia2/chat/actions/runs/36743157710), fork i18n [36743157697](https://github.com/autonom-ia2/chat/actions/runs/36743157697) e Guia/Central [36743157615](https://github.com/autonom-ia2/chat/actions/runs/36743157615). Uma execução duplicada do Guia foi substituída por esta execução bem-sucedida no mesmo commit.
- Artefatos lidos: campanhas 1.050 exemplos, zero falhas, dois pending antigos; Relacionamentos 288 exemplos, zero falhas, um pending antigo. Frontend e imagem Linux também aprovados.
- Aceitação nova com Jev real: 30/30 resultados esperados, 26 importações e quatro recusas justificadas. Nome e valores de campos adicionais conferidos diretamente nos arquivos e em 51 destinatários salvos: nenhuma divergência. Os valores numéricos do XLSX são comparados com o conteúdo efetivamente armazenado na célula, não com a intenção do gerador.
- Estimativa observada US$ 0,007664916; reserva conservadora final US$ 0,031252284, dentro do limite US$ 1. Não é conferência de fatura. Nenhuma nova consulta paga necessária para liberação.
- Capturas reais, casos, resultados e limites em [aceitação](2026-09-30-typesafe-764-acceptance.md). Causa da queda do banco não determinada; contenção documentada em [interrupção do RDS](2026-09-30-typesafe-764-rds-interruption.md).

## Integração e bateria do lote

PR #796 squash no lote em `7da80ef87c2472a04238e0df24f8aebbf3ab0f66`, em 30/09/2026 16:51:15 UTC. `git diff --exit-code` confirmou árvore idêntica à implementação revisada/testada. A main não foi alterada por esse squash e nenhum deploy foi iniciado nessa etapa.

Bateria final concluída: união de 579 arquivos RSpec da lista fixa Autonomia/CRM/Super Admin/configs/lib com campanhas/TypeSafe, apresentação e permissões Enterprise. Resultado: 6.197 exemplos, zero falhas/erros fora dos exemplos e 11 pending antigos (oito quarentenas e três evals pagas desligadas). Banco novo local `email764_releaseunion`, PostgreSQL local e Redis isolado. Frontend completo: 6.838 testes em 616 arquivos, zero falhas/erros. Guia build/check e Central check passaram por último, sem arquivo gerado alterado; avisos de evidências antigas da Central são existentes e o gate remoto também passou.

## Publicação e rollback

Último lote publicado, #790, tem confirmação de runtime/browser em [auditoria de Relacionamentos](2026-09-30-release-relacionamentos-785.md). Os dois workflows de produção encerraram com sucesso em `e45fbe68945f948525dcc0a2997eae5c3c9dc74f`. Antes desta liberação, ambos os endpoints HTTPS responderam 200 e o RDS Hub2You estava `available`, sem modificação pendente. Isso confirma disponibilidade observada, não determina a causa da queda.

Após todos os gates, um único merge commit do lote na main dispara os workflows `deploy-hub2you-blue-green.yml` e `deploy-autonomia-blue-green.yml`. Verificar imagem de web/worker, serviços, target group, HTTPS, assets e implementação publicada; conferir a recuperação no navegador em modo de leitura. Importações produtivas dependem de autorização específica; a autorização adicional e o teste limitado estão registrados abaixo. Nenhum envio deve ser executado como teste de saúde.

Rollback em caso de falha da entrega: `workflow_dispatch` com `action=rollback` e `confirm_production=true` nos dois workflows oficiais, retornando à instância/imagem imediatamente anterior. A drenagem de importações segue o runbook existente. Sem schema novo a reverter; não apagar importações ou destinatários. Confirmar os parâmetros `previous-*` antes de declarar o rollback disponível. Nenhum rollback executado nesta etapa.

## Gates finais e merge

Commit final do lote `37f7aa9cf910f8ee22ef36729cbde1321c927f2d`, acrescido somente desta auditoria em relação ao squash. Todos os checks aprovados: Email [36747761431](https://github.com/autonom-ia2/chat/actions/runs/36747761431), Relacionamentos/imagem [36747761483](https://github.com/autonom-ia2/chat/actions/runs/36747761483), fork i18n [36747761381](https://github.com/autonom-ia2/chat/actions/runs/36747761381) e Guia/Central [36747761526](https://github.com/autonom-ia2/chat/actions/runs/36747761526). Artefatos lidos: 1.050 exemplos de campanhas e 288 de Relacionamentos sem falhas; frontend 6.838 sem falhas. Artefato da imagem confirma o commit final, Ruby 3.4.4 Linux-musl e 11 verificações reais aprovadas.

A main foi reconferida em `f59a7e9f258efa7aa0be28f165ad581eb090e26b`, sem alteração concorrente. PR #797 mergeado com merge commit em 30/09/2026 17:26:02 UTC, SHA `45b28c56f0515f0675d69554b34a96f1345b3c00`. `git diff --exit-code` confirmou árvore idêntica entre lote aprovado e main publicada. A issue #764 foi encerrada pelo merge; o Project foi atualizado.

Workflows de publicação iniciados automaticamente: Hub2You [36751344997](https://github.com/autonom-ia2/chat/actions/runs/36751344997) e Autonom.ia [36751345161](https://github.com/autonom-ia2/chat/actions/runs/36751345161). O resultado operacional será registrado depois das verificações; iniciar o workflow não equivale a deploy concluído.

A investigação da interrupção do RDS permanece separada na [issue #798](https://github.com/autonom-ia2/chat/issues/798), no Project, com prioridade P1. Nenhum ajuste de capacidade/configuração aplicado por esta sessão. A medição de dez minutos anterior à liberação ainda mostrava pouca margem: aproximadamente 99 MiB disponíveis, swap 277 MiB, CPU 7,25% e 27 conexões no último ponto; RDS disponível, sem modificação pendente. Esses valores não comprovam a causa do incidente.

## Resultado operacional confirmado

Os dois deploys encerraram com sucesso: Autonom.ia às 17:40:32 UTC e Hub2You às 17:41:07 UTC. Web e worker executam `45b28c56f0515f0675d69554b34a96f1345b3c00` nos dois ambientes. Uma verificação por SSM comparou a revisão e SHA-256 de 18 arquivos de aplicação/configuração com o código aprovado, confirmou os dois serviços ativos e HTTP local saudável. Essa verificação usa Ruby padrão e Docker; não carrega Rails nem consulta o banco.

HTTPS público respondeu 200 em `https://chat.hub2you.ai/` e no domínio vigente `https://agents.autonomia.site/`. Os targets atuais estão `healthy`. As instâncias imediatamente anteriores estão preservadas e paradas, e os target groups anteriores existem nos dois ambientes. Parâmetros `current-*` e `previous-*` conferidos. Rollback oficial disponível; não foi executado. Uma consulta inicial usou por engano o endereço `chat2you.autonomia.site`, que não é o domínio vigente no workflow, e recebeu 404; esse resultado não descreve a aplicação vigente.

## Teste adicional em produção autorizado por Rodrigo

Depois da validação anterior, Rodrigo autorizou explicitamente: “Pode testar em produção sim... sem problemas.” A execução ficou limitada à conta 16, campanha fictícia 50, em rascunho, e ao arquivo original `05_duplicidade_normalizada.xlsx`, SHA-256 `9172ae95b1be49f90425c2bf23c0a0ceac8b37b86d0dfa361a9184e8eda0599d`, com dois registros sintéticos.

O popup apareceu automaticamente no editor de produção com o motivo histórico `duplicated_name_header`, orientação e opção para subir outro arquivo. O envio automatizado do navegador foi impedido pela permissão de arquivos da extensão. Nenhuma permissão foi ampliada. O navegador interno não tinha sessão autenticada. Por isso, a planilha foi anexada com a mesma persistência/lock usados pelo endpoint, em uma única execução Rails no servidor, e enfileirada para o worker normal. Isso executa a rotina de importação produtiva, mas não comprova o POST do upload pelo navegador em produção; o fluxo de escolha/reenvio completo foi exercitado no ambiente local e o popup/resultado foram confirmados no navegador produtivo.

Importação nova **29 concluída**; falha original **28 preservada**. Resultado: **1 adicionado, 1 duplicado, 0 inválidos, 0 suprimidos, total 2**. Metadados persistidos confirmam `method=jev`, `model=jev-1.13.0`, e-mail na coluna 2, nome na coluna 1, confiança do e-mail 1,00, do nome 0,85 e probabilidade do schema 0,96. Nome, endereço normalizado e empresa em campo adicional correspondem à planilha. Nome/assunto/HTML/status/agendamento do rascunho permaneceram iguais. Nenhum envio solicitado; campanha permaneceu `draft`.

O editor em produção passou a mostrar “Importação da lista concluída” e as mesmas contagens. Capturas reais e o relatório sanitizado foram preservados na pasta local de entrega `Documents/Codex/Entregas/2026-09-30-importacao-764`. A consulta ao Jev foi feita pelo worker produtivo com a credencial instalada, fechando a limitação anterior do transporte de teste. A rodada adicional não foi repetida nos clientes nem na Autonom.ia.

A reserva conservadora passou para **US$ 0,03950982**, incluindo até três tentativas e contexto máximo da consulta produtiva cujo uso não foi retornado pela interface pública. A estimativa observada anterior permanece US$ 0,007664916 e não cobre a medição desconhecida dessa última chamada. Ambas estão abaixo do orçamento US$ 1; não houve conferência de fatura.

A entrega #764 está concluída. A causa da interrupção do banco continua sem conclusão, acompanhada na #798, sem atribuição automática a estes testes ou ajuste de infraestrutura do RDS. Outras frentes abertas não foram incluídas neste lote.

Após a importação produtiva, o RDS Hub2You foi reconferido pela API AWS: `available`, sem modificações pendentes. Essa consulta não executa SQL; não é prova da causa anterior nem garante capacidade para qualquer carga.
