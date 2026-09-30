# Liberação da importação com Jev — #764 — 30/09/2026

## Escopo e autorização

Rodrigo autorizou merge/deploy quando implementação, revisão e testes estivessem verdes e confirmou continuar/finalizar com cuidado após a interrupção do RDS. O lote exclusivo `release/2026-09-30-lote2` contém somente o PR #796: leitura com Jev antes dos aliases duplicados, distinção entre identificação da coluna e qualidade das linhas, privacidade dos exemplos e recuperação utilizável no editor. Não inclui outras frentes abertas. PR de liberação: #797.

Sem migration, dependência nova, mudança de política SES ou alteração de credenciais. O deploy utiliza o processo blue-green existente; suas etapas normais incluem preparação do banco, mas esta alteração não introduz novo schema. Nenhum envio ou reimportação de dados da conta 16 faz parte da validação.

## Evidências anteriores à integração

- Commit revisado `254c173726de00a1004fbdde553de05e29b60e78`. Revisão independente concluída, sem bloqueador remanescente.
- CI completo desse commit aprovado: Email [36743157692](https://github.com/autonom-ia2/chat/actions/runs/36743157692), Relacionamentos/imagem Linux [36743157710](https://github.com/autonom-ia2/chat/actions/runs/36743157710), fork i18n [36743157697](https://github.com/autonom-ia2/chat/actions/runs/36743157697) e Guia/Central [36743157615](https://github.com/autonom-ia2/chat/actions/runs/36743157615). Uma execução duplicada do Guia foi substituída por esta execução bem-sucedida no mesmo commit.
- Artefatos lidos: campanhas 1.050 exemplos, zero falhas, dois pending antigos; Relacionamentos 288 exemplos, zero falhas, um pending antigo. Frontend e imagem Linux também aprovados.
- Aceitação nova com Jev real: 30/30 resultados esperados, 26 importações e quatro recusas justificadas. Nome e valores de campos adicionais conferidos diretamente nos arquivos e em 51 destinatários salvos: nenhuma divergência. Os valores numéricos do XLSX são comparados com o conteúdo efetivamente armazenado na célula, não com a intenção do gerador.
- Estimativa observada US$ 0,007664916; reserva conservadora final US$ 0,031252284, dentro do limite US$ 1. Não é conferência de fatura. Nenhuma nova consulta paga necessária para liberação.
- Capturas reais, casos, resultados e limites em [aceitação](2026-09-30-typesafe-764-acceptance.md). Causa da queda do banco não determinada; contenção documentada em [interrupção do RDS](2026-09-30-typesafe-764-rds-interruption.md).

## Integração e bateria do lote

PR #796 squash no lote em `7da80ef87c2472a04238e0df24f8aebbf3ab0f66`, em 30/09/2026 16:51:15 UTC. `git diff --exit-code` confirmou árvore idêntica à implementação revisada/testada. A main não foi alterada por esse squash e nenhum deploy foi iniciado nessa etapa.

Bateria final do lote em execução: união de 579 arquivos RSpec da lista fixa Autonomia/CRM/Super Admin/configs/lib com campanhas/TypeSafe, apresentação e permissões Enterprise. Banco novo local `email764_releaseunion`, PostgreSQL local e Redis isolado; provedores pagos desativados. Frontend e geração/conferência Guia/Central serão concluídos antes do merge na main. O resultado completo e o CI do commit final são condições de liberação; uma contagem sem zero falhas não é aprovação.

## Publicação e rollback

Último lote publicado, #790, tem confirmação de runtime/browser em [auditoria de Relacionamentos](2026-09-30-release-relacionamentos-785.md). Os dois workflows de produção encerraram com sucesso em `e45fbe68945f948525dcc0a2997eae5c3c9dc74f`. Antes desta liberação, ambos os endpoints HTTPS responderam 200 e o RDS Hub2You estava `available`, sem modificação pendente. Isso confirma disponibilidade observada, não determina a causa da queda.

Após todos os gates, um único merge commit do lote na main dispara os workflows `deploy-hub2you-blue-green.yml` e `deploy-autonomia-blue-green.yml`. Verificar imagem de web/worker, serviços, target group, HTTPS, assets e implementação publicada; conferir a recuperação no navegador em modo de leitura. Não executar nova rodada de importações produtivas ou envio como teste de saúde.

Rollback em caso de falha da entrega: `workflow_dispatch` com `action=rollback` e `confirm_production=true` nos dois workflows oficiais, retornando à instância/imagem imediatamente anterior. A drenagem de importações segue o runbook existente. Sem schema novo a reverter; não apagar importações ou destinatários. Confirmar os parâmetros `previous-*` antes de declarar o rollback disponível. Nenhum rollback executado nesta etapa.
