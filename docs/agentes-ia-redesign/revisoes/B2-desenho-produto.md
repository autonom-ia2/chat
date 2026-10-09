# Revisão independente do desenho B2 — produto/UX e testes

**Escopo:** revisão normal, somente leitura do desenho `docs/agentes-ia-redesign/design/B2.md`, pela lente de produto, UX e contratos de teste. A fonte de verdade é o PRD nas seções 6.6 e 7.2 e a linha de base de código `6242e31695fd1c6b8b088f2fcb819c027fc5083c`, conforme o próprio desenho. Não foram executados navegador, testes, build ou ações de produção.

## Achados

### B2-PROD-01 — Alto — `skipped_tools` pode invalidar um teste que o PRD considera válido

**Prova:** `docs/agentes-ia-redesign/design/B2.md:257-267` classifica “`skipped_tools` incompatível” entre os resultados inválidos, mas não define o que torna o bloco incompatível, nem seus códigos aceitos. O exemplo de estado em `B2.md:169-180` só mostra uma lista vazia, e a matriz de specs em `B2.md:500-511` não exige um caso positivo de ferramenta pulada. O PRD fecha o contrato em `docs/agentes-ia-redesign/PRD.md:452-457`: uma resposta concluída na conversa atual conta para E4 mesmo quando uma ferramenta não rodou; em `PRD.md:525` os códigos são `not_in_test` e `viewer_not_allowed`, e `PRD.md:563-569` exige a distinção entre cotação/assíncrona e permissão de quem só vê.

**Efeito:** uma implementação pode tratar qualquer `skipped_tools` como falha, deixando o editor preso em E3 e sem “Está bom, continuar” mesmo após uma resposta real. Também fica indeterminada a mensagem de cotação, de ferramenta assíncrona e de espectador. Isso quebra a jornada de Teste e os cenários Lia, ajudante interno e só ver.

**Correção mínima:** definir no B2 o contrato fechado de `skipped_tools` (`slug`, `name`, `code`) com os códigos do PRD; considerar válidos os códigos normativos quando a resposta do editor terminou; reservar invalidação para resultado malformado ou erro real. Acrescentar às specs um teste positivo de editor com `not_in_test` e um teste de espectador com `viewer_not_allowed`, incluindo o aviso visual, sem fazer o teste de espectador satisfazer E4.

### B2-PROD-02 — Alto — o requisito de material resolvido cria uma trava de E4 que o PRD não autoriza

**Prova:** a tabela de estados de `docs/agentes-ia-redesign/design/B2.md:144-153` exige, para E4, “snapshot de material resolvido”. A regra operacional em `B2.md:269-274` repete que material pendente permite responder, mas que E4 só existe com `material_snapshot_state=complete`; a matriz de specs em `B2.md:510-511` torna essa condição obrigatória. O PRD diz que Testar libera com as quatro respostas e sem travar por material pendente ou com falha (`docs/agentes-ia-redesign/PRD.md:188-194`, `PRD.md:539-540`), define E4 pelo teste concluído por quem edita sobre a instrução atual (`PRD.md:420-427`) e afirma que uma resposta concluída conta, enquanto erros e ausência de resposta não contam (`PRD.md:452-457`).

**Efeito:** com material em “Lendo” ou pendente, a pessoa pode concluir uma resposta real, mas o desenho mantém o agente em E3 e não libera “Está bom, continuar”/Ligue. A espera invisível contradiz a jornada simples e o contrato de avanço; o usuário não recebe uma ação que explique por que precisa esperar. A posterior conclusão do material já pode invalidar o teste por mudança de digest, sem bloquear o teste inicial.

**Correção mínima:** formar E4 a partir da resposta concluída do editor, da sessão e do digest atuais, independentemente de o snapshot estar pendente ou falho; guardar o estado do snapshot apenas para auditoria e projeção. Quando a leitura posterior mudar a instrução ou o digest de material, invalidar para E3 com o motivo previsto no PRD. Se a equipe quiser uma trava adicional, ela precisa primeiro ser uma decisão explícita no PRD e ter cópia/CTA próprios.

### B2-PROD-03 — Médio — `ready_for_test` é um campo sem contrato de leitura

**Prova:** `docs/agentes-ia-redesign/design/B2.md:365-374` adiciona `ready_for_test` à API de fontes, mas `B2.md:376-399` só fecha `screen_state` e `uses`; não há mapeamento de quando `ready_for_test` é `true`. A única regra é parcial em `B2.md:401-410`: fica falso enquanto a fonte alterada não tem snapshot estável, sem dizer o que o consumidor deve fazer nos demais estados. A matriz de specs cobre os oito `screen_state` e `uses` (`B2.md:514-519`), mas não testa esse campo. Uma busca no PRD, no aceite de telas reais e no próprio B2 não encontrou contrato, leitor de front ou caso de aceite para `ready_for_test` fora dessas duas menções do desenho.

**Efeito:** um implementador pode usar o campo para desabilitar Testar ou “Continuar” durante material pendente, reforçando a trava apontada em B2-PROD-02; ou pode ignorá-lo e entregar uma propriedade pública sem significado. As duas leituras produzem jornadas diferentes para o mesmo estado.

**Correção mínima:** remover `ready_for_test` do contrato B2 se nenhum consumidor real precisar dele. Se for mantido, definir uma enumeração/semântica fechada por estado, declarar expressamente que ele é informativo e nunca bloqueia E3/Testar conforme PRD, e adicionar specs de `true`/`false` para todos os estados relevantes.

## Conferências realizadas sem novo achado

- O desenho enumera as 14 famílias de aceite e não as declara aprovadas (`B2.md:527-559`); também registra que o aceite visual real ainda depende das combinações de viewport, tema e perfil. Não tratei o mockup como captura de tela real.
- A matriz de atores, namespaces privados e campos de teste mantém a separação entre editor e espectador (`B2.md:163-184`, `B2.md:261-267`). O problema encontrado é a semântica incompleta do resultado, não uma exposição de dados privados.
- As fontes de material usam uma projeção compartilhada para Retriever e tela (`B2.md:401-410`), e o desenho preserva a salvaguarda de todos os materiais fora do negócio (`B2.md:392-399`).
- O desenho deixa ferramentas e invalidações adicionais para B4/B4b (`B2.md:587-599`); não converti essa dependência declarada em achado B2.

## Conclusão

B2 tem um mapa útil de estados, atores, materiais e famílias de aceite, mas não está pronto para implementação sem corrigir os dois contratos de jornada acima. O primeiro pode negar um teste normativamente válido; o segundo introduz uma espera que o PRD proíbe. `ready_for_test` deve ser removido ou fechado antes de virar API pública. Não há aprovação visual nem evidência de telas reais nesta revisão.
