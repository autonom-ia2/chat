# Instagram: reutilizar a página Meta com resposta atual

Rodrigo aprovou reaproveitar a página carregada e validar a mudança no piloto com recursos reais antes de merge/deploy. A issue995, branchcodex/995-manager-route-crash e PR1163 continuam sendo o mesmo trabalho.

## Desenho aprovado

O manager já mantém uma única Page no perfil Chrome isolado. A alteração evita navegar novamente nas ações de leitura, preservando o contexto, cookies legítimos e proxy. A consulta RolesTable_Query permanece estritamente validada por docId/appId/businessId/adminId e envia uma requisição nova dentro do próprio Chrome. A resposta anterior não é usada para produzir accepted, pending ou absent.

A âncora usa apenas o request natural validado e o vínculo com a Page/configuração, guardados em memória. Navegação, fechamento, mudança de configuração e erros invalidam essa âncora. O convite continua usando seu caminho natural de navegação, seleção e permit. A busca precisa obter resposta atual e um typeahead natural novo, com input e alvo validados.

## Execução e propriedade

- [x] Registrar medição anterior completa: busca13.228/12.403/8.845ms e status9.204/8.066/7.442ms; gate10x reprovado.
- [x] Autorizar escopo de reutilização da página e teste espelhando produção; nenhum merge/deploy autorizado pelo sucesso de teste isolado.
- [x] Iris: implementar menor contrato de âncora/reutilização em scripts/instagram_testers/browser-operations.mjs e testes locais de request atual, UI e invalidação.
- [x] Root: integrar âncora após refresh/CAS válido em scripts/instagram_testers/session-manager.mjs, preservando ciclo/cleanup e exclusividade do perfil.
- [x] Atlas/Nexo: revisar requests/headers/cancelamento, freshness e impossibilidade de convite sem permit.
- [x] Executar testes Node e Chrome/proxy HTTPS local com status que muda entre operações, username repetido/diferente, token vencido, erro401/403, dados incompletos/conflitantes, cancelamento, página fechada e nova navegação.
- [x] Gerar pacote isolado somente após testes, com hashes de cada fonte e quota de publisher200% equivalente ao serviço atual.
- [x] Rodar novo piloto: API real, mesma fila/Redis/AWS, perfil legítimo exclusivo na VPS, três pares busca/status e handoffURL sem seguir OAuth. Medir HTTP, fila/claim, executor, requests críticos e publicação.
- [x] Reconciliar exatamente os seis hashes em claim/executor/complete; provar resposta nova por operação e zero navegações extras no warm path.
- [x] Provar fila zero; parar units próprias; restaurar manager anterior, oito units, quotas, PIDs dos outros sete e socket/CURRENT; salvar evidência sanitizada antes de remover apenas arquivos próprios.
- [x] Atualizar auditoria/PR/Project. Gate busca≤8096,6ms e status≤4250,6ms em todas as amostras; handoff sem novo browseroperation.

## Restrições

Sem clone de perfil/cookies, prompts completos, tokens, headers ou bodies na auditoria. Sem login novo, convite novo, DM, inbox, alteração de aplicação AWS ou OAuth seguido. Nenhuma alteração em banco fora das operações reais autorizadas e expiração oficial necessária à recuperação. Sem CURRENT, merge ou deploy até validar desempenho e revisão.

## Validação local

Manager: 63 testes executados, 63 aprovados, 0 falhas. O teste da execução confirma a mesma Page, priming após CAS e limpeza de formBody ao encerrar. Esse teste isolado verifica o ciclo do manager; a prova de desempenho e os caminhos do executor estão registrados abaixo.

## Resultado final real

Três buscas: 6371/6271/4631ms; três status accepted: 3484/3397/3291ms. Todos passaram os limites históricos /10 no servidor. A observação do cliente ficou em 5657,927–7287,860ms para busca e 3573,445–4705,711ms para status; é outra métrica, com polling1000ms preservado.

O status no executor Chrome foi 486/427/474ms. Cada ação fez uma nova RolesTable_Query, zero goto extra, zero InvitePOST ou mutation. O handoff original levou140,284ms, sem nova operação de navegador. Não foi seguido OAuth. Perfil, CURRENT, socket, sete PIDs e recursos restaurados; arquivos próprios removidos.

380 testes Node e Chrome local adversarial passaram. Lint5arquivos sem erros. CI do novo commit ainda precisa terminar; conexão/reconexão completas permanecem fora da prova de latência.
