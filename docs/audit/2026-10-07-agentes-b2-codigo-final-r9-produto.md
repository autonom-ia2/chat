# B2 — causa raiz do fechamento incompleto no snapshot final

**Data:** 2026-10-07
**Snapshot:** `20261007-190704-532a5b7b-42bf732f84-0ababeca`
**SHA de conteúdo:** `42bf732f841c507e24baf8e134990355c504983159e447d9ec4834cc0c79e3f0`

## Causa registrada

O lote funcional chegou ao snapshot final com os contratos de enum, disponibilidade do Copilot,
ordem de validação e configuração pública preservados. O fechamento não ocorreu porque a limpeza de
estilo ficou incompleta em duas fronteiras diferentes.

1. `RequestValidation` registra três filtros lexicais (`create`/`update`) dentro de um módulo que não
   declara essas actions. Rails resolve os callbacks no controller incluinte, mas
   `Rails/LexicallyScopedActionFilter` analisa o módulo isoladamente e mantém três ofensas.
2. A correção de alinhamento foi direcionada a um caminho Enterprise incorreto. O spec efetivamente
   incluído na bateria é `spec/enterprise/requests/api/v1/accounts/autonomia/agents/analytics_wrong_replies_spec.rb`,
   onde as linhas 104-107 ainda têm três ofensas de alinhamento de argumentos/hash.

Assim, os 222 exemplos Ruby e 43 testes JavaScript verdes não bastam para fechar o lote: o lint ainda
retorna seis ofensas em 106 arquivos. O bloqueio é de qualidade verificável, não uma autorização para
reabrir contratos B2, F0 ou F1.

## Saída mínima para a próxima execução

Mover os três `before_action` para o `AgentsController`, logo depois do `include`, preservando a ordem
`validate_public_config_contract`, `validate_actuation_type`, `validate_copilot_actuation`; manter os
métodos no concern. Alinhar as três continuações no spec Enterprise de requests correto. Depois disso,
executar lint direcionado e a mesma bateria coordenada. Não fazer correção ampla nem alterar enum,
Copilot, configuração ou produto enquanto esse gate estiver pendente.

Não houve edição de código, teste, build, banco, produção ou configuração nesta checagem.
