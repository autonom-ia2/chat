# 2026-09-18 — Funções personalizadas: matriz Ver/Editar (PR 1 de #452)

## Decisões (Rodrigo)
- Matriz por módulo Sem acesso · Ver · Editar, com modelos prontos; vale para todos os módulos do escopo.
- Fora: Captain e Empresas (não usados).
- Conexões: Ver/Editar enxergam todas as caixas da conta nas configurações; a visibilidade de conversas não muda.
- Agentes Autonom.ia: Ver inclui testar no playground.
- Entrega em 2 PRs: este (modal, bugs, Autonomia, Campanhas, Conexões) e o PR 2 (Prospecção, Cotação, configurações leves).

## Decisões técnicas
- Ponto de extensão `AccountUser#permission_granted?` (OSS = admin; EE soma chaves da função; `_manage` implica `_view`).
- Chaves antigas preservadas; funções existentes carregam sem migração.
- Ficam só com admin mesmo com Editar: token do WhatsApp Business, reset de segredo da caixa, OAuth apps de e-mail.
- Criação de caixa WhatsApp pelo cadastro incorporado segue aberta a agentes (comportamento upstream coberto por spec); só a reautorização exige `inbox_manage`.
- Respostas prontas: admin e agente sem função mantêm o acesso; função personalizada precisa de `canned_response_manage` para escrever.

## Validação
- RSpec novos: 13 de policy + 6 de request, verdes.
- Suíte existente dos módulos afetados (227 arquivos, 2349 exemplos): falhas restantes pré-existentes/ambiente (auditoria de caixa com dados residuais no banco de teste local; quarentenas já marcadas).
- Vitest: 13 testes novos verdes; suíte completa 5086 verdes, 14 falhas em helpers de data/fuso não relacionados.
- `bin/vite build` ok. Checagem visual local bloqueada: o dashboard em dev local para de re-renderizar também no `main` puro (verificado com stash) — pendente validar no ambiente de homologação/produção.
- Revisão independente: 1 bug (templates CSAT graváveis com `inbox_view`) corrigido.

## Pendências
- `InboxesController` já excedia `Metrics/ClassLength` antes desta mudança.
- Sub-abas de caixa com muitas ações (colaboradores, CSAT, configuração, conexão, voz) não escondem botões para quem só tem Ver; o backend responde 403.
