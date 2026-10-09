# Checagem independente do desenho B2 — produto/UX e contratos

**Escopo:** única checagem após o bloco corretivo, pela lente de produto/UX e contratos de teste. O arquivo conferido tem SHA-256 `d8f488f5c8f0c53ad546aec7be603e602905c59e8ac967e677c719da3f2bf399` e 734 linhas. A comparação usa o PRD, o audit de decisões `docs/audit/2026-10-07-agentes-b2-desenho-decisoes.md` e a baseline fixa `6242e31695fd1c6b8b088f2fcb819c027fc5083c`. Não foram executados navegador, testes, build, banco ou produção.

## Resultado

**Nenhum achado novo.** Os três achados de produto da revisão normal foram corrigidos no desenho e não encontrei nova trava de jornada ou contrato incompatível com o PRD.

## Conferência dos achados anteriores

### PROD-01 — `skipped_tools`

Resolvido. `docs/agentes-ia-redesign/design/B2.md:321-339` separa resposta real concluída de erro, fecha o formato em `{slug, name, code}`, limita os códigos a `not_in_test` e `viewer_not_allowed`, aceita `not_in_test` para o editor e mantém o resultado de quem só vê fora de E4. A matriz de casos exige os dois positivos em `B2.md:637-640`, em acordo com `docs/agentes-ia-redesign/PRD.md:452-457`, `PRD.md:525` e `PRD.md:563-569`.

### PROD-02 — material pendente ou falho

Resolvido. E4 exige resposta concluída pelo editor, sessão e digest atuais, incluindo material pendente ou falho (`B2.md:144-159`). O estado do snapshot é explicitamente informativo e nunca guarda de E4, Testar, Continuar ou Ligue (`B2.md:353-359`); a regra de material repete a mesma decisão em `B2.md:518-522`. A conclusão posterior só invalida quando muda o conjunto efetivamente consultável ou a instrução, conforme o PRD (`PRD.md:420-427`, `PRD.md:452-457`, `PRD.md:539-540`).

### PROD-03 — `ready_for_test`

Resolvido. O campo foi removido do contrato de fontes. O desenho declara em `B2.md:520-522` que não existe `ready_for_test` e que a projeção de estados de material não é uma guarda da jornada.

## Conferências adicionais

- **Máquina de estados:** E1, E1x, E2, E2m, E3, E4, E5 e E6 têm precedência e destinos compatíveis com o PRD (`B2.md:141-159`). Agentes no ar ou pausados preservam E5/E6, conforme D24.
- **Namespace e ator:** o estado privado é escrito apenas pelo `AgentStateStore`, não aceita `config` público e não expõe instrução, histórico, tokens ou dados de cliente (`B2.md:133-200`). O POST, o job, a conclusão e o polling distinguem `AccountUser`, permissão atual, sessão e conta (`B2.md:317-351`).
- **Digest e foto:** o digest cobre os controles que têm leitor real e mantém hashes sem texto oculto ou segredo (`B2.md:207-245`). Nome invalida antes de operar; foto sozinha apenas sincroniza; nome e foto juntos invalidam uma vez; E5/E6 permanecem protegidos por D24 (`B2.md:246-258`, `B2.md:451-466`). Isso corresponde à matriz de leitores do PRD (`PRD.md:385-413`) e aos casos BE-16 (`B2.md:642`).
- **Materiais:** a projeção e o snapshot usam apenas `kind=knowledge`; mídia fica fora de `screen_state`, `uses`, contador, digest e Retriever (`B2.md:361-367`, `B2.md:468-522`). Os oito estados e a salvaguarda de todos os aceitos fora do negócio estão explicitados e cobertos pela matriz de specs (`B2.md:482-510`, `B2.md:643-644`).
- **Gaveta:** o contrato usa uma marcação `MessageReport` por linha, filtra conversas antes de buscar/ordenar/limitar, preserva `report_id`, trata duplicidades e separa `T`, `V`, `hidden_count` e `has_more` sem expor conteúdo oculto (`B2.md:524-570`). Isso acompanha o PRD para resultados, permissões e limite de 50 (`PRD.md:243-250`, `PRD.md:1149-1155`).
- **Simplificações de escopo:** `writes_external` e a execução completa das ferramentas permanecem explicitamente em B4b; o B2 apenas fecha o resultado de ferramentas puladas e o digest (`B2.md:10-13`, `B2.md:262-265`, `B2.md:334-339`, `B2.md:716-727`). Não tratei essa dependência declarada como erro B2.
- **Visual:** o desenho não declara aceite de telas reais, nem aprovação do mockup (`B2.md:656-688`). As 14 famílias, perfis e combinações de viewport/tema continuam sendo validação posterior, não evidência deste documento.

## Conclusão

O desenho corrigido está consistente com o PRD nas três questões verificadas e nas matrizes de estado, material, ator, digest, foto e gaveta. Está pronto para a próxima etapa documental/implementação prevista pelo processo, sem aprovação de código, telas reais, merge ou deploy.
