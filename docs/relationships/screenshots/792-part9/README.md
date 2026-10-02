# #792 — Parte 9: oportunidades na ficha do contato

Onze capturas da aplicação compilada, com APIs Rails/PostgreSQL locais reais e dados sintéticos. Não são imagens geradas, o HTML de demonstração ou uma publicação na AWS. O painel Acompanhamento preserva seu leiaute nativo; o card aberto no CRM continua com 640px, igual a Editar funil.

| Captura | Estado |
|---|---|
| [01-oportunidades-na-ficha.png](01-oportunidades-na-ficha.png) | Nova aba no Acompanhamento, oportunidades do contato em diferentes funis e contagem da consulta. |
| [02-paginacao-e-moedas.png](02-paginacao-e-moedas.png) | Segunda página obtida do servidor, com moedas individuais e valor zero preservado. |
| [03-oportunidades-ganhas.png](03-oportunidades-ganhas.png) | Filtro de oportunidades ganhas. |
| [04-busca-em-todos-os-funis.png](04-busca-em-todos-os-funis.png) | Busca por título alcançando um outro funil. |
| [05-resultado-vazio.png](05-resultado-vazio.png) | Consulta válida sem resultados; diferente de erro de rede ou autorização. |
| [06-mesma-oportunidade-aberta-no-crm.png](06-mesma-oportunidade-aberta-no-crm.png) | Mesmo card aberto no CRM, com o funil correto selecionado. |
| [07-erro-de-consulta-com-retentativa.png](07-erro-de-consulta-com-retentativa.png) | Falha de GET deliberada, com mensagem e nova tentativa; nenhum sucesso foi simulado. |
| [08-oportunidades-no-celular.png](08-oportunidades-no-celular.png) | Painel nativo no celular, capturado depois do fim da animação e dentro da viewport. |
| [09-filtro-no-celular.png](09-filtro-no-celular.png) | Filtro de ganhas em 390×844. |
| [10-oportunidades-no-notebook.png](10-oportunidades-no-notebook.png) | Lista em notebook 1366×768. |
| [11-visao-somente-leitura-com-permissoes.png](11-visao-somente-leitura-com-permissoes.png) | Usuário CRM somente leitura vê apenas seus dois cards e o total autorizado. |

## Evidências

`manifest.json` contém 14 checks da parte 9, 11 capturas, limites das viewports, hashes dos PNGs/fontes e registros de console/requisições. `persistence.json` confirma zero gravações: contato e oito cards foram comparados integralmente, incluindo timestamps em UTC/seis casas. As contagens de pessoas, empresas, oportunidades, mensagens e conversas ficaram iguais.

`previous-flow.json` registra 14 checks de regressão da criação contextual pela ficha, executados depois com baseline próprio. `compiled-assets.json` identifica o bundle efetivamente carregado e seu SHA-256. `backend-summary.json` separa 507 testes aprovados dos quatro suspensos históricos, entre 511 exemplos sem falhas. A bateria frontend selecionada teve 484 testes aprovados; não se afirma uma nova execução da bateria completa de mais de sete mil testes neste incremento.

A lista depende de acesso ao CRM e ao contato, com o mesmo escopo autorizado nos registros e na contagem. A API retorna somente os campos comerciais necessários, não conversas, mensagens ou metadados de IA. A criação não aparece para quem não tem permissão; um filtro vazio também não oferece essa ação indisponível. Os filtros da ficha não alteram os do Kanban. Abertura em outra aba preserva o formulário original.

Os ensaios incluem paginação, busca, situações, múltiplos funis, zero/moedas, previsão à meia-noite UTC, erro/retentativa, retorno ao foco, teclado, troca de contato, papel somente leitura e tentativa de abrir um card oculto. Não houve exceção JavaScript nem erro de renderização nos roteiros finais. Os 404 dos limites Enterprise locais e a interrupção de rede deliberada permanecem registrados.

[Auditoria, contratos e comandos](../../../audit/2026-09-30-792-crm-relationships-part-9.md). Scripts/logs temporários em `.codex/792/part9-*`; credenciais e snapshots detalhados não são publicados. Aguardar aprovação visual antes da lista na ficha da empresa. Sem merge/deploy.
