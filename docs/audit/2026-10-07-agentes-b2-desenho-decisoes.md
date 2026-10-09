# B2 — decisão da revisão normal de desenho

Issue #1122. Esta é a consolidação da primeira revisão independente do desenho, antes do código B2. Os relatórios técnico e de produto estão em `docs/agentes-ia-redesign/revisoes/B2-desenho-{tecnica,produto}.md`. Não é revisão de código nem aceite de telas reais.

Os nove achados são procedentes: seis técnicos e três de produto. A correção cabe no desenho, sem alterar decisões aprovadas do PRD e sem introduzir bloqueio de material ou API pública sem leitor.

| Achado | Decisão para o bloco corretivo |
|---|---|
| TEC-01 | Fechar matriz dos 12 controles operacionais, `with_knowledge`, `scaffold` e limites efetivamente lidos. O digest privado cobre mudanças de operação pré-live; a matriz distingue execução no Teste de entrega no atendimento. Texto oculto e telefone não aparecem na API. Escritores legados são detectados na comparação do digest, sem exigir uma segunda máquina de estados. |
| TEC-02 | Nome invalida pré-live e sincroniza espelho; foto sozinha só sincroniza. Nome+foto invalida uma vez. D24 mantém E5/E6. |
| TEC-03 | Projeção, contador e snapshot de conhecimento usam somente `kind=knowledge`. Mídia permanece no contrato legado sem receber estado/uso de conhecimento. |
| TEC-04 | Leitura em lote de última thread, resposta do dono, materiais e vínculos. Medir todo o GET com N agentes, não apenas a query de eventos. |
| TEC-05 | `AccountUser` é o ator persistido, com identidade de usuário apenas derivada. POST e execução exigem view; conclusão válida exige manage atual; polling continua exclusivo do criador e reautoriza view. |
| TEC-06 | A unidade é a marcação `MessageReport`: filtro de conversas antes de buscar/limitar marcações; contagens e paginação usam a mesma unidade e janela. |
| PROD-01 | Resposta concluída de editor com ferramenta pulada conta. Fechar `slug/name/code`, códigos `not_in_test` e `viewer_not_allowed`; viewer nunca satisfaz E4. |
| PROD-02 | Material pendente ou falho não bloqueia E4. Guardar estado informativo do snapshot; mudança efetiva posterior invalida pré-live e explica o motivo. |
| PROD-03 | Remover `ready_for_test`, pois não há consumidor nem requisito normativo. |

Causa comum: o rascunho descreveu os serviços isoladamente sem fechar os leitores, escritores legados e a unidade de cada resultado; também inferiu uma trava de prontidão que o PRD proíbe. Conferir o desenho corrigido pelos mesmos revisores, em uma única checagem. Se a checagem encontrar erro, parar, registrar a causa antes de corrigir e fazer uma revisão final. Erro nessa revisão final exige retorno ao Rodrigo. Não abrir nova sequência de rodadas.

Baseline fixo de conferência: `6242e31695fd1c6b8b088f2fcb819c027fc5083c`; mudanças B1 locais não são aprovação B2. O desenho corrigido permanece não implementado, sem migração executada, produção, merge ou deploy.

## Resultado da única checagem após correção

Os dois revisores independentes fecharam os nove achados sem erro residual, nos relatórios `B2-desenho-checagem-tecnica.md` e `B2-desenho-checagem-produto.md`. Alvo preservado: SHA-256 `d8f488f5c8f0c53ad546aec7be603e602905c59e8ac967e677c719da3f2bf399`, 734 linhas. Não foi necessária revisão final adicional. A correção posterior das referências de seção no relatório técnico não alterou o desenho nem abriu nova rodada.

O desenho está liberado para a implementação local prevista, após fechar a validação B1. Código B2, telas reais, prova de persistência, revisão de código e aceite visual seguem pendentes. Este resultado não autoriza produção nem qualquer operação de liberação.
