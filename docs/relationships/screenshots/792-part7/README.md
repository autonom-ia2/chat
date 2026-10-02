# #792 — Parte 7: cadastro real de contato, empresa e oportunidade

Capturas da aplicação local real, com Rails/PostgreSQL, login normal, cadastros sintéticos e componentes nativos. Não são imagens geradas nem o HTML de demonstração. Não comprovam publicação na AWS.

O roteiro principal executou 14 verificações e gerou dez telas; a captura 11 apresenta um rascunho sem possível homônimo, sem gravar registros. Outros 25 checks revalidaram as partes 5 e 6 no código atual. A lateral mede 640px em desktop/notebook e ocupa os 390px disponíveis no celular. O botão de criação permanece no rodapé.

| Arquivo | Estado mostrado |
|---|---|
| [11-novo-cadastro-desktop.png](11-novo-cadastro-desktop.png) | Novo contato e nova empresa, campos essenciais e cadastro ainda não salvo. |
| [01-novo-contato-e-empresa.png](01-novo-contato-e-empresa.png) | Mesmo fluxo com aviso de empresas homônimas; nome igual não é bloqueio de duplicidade. |
| [02-atributos-compartilhados.png](02-atributos-compartilhados.png) | Detalhes e atributos do contato recolhíveis, usando definições reais da conta. |
| [03-dados-da-oportunidade.png](03-dados-da-oportunidade.png) | Segunda seção com dados comerciais e ação fixa de confirmação. |
| [04-cadastros-confirmados.png](04-cadastros-confirmados.png) | Oportunidade realmente gravada, contato e empresa vinculados. |
| [05-novo-contato-empresa-existente.png](05-novo-contato-empresa-existente.png) | Nova pessoa associada a uma empresa existente por seu ID. |
| [06-reutilizacao-de-contato.png](06-reutilizacao-de-contato.png) | Pessoa encontrada por identidade: reutilização somente após ação explícita. |
| [07-reutilizacao-de-empresa.png](07-reutilizacao-de-empresa.png) | Domínio normalizado já cadastrado: escolha explícita da empresa encontrada. |
| [08-retentativa-segura.png](08-retentativa-segura.png) | Erro de rede deliberado após confirmação no servidor; a nova tentativa recupera os mesmos registros. |
| [09-cadastro-no-celular.png](09-cadastro-no-celular.png) | Formulário responsivo em 390×844, sem rolagem horizontal e com rodapé acessível. |
| [10-cadastro-no-notebook.png](10-cadastro-no-notebook.png) | Formulário em notebook 1366×768, largura de 640px. |

## Rastreabilidade

`manifest.json` contém estados, tamanhos, hash SHA-256 das fontes e PNGs, callbacks de console e resultados do navegador. `persistence.json` confere diretamente no banco os oito IDs de oportunidade, os sete contatos novos, as três empresas novas e a ausência de novas mensagens/conversas nesse roteiro. `previous-flows.json` registra a reexecução dos fluxos aprovados. `cache-probe.json` reproduz duas substituições simultâneas no IndexedDB real; a correção confirma ambos os snapshots sem exceções. `backend-summary.json` registra 305 exemplos, zero falhas e três suspensos antigos separados dos 302 aprovados.

O console mantém o 404 da consulta de limites Enterprise no ambiente local, avisos nativos e falhas HTTP de validação/rede esperadas. Nos roteiros finais não houve exceção JavaScript não tratada. A interrupção de rede é a única interceptação de uma resposta de negócio: o servidor grava de verdade antes de o navegador perder a confirmação. Nenhum resultado positivo de cadastro foi simulado.

Roteiros temporários: `.codex/792/part7-browser-ui.mjs`, `part7-clean-desktop.mjs`, `part7-persistence-check.rb` e os roteiros de regressão das partes 5/6. Os dados de autenticação local não fazem parte das evidências versionadas.

[Auditoria, contratos, testes e limites](../../../audit/2026-09-30-792-crm-relationships-part-7.md). Aguardar aceite de Rodrigo antes do próximo incremento. Sem merge ou deploy.
