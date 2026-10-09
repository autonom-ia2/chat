# Audit — checagem limitada B2-CODE-01/02

Data: 2026-10-07

## Escopo

Leitura independente somente do snapshot23:

- caminho: `/Users/Shared/maccluster-workspaces/chat2you/20261007-184308-532a5b7b-9803329751-205ae53c/src`;
- SHA informado: `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`;
- alvo: correções do enum numérico do Copilot e da chave de canal na projeção da lista.

Não houve execução de teste, build, banco, navegador, produção ou mutação de produto.

## Evidência conferida

1. `AgentsController` rejeita qualquer `actuation` que não seja string e chave do enum antes das ações de create/update. Os casos request cobrem `1` e `2` em create e PATCH, com `422 invalid_enum` e nenhuma gravação parcial.
2. `CopilotAvailability` continua avaliando as quatro condições (`crm`, `autonomia`, `copilot` e `crm_ai`) para strings públicas válidas.
3. `ListProjection#channels_for` produz apenas `inbox_id`, `name` e `channel_type`; o serializer não renomeia nem duplica a chave. O spec da lista fixa o shape.
4. O endpoint de gestão de Canais continua separado e preserva `id` do vínculo, `inbox_id` da caixa, `eligible_inboxes` por `id` e a rota com `param: :inbox_id`. O consumidor legado usa essas formas de maneira compatível.

## Resultado

Nenhum residual concreto ou dependência incompatível foi encontrado nos dois achados. A checagem limitada passa; o lote B2 geral continua dependendo das outras correções e da execução coordenada registrada pelo principal.
