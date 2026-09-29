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
