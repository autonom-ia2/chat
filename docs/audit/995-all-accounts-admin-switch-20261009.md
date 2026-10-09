# Issue 995 — Instagram assistido controlado por conta

## Regra confirmada por Rodrigo em 2026-10-09

Disponibilizar Instagram assistido para todas as contas da Hub2You e Autonom.ia. A marcação `instagram_assisted_onboarding` no console super admin escolhe o fluxo de cada conta. Ligado: busca, convite e confirmação de testador; depois, OAuth original do Chat2You/Chatwoot. Desligado: fluxo original diretamente, sem chamadas de testadores ou preparação de navegador na VPS. Preservar as marcações atuais das contas; disponibilizar não significa ligar todas.

Este plano substitui a liberação por IDs 16,18 e a restrição de publicação à Hub2You. Preservar as conexões existentes, inclusive a conta18, e as permissões de criação de caixas. As restrições existentes do canal Instagram e de incidente Meta continuam valendo.

## Configuração necessária

Nas duas instalações, manter `INSTAGRAM_TESTER_AUTOMATION_ENABLED=true` e publicar `INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS=` vazio no parâmetro SecureString `/chatwoot/prod/instagram-tester-env`. Não excluir a chave nem alterar outras linhas. A implementação atual aceita lista vazia como ausência de restrição por IDs, mantendo a marcação por conta. Não é necessário remover a proteção opcional do código.

Instagram.vue já escolhe o componente pela marcação da conta. O backend exige a mesma marcação; desligado usa autorização original sem seleção de testador. Reconexão de caixa existente segue o OAuth de reconexão, independentemente da marcação. Conta ligada com assistência indisponível apresenta indisponibilidade; não muda silenciosamente para o fluxo desligado.

## Evidência e limites

Leituras bem-sucedidas em produção: Hub2You, 15 contas (2 ligadas, 13 desligadas); Autonom.ia, 7 contas (2 ligadas, 5 desligadas). Com lista vazia simulada, zero divergências nas 22 contas. Atualmente apenas 1 conta por instalação passa pelo filtro de IDs. Web e worker das duas instalações carregam automação global=true e lista de IDs restrita, no SHA28e1e0ac8b3835577f7469368f03a86d1a8dab0d. Parâmetros estão nas versões16 (Hub2You) e8 (Autonom.ia). Isso comprova o controle de habilitação no código real; não comprova UI, sessão Meta disponível ou novo grant OAuth. Nenhuma mudança foi publicada.

A sonda roda em processo separado, em transação de banco READ ONLY; simula lista vazia apenas na memória, restaura o valor após cada conta e não grava configurações, contas, cookies, convites ou tokens. Só resultados agregados são registrados.

Os 4 contratos de configuração ENV e 12 contratos de gatilhos de deploy passaram nesta rodada. A tentativa de Vitest local não iniciou testes porque suas dependências estão ausentes neste worktree; não conta como aprovação. Casos existentes de UI ligado/desligado, troca de conta, payload OAuth original e reconexão passaram na CI anterior fb32568b52. Esses arquivos não mudaram no candidato atual; isso não substitui CI final.

GitHub Actions: c7c2e2afc9f6873380798aa9510ed65d44e75526 sem checks, PR aberto e BLOCKED. Último dispatch recusado com HTTP422, “Actions has been disabled for this repository”, apesar de enabled=true. Política da organização retorna403; causa administrativa não confirmada.

## Publicação e rollback

1. Liberar Actions, concluir CI da revisão final e passar pela fila nativa; confirmar MERGED. Sem bypass administrativo.
2. Preparar artefato Linux do SHA mergeado; com filas vazias, instalar e verificar VPS antes de expandir configuração AWS. Preservar templates idênticos, Node, perfis e overrides de CPU efetiva200%.
3. Registrar backup privado e versões dos dois parâmetros, conferir ausência de alterações concorrentes e editar somente a linha da lista de IDs para vazia. Se versão mudar, abortar e reler. Não registrar segredos em auditoria ou PR.
4. Publicar por blue-green nas duas instalações; não reiniciar diretamente web/worker. Conferir ENV efetiva em ambos os containers, marcas por conta, saúde, filas e CURRENT. Aproveitar deploy aprovado já correspondente para evitar duplicação.
5. Validar via API e UI: conta ligada usa assistência; desligada vai ao OAuth original; troca de conta descarta seleção; aceite termina na URL original; reconexão preserva a caixa. Login/2FA e grant Meta pertencem ao usuário. Não enviar convites ou mensagens para validar somente configuração.

Rollback: VPS retorna por CAS ao CURRENT anterior61f20cfd107361a431fda51f02cace751cc4978d, preservando perfis e overrides. AWS retorna somente à linha anterior de cada parâmetro, conservando alterações concorrentes e usando blue-green. Não alterar marcações feitas por Rodrigo ou outros operadores. Issue995 continua aberta até aceite funcional e reconexão real.
