# Atributos personalizados de Empresas

## Objetivo

A conta pode definir atributos personalizados para Empresas usando o mesmo mecanismo de `CustomAttributeDefinition` já usado por Conversas e Contatos.

O recurso é exposto somente quando o feature flag `companies` está habilitado para a conta.

## Configuração

Em **Configurações → Atributos Personalizados** existem as abas:

- Conversas → `conversation_attribute`
- Contato → `contact_attribute`
- Empresa → `company_attribute`

A criação, edição e exclusão das definições usa a API existente de atributos personalizados. Não há tabela ou endpoint novo.

## Uso na Empresa

Na ficha de uma Empresa, a sidebar inclui a aba **Atributos**. Ela usa os componentes existentes `CompanyCustomAttributes.vue` e `CompanyCustomAttributeItem.vue`.

Os valores são persistidos em `Company.custom_attributes` e não são copiados para os contatos associados.

Tipos expostos nesta entrega: Texto, Número, Link, Data, Lista e Checkbox. Moeda e percentual permanecem fora da UI até validação específica de apresentação e edição.

## Compatibilidade e rollback

- Conversas e Contatos mantêm o comportamento existente.
- Contas sem `companies` não recebem a aba Empresa na configuração.
- Não há migration nem transformação de dados.
- Rollback: reverter o commit da entrega; os valores já existentes em `Company.custom_attributes` permanecem intactos.

## Extensão Relacionamentos — #757

Com `relationships_attributes`, a ficha da Empresa oferece o mesmo modal contextual
usado na ficha do Contato e na Central. A configuração de destaque fica em
`Account.settings.relationships.surfaces.company_details`; os valores continuam em
`Company.custom_attributes`. Uma seleção personalizada vazia destaca zero campos.
A aba completa de atributos não é filtrada. Campos de Empresa não aparecem
automaticamente no atendimento.

O novo fluxo exige descrição ao criar, mantém chave/tipo/entidade na edição e grava
definição e apresentação na mesma transação. Valores são confirmados individualmente
por `PATCH /api/v1/accounts/:account_id/relationships/company/:id/values`.
O corpo contém `field: { key, value, previous }`; `null` limpa somente a chave indicada.
Conflitos retornam 409 e erros de formato 422. O endpoint exige Companies e a flag de
atributos, além da permissão existente de atualização de Empresa.

`relationships_company_media` habilita a aba Mídias e a tabela ampliada, usando os
contatos vinculados por `company_id` e as conversas acessíveis ao usuário. Consulte
[company-media.md](relationships/company-media.md) e os bloqueios reais de validação
em [qa-acceptance.md](relationships/qa-acceptance.md).

Na retomada #757, o modal novo oferece Configurar campos e Criar atributo diretamente.
Ele exige descrição na criação, gera a chave sem regex e preserva chaves/metadados legados
ao renomear. Valores com validação histórica usam o editor existente; o novo endpoint de
valores os rejeita explicitamente. Ver aditivo em `docs/relationships/attributes-and-visibility.md`.
