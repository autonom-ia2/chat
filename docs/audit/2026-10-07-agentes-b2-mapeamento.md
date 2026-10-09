# Auditoria — mapeamento do desenho B2

**Data:** 07/10/2026  
**Branch:** `docs/agentes-ia-prd`  
**Worktree:** `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Baseline de código:** `6242e31695fd1c6b8b088f2fcb819c027fc5083c`  
**Issue:** #1122  
**Estado:** rascunho documental, sem revisão de desenho e sem implementação.

## Escopo e autorização

Foi autorizado escrever somente:

- `docs/agentes-ia-redesign/design/B2.md`;
- este apêndice de auditoria.

Não foram alterados código de produto, specs, PRD, HANDOFF, rotas de produção, banco, secrets, fila,
merge ou deploy. Não houve consulta de produção, SQL, eval pago ou escrita de dados.

## Fontes lidas

- PRD: §6.6, §7.0–§7.2, §8, §10.1, §11.2, §11.6 e critérios CA relacionados;
- `docs/agentes-ia-redesign/aceite-telas-reais.md`, incluindo as 14 famílias de cenários;
- mockup local: `mockup/src/data.js`, `kit.js`, `screens-list.js`, `screens-build.js`, `screens-panel.js`,
  `screens-extra.js` e `main.js`;
- código no baseline fixo dos BEs 00, 01, 08, 11, 16, 27, 28 e 32;
- desenho B1 para respeitar o contrato do BE-19 e a dependência do lote.

## Evidências registradas

1. O gate atual usa `AUTONOMIA_AGENTS_ENABLED` e `autonomia_agents_enabled`; B2 propõe uma chave separada
   `autonomia_agents_redesign`, default off, sem alterar o gate antigo.
2. A listagem atual não calcula stats nem estado de montagem; `AgentEvent`, `Agent.kept` e a janela do
   Analytics permitem uma projeção agregada sem migration.
3. O teste atual é `202` em Redis e termina no `InteractiveJob`; o rascunho exige registrar só a conclusão
   real, o ator e o digest, mantendo a conversa fora da lista.
4. A API atual de canais devolve apenas vinculados/elegíveis e o vínculo tem scope `kept`; o desenho usa
   esses dados e a regra já existente de `EngagementGate` para `has_schedule`.
5. O espelho é criado com o nome inicial e `AgentBot` é avatarável; o desenho fecha a sincronização dos
   escritores de nome/foto, preservando bot externo e conta.
6. `Source` já possui status/revisão/metadata, e `Retriever` já implementa a exclusão e a salvaguarda de
   fora do negócio; o contrato novo torna essa decisão explícita para a UI.
7. A gaveta atual reutiliza serializer genérico, embora `Captain::MessageReport` tenha motivo/descrição;
   B2 reserva serializer próprio após filtragem de permissão.
8. A visibilidade do copiloto é calculada em dois caminhos diferentes hoje; B2 centraliza CRM, Autonomia,
   `CRM_COPILOT_ENABLED` e `CRM_AI_ENABLED`.

## Limites e pendências

- Este documento não prova que qualquer spec foi executada. O snapshot B1 foi capturado pela sessão
  coordenadora antes da escrita e a validação de código permanece uma etapa posterior.
- Nomes de classes, rotas novas e nomes de arquivos de spec no B2 são decisões de desenho para revisão;
  não são arquivos existentes nem autorização para criá-los em outro PR.
- O campo privado de estado só pode ser escrito pelo serviço interno descrito no B2. O contrato do B1 deve
  rejeitar a mesma chave quando vier pela API pública.
- As telas reais ainda precisam ser vistas em ambiente local isolado, em todos os cenários aplicáveis,
  tamanhos, temas e perfis de `aceite-telas-reais.md`. O mockup é referência visual, não evidência de
  implementação.
- Produção, banco, merge, fila e deploy continuam sob aprovação explícita do Rodrigo e coordenação da
  sessão Automação.

