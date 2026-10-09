# Revisão final — F0 produto, jornada e testes

**Alvo:** `docs/agentes-ia-redesign/design/F0-mapeamento.md`  
**SHA do alvo:** `38649eb14b909eae5628b82ac2275f88858cc2d291b4c8eaa3df1eddca9f8755`  
**Decisões:** `docs/audit/2026-10-07-agentes-f0-desenho-decisoes.md`, SHA `5b336f4aa5fb1e55d2052d9c373c2a0cd204d22e4d73c01f275edb48a56142b2`  
**Escopo:** revisão final única do mesmo bloco corretivo, contra o PRD, `aceite-telas-reais.md` e o diagnóstico de causa raiz. Não executei testes, build, navegador, banco, produção ou código de produto.

## Resultado

**PASS — não há erro residual concreto nos três pontos que bloquearam a checagem anterior, nem na matriz, nas permissões ou no retorno Conte.**

Isso fecha a revisão do desenho. Não aprova implementação, aceite visual, merge, fila, deploy ou produção: o F0 continua explicitamente DRAFT e o aceite ainda depende das telas reais, dos cenários locais e da aprovação do Rodrigo.

## Conferência dos três residuais

1. **Matriz rastreável e completa — fechado.** A seção 8 identifica o arquivo-base `tests/playwright/tests/agents/visual.spec.ts`, transforma cada estado em caso `Fxx-*`, exige leitor, perfil, ação, pós-condição, resultado `PASS/FAIL/BLOCKED` e quatro capturas por estado (F0:204-206). O cruzamento com as 14 famílias do aceite cobre todos os estados normativos: F06 agora separa “Não salvou” (422 com `error_fields`) de “Ainda respondendo” (409); F09 separa falha ao ligar e editor sem administrador; F13 nomeia código vencido (F0:208-223). A regra de sucesso, vazio, loading e persistência vindos da API/banco local, com `page.route` limitado a falha/atraso nomeado, também está preservada (F0:180-200, 223).

2. **Ferramentas com o ator correto — fechado.** A linha F11 usa explicitamente `super_admin` para a captura positiva, perfis sem essa permissão para ausência/401 e Lia para a aba oculta mesmo com sessão SuperAdmin (F0:197, 218-219). Isso coincide com o aceite e com CA-GERAL-10: quem só vê não escreve, editor não recebe Ferramentas e somente SuperAdmin recebe a permissão de plataforma.

3. **Retorno de Conte — fechado.** Conte não ficou limitado à entrada E1/E2: em E3/E4, “Quero mudar algo” retorna à edição preservando a mesma thread e os dados, invalida o teste atual e exige novo teste válido antes de Ligue (F0:83-93). E5/E6 não são convertidos em rascunho. A regra coincide com o PRD/aceite sobre mudança antes de ir ao ar e não cria atalho de escrita para quem só vê.

## Permissões e jornada

O mapa mantém a separação entre o gate antigo e o gate aditivo do redesign, conserva conta/agente/thread no escopo e define os fallbacks com o leitor B3/BE-05 antes do legado, sem `start` ou nova thread (F0:126-148). A fixture viewer usa o caminho “Abrir”/leitor e a exceção documentada de teste de leitura; não recebe criação, retomada, edição, Ligue ou controles das abas de gestão (F0:158, 194-200, 209, 214, 218; PRD:861-864, 912-914, 1066-1069). As fixtures `editor_a`, `account_admin_a`, `super_admin` e `viewer_b` cobrem edição, conexão, Ferramentas e isolamento entre contas.

A jornada tem quatro itens na barra — Escolha, Conte, Teste e Ligue — e Pronto como conclusão em `ready`, sem quinta etapa (F0:43-54). Os estados E1–E6, abandono, retomada e a distinção entre E4, E5 e E6 estão ligados a dados e leitores reais, sem inferência por texto (F0:83-93, 208-223). O mapa também mantém as correções já fechadas para origem canônica de conexão, locale único, foco do SidePanel, n-navy, Guia/Central e axe executável (F0:43-71, 137-148, 178-187, 225-248).

## Conclusão final

**PASS final do desenho F0, sem residual para retornar ao Rodrigo nesta revisão.** O próximo bloqueio legítimo é de implementação/validação: a matriz ainda precisa ser executada nas telas reais, em quatro combinações de viewport/tema, com os perfis e leitores definidos, antes do aceite. O documento continua DRAFT até essa evidência e a aprovação explícita do Rodrigo.
