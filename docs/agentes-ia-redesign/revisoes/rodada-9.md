# Rodada 9 — 07/10/2026

## Escopo e evidência

Revisão documental independente nas lentes produto/UX, técnica, segurança/produção e testes/aceite. Baseline de código fixo `6242e31695fd1c6b8b088f2fcb819c027fc5083c`; mudanças posteriores em origin/main não foram incorporadas. Autores não aprovaram os próprios documentos. Segurança e testes usaram CLI somente leitura com gpt-6.1-sol/high após limite de threads; execuções sem conclusão foram descartadas, sem contar como aprovação.

O protótipo publicado foi inspecionado no navegador, com Todas as telas e Ver esta tela como. Isso não equivale a telas reais ou aceite de produto. O desenho B1 continua rascunho; somente os dois SQL passaram revisão final própria e foram executados com autorização restrita.

## Achados e tratamento

| ID | Gravidade | Achado | Tratamento |
|---|---|---|---|
| UX-01 | Alto | Exclusão interna contradizia preservação D34/#1063 | Corrigir item inteiro de exclusão e aceite correspondente |
| UX-02 | Médio | Checklist não explicitava Abrir para só ver em E1–E4 | Acrescentado cenário obrigatório CA-LISTA-15 |
| UX-03 | Médio | Resultado confundia Atendendo com Pronto para ligar | Separadas transições E5 e E4 e prova no backend |
| UX-04 | Médio proposto | Lia Testar supostamente inacessível no mapa | Achado rejeitado após prova no navegador: Como está indo Lia → Testar; caminho acrescentado |
| UX-05 | Médio | Checklist omitia três pessoas leigas de O1 | Gate humano obrigatório, mediana e todas sem ajuda; pendente antes de deploy |
| UX-06 | Médio | Reutilização de material incompleta no checklist | Incluídos um/vários/vazio/404 entre contas/arquivado |
| TEC-01 | Médio | Equivalente com flag OFF indefinido | Destinos por rota e aviso sem falsa equivalência WhatsApp |
| TEC-02 | Médio | CA-BE09 bloqueava efeitos pretendidos BE30 | Separar renomeação BE29 dos campos lidos BE30 |
| TEC-03 | Médio | Projeções de vínculos arquivados sem caso obrigatório | Acrescentar ausência em canais/counters/elegibilidade e substituição viva |
| TEC-04 | Médio | Registro operacional podia existir sem texto/filtro legível | Exigir apresentação/filtro/i18n em CA-BE07 e desenho B1 |
| TEC-05 | Baixo | HTML omitindo estado e aprovação das decisões | Gerador com sexta coluna e texto coerente |
| TST-1 | Médio | Ajustes Lia omitindo foto/público/janela e confundindo horários | Checklist alinhado a CA-AJU-12, salvar e reler |

Segurança/produção: zero novos achados no recorte documental; riscos BE19/25/31 já existentes continuam requisitos B1, sem afirmar correção implementada.

## Estado

Correções e checagem independente concluídas: zero achados residuais no escopo documental. Não há aprovação de código B1, aceite das telas reais ou autorização de merge/deploy. Achado na checagem exige parada, causa raiz e uma revisão final; erro persistente na final exige retornar ao Rodrigo.

### Checagem das correções — produto/UX e testes

Revisor independente confirmou UX01 no PRD (§6.3 item 9, §6.4, CA-AJU11, D34/#1063), sem contradição residual. Também confirmou UX02/03/05/06 e TST1 no checklist, sem nova falha concreta. UX04 permanece rejeitado como defeito: o caminho existente foi provado no navegador e explicitado no checklist. Checagem técnica também concluída, conforme abaixo.

### Checagem técnica

Revisor independente confirmou TEC01–05: mapa de rotas com flag desligada, BE29 separado de BE30, projeções de arquivados, Registro Enterprise legível/filtros/i18n e HTML com 35 estados/nove rodadas. Sem achado concreto nem causa raiz adicional. A checagem normal terminou limpa; não foi necessária outra revisão documental.

Resultado final documental: um alto, nove médios e um baixo confirmados na rodada normal, corrigidos e fechados na checagem; UX04 rejeitado por prova do caminho existente. Segurança/produção sem novo achado documental. Código B1 e aceite real não fazem parte deste resultado.
