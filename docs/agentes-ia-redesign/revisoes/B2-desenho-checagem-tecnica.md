# Checagem independente do desenho B2 — técnica e segurança

**Data:** 2026-10-07  
**Artefato verificado:** `docs/agentes-ia-redesign/design/B2.md`  
**SHA-256 do artefato:** `d8f488f5c8f0c53ad546aec7be603e602905c59e8ac967e677c719da3f2bf399`  
**Baseline de código:** `6242e31695fd1c6b8b088f2fcb819c027fc5083c` (referência fixa da análise; não é uma afirmação sobre o `origin/main` atual).

## Resultado

**PASSOU: nenhum erro residual foi encontrado nos seis pontos técnicos TEC01–TEC06.** A checagem foi somente documental e estática. Não houve execução de banco, M2, navegador, produção, código de produto ou testes de implementação. O resultado não aprova a implementação, o gate visual, merge ou deploy.

## Evidências verificadas

| Ponto | Resultado | Evidência no B2 |
|---|---|---|
| TEC01 — estado, digest e escritores legados | Passou | O documento fecha os campos efetivos do digest, inclui `with_knowledge`, scaffold, ferramentas HTTP e as 12 chaves operacionais; define comparação contra escritores legados, estado privado e casos de teste. §§ 3.1–3.3, 4.2–4.4 e 10–11, linhas 207–307 e 606–645. |
| TEC02 — identidade, nome e avatar | Passou | Nome e avatar têm efeitos separados; avatar isolado não invalida e a alteração conjunta gera uma invalidação. O espelho e os canais preservam a associação da mesma conta. §§ 4.3 e 6.1–6.2, linhas 246–258 e 417–466. |
| TEC03 — materiais, conhecimento e mídia | Passou | Projeções, contadores, snapshot e elegibilidade ficam limitados a `kind=knowledge`; mídia mantém o contrato legado sem receber estados de conhecimento. Materiais pendentes ou falhos não bloqueiam E4. §§ 4.4 e 7.1–7.2, linhas 353–367 e 468–522. |
| TEC04 — lista, métricas e N+1 | Passou | O desenho define lote para threads/fontes/entries, preload de links e avatares, limite de consultas no GET completo e prova de incremento fixo. A consulta de reports usa janela e ordenação determinísticas. §§ 5.1–5.2 e 8, linhas 369–415 e 524–570. |
| TEC05 — async, ator, polling e autorização | Passou | O fluxo reautentica conta e `AccountUser`, restringe conclusão a view+manage, restringe polling ao criador/token, mantém 404 para posse/isolamento e 401 para view revogada, conforme o comportamento atual. §§ 4.4 e 10–11, linhas 309–359 e 606–645. |
| TEC06 — unidade dos reports | Passou | `MessageReport` é a unidade do contrato; a permissão filtra conversas antes do conteúdo e as métricas usam a mesma unidade, com paginação/contagens consistentes. § 8, linhas 524–570. |

## Conferências cruzadas

- A matriz de runtime preserva os controles de instrução, scaffold, knowledge, ferramentas HTTP, voz, silêncio, entrega, handoff e operação; mudanças efetivas invalidam o digest correspondente. O texto também registra que campos sem leitor no baseline não são tratados como comportamento ativo. §§ 4.2–4.3, linhas 260–307.
- O contrato de execução mantém `E4` inclusive quando material está pendente ou falho e registra o aviso sem inventar bloqueio operacional. Linhas 139–159 e 353–359.
- A autorização de POST, execução, conclusão e polling está separada; não há atalho para recuperar resultado de outro membro, conta ou token. Linhas 341–351.
- O relatório de métricas permanece na unidade de `MessageReport`, inclusive nos casos de múltiplos reports para a mesma conversa/mensagem e no isolamento por conta/agente/janela. Linhas 552–570 e 630–645.
- A remoção de `ready_for_test`, a regra de que apenas conhecimento participa das projeções e a paridade de mídia estão explícitas. Linhas 468–522.

## Limites da conclusão

Esta checagem confirma a coerência documental do alvo fixado. Ainda faltam a implementação, seus testes reais, a validação visual de todas as telas e a validação local dos cenários antes de qualquer release. Nenhuma leitura ou mutação de produção foi feita.
