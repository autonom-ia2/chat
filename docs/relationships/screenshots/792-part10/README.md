# #792 — Parte 10: oportunidades dos contatos da empresa

Capturas reais da aplicação compilada, Rails/PostgreSQL locais, login normal e dados fictícios. Não são o mockup HTML nem prova de publicação na AWS. Retomada em 01/10/2026 após reconexão do Mac.

## Estados para aprovação visual

| Arquivo | Estado |
|---|---|
| [01-ficha-empresa-contatos-preservados.png](01-ficha-empresa-contatos-preservados.png) | Contatos continua sendo a entrada da ficha; abas anteriores preservadas. |
| [02-oportunidades-da-empresa.png](02-oportunidades-da-empresa.png) | Lista dos contatos vinculados, mostrando a pessoa de cada negociação. |
| [03-paginacao-contatos-e-moedas.png](03-paginacao-contatos-e-moedas.png) | Segunda página, moedas individuais e valor zero. |
| [04-oportunidades-ganhas.png](04-oportunidades-ganhas.png) | Filtro de ganhas aplicado pelo servidor. |
| [05-busca-em-todos-os-contatos.png](05-busca-em-todos-os-contatos.png) | Busca por título atravessando contatos e funis. |
| [06-oportunidade-aberta-no-crm.png](06-oportunidade-aberta-no-crm.png) | Mesmo card e seu funil no CRM; lateral de 640px e ficha original preservada. |
| [07-erro-de-consulta-e-retentativa.png](07-erro-de-consulta-e-retentativa.png) | GET deliberadamente interrompido, sem falso resultado vazio; retentativa real. |
| [08-oportunidades-da-empresa-celular.png](08-oportunidades-da-empresa-celular.png) | Painel móvel totalmente aberto dentro de 390×844. |
| [09-filtro-da-empresa-celular.png](09-filtro-da-empresa-celular.png) | Situação selecionada no celular. |
| [10-oportunidades-da-empresa-notebook.png](10-oportunidades-da-empresa-notebook.png) | Painel em notebook de 1366×768. |
| [11-empresa-sem-oportunidades.png](11-empresa-sem-oportunidades.png) | Outra empresa, sem herdar as linhas ou a contagem anterior. |
| [12-agente-apenas-oportunidades-permitidas.png](12-agente-apenas-oportunidades-permitidas.png) | Agente padrão: somente dois cards e total 2, sem negócios restritos. Não é um papel personalizado. |

## Evidências e limites

`manifest.json`: 14 checks concluídos, hashes de fontes/PNGs, console, requisições, viewports e **um cenário bloqueado separado**. `persistence.json`: consulta não alterou empresa, três contatos ou nove oportunidades; contagens, atributos e timestamps conferidos diretamente no banco. `contact-regression.json`: 14 checks da lista do contato reexecutados após o reaproveitamento da implementação, com persistência própria. Não foram sobrescritas as evidências publicadas da parte 9.

`compiled-assets.json` identifica o bundle realmente carregado, com SHA-256 e sem HMR. `backend-summary.json` registra 531 exemplos: 527 aprovados, zero falhas e quatro suspensos históricos. Os logs locais conservam os 502 testes frontend selecionados aprovados, as verificações de qualidade e os ensaios anteriores.

**Pendente, não aprovado:** a navegação empresarial do papel personalizado `contact_view/crm_view` não carrega a ficha; a rota existente aceita administrador/agente. Esse comportamento não foi transformado em sucesso nem contornado ampliando permissões. A API desse papel foi verificada separadamente e retornou apenas os dois cards autorizados, sem ganhos ocultos. O cenário de UI integra a revisão transversal antes da liberação final.

Nos caminhos concluídos não houve exceção JavaScript nem erro de renderização. Foram preservados os 404 da consulta de limites Enterprise local e as falhas deliberadas de GET. Não houve resposta positiva simulada; os testes usam APIs reais. A consulta não altera cadastros e não dispara mensagens.

[Auditoria, comandos, contratos e pontos pendentes](../../../audit/2026-09-30-792-crm-relationships-part-10.md). Aguardar aceite visual de Rodrigo antes da revisão integrada M01–M08. Sem merge/deploy.
