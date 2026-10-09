# Issue 995 — Instagram assistido controlado por conta

## Regra confirmada por Rodrigo em 2026-10-09

Disponibilizar Instagram assistido para todas as contas da Hub2You e Autonom.ia. A marcação `instagram_assisted_onboarding` no console super admin escolhe o fluxo de cada conta. Ligado: busca, convite e confirmação de testador; depois, OAuth original do Chat2You/Chatwoot. Desligado: fluxo original diretamente, sem chamadas de testadores ou preparação de navegador na VPS. Preservar as marcações atuais das contas; disponibilizar não significa ligar todas.

Este plano substitui a liberação por IDs 16,18 e a restrição de publicação à Hub2You. Preservar as conexões existentes, inclusive a conta 18, e as permissões de criação de caixas. As restrições existentes do canal Instagram e de incidente Meta continuam valendo.

## Configuração necessária

Nas duas instalações, manter `INSTAGRAM_TESTER_AUTOMATION_ENABLED=true` e publicar `INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS=` vazio no parâmetro SecureString `/chatwoot/prod/instagram-tester-env`. Não excluir a chave nem alterar outras linhas. A implementação atual aceita lista vazia como ausência de restrição por IDs, mantendo a marcação por conta. Não é necessário remover a proteção opcional do código.

Instagram.vue já escolhe o componente pela marcação da conta. O backend exige a mesma marcação; desligado usa autorização original sem seleção de testador. Reconexão de caixa existente segue o OAuth de reconexão, independentemente da marcação. Conta ligada com assistência indisponível apresenta indisponibilidade; não muda silenciosamente para o fluxo desligado.

## Evidência e limites

Leituras bem-sucedidas em produção: Hub2You, 15 contas (2 ligadas, 13 desligadas); Autonom.ia, 7 contas (2 ligadas, 5 desligadas). Com lista vazia simulada, zero divergências nas 22 contas. Atualmente apenas 1 conta por instalação passa pelo filtro de IDs. Web e worker das duas instalações carregam automação global=true e lista de IDs restrita, no SHA 28e1e0ac8b3835577f7469368f03a86d1a8dab0d. Parâmetros estão nas versões 16 (Hub2You) e8 (Autonom.ia). Isso comprova o controle de habilitação no código real; não comprova UI, sessão Meta disponível ou novo grant OAuth. No preflight inicial, nenhuma mudança havia sido publicada; o resultado final consta abaixo.

A sonda roda em processo separado, em transação de banco READ ONLY; simula lista vazia apenas na memória, restaura o valor após cada conta e não grava configurações, contas, cookies, convites ou tokens. Só resultados agregados são registrados.

Os 4 contratos de configuração ENV e 12 contratos de gatilhos de deploy passaram nesta rodada. A tentativa de Vitest local não iniciou testes porque suas dependências estão ausentes neste worktree; não conta como aprovação. Casos existentes de UI ligado/desligado, troca de conta, payload OAuth original e reconexão passaram na CI anterior fb32568b52. Esses arquivos não mudaram no candidato atual; isso não substitui CI final.

Bloqueio inicial: GitHub Actions recusou dispatch comHTTP 422 apesar de enabled=true, e a política da organização retornou 403. O serviço voltou a executar após o push documentalcdd0591b; causa administrativa não confirmada. Vitest Instagram passou 104 testes; smoke Chrome Linux falhou em navegação de formulário e continua bloqueando a otimização PR1163. Esta falha não promoveu código candidato à produção.

## Publicação e rollback

1. Liberar Actions, concluir CI da revisão final e passar pela fila nativa; confirmar MERGED. Sem bypass administrativo.
2. Preparar artefato Linux do SHA mergeado; com filas vazias, instalar e verificar VPS antes de expandir configuração AWS. Preservar templates idênticos, Node, perfis e overrides de CPU efetiva 200%.
3. Registrar backup privado e versões dos dois parâmetros, conferir ausência de alterações concorrentes e editar somente a linha da lista de IDs para vazia. Se versão mudar, abortar e reler. Não registrar segredos em auditoria ou PR.
4. Publicar por blue-green nas duas instalações; não reiniciar diretamente web/worker. Conferir ENV efetiva em ambos os containers, marcas por conta, saúde, filas e CURRENT. Aproveitar deploy aprovado já correspondente para evitar duplicação.
5. Validar via API e UI: conta ligada usa assistência; desligada vai ao OAuth original; troca de conta descarta seleção; aceite termina na URL original; reconexão preserva a caixa. Login/2FA e grant Meta pertencem ao usuário. Não enviar convites ou mensagens para validar somente configuração.

Rollback: VPS retorna por CAS ao CURRENT anterior 61f20cfd107361a431fda51f02cace751cc4978d, preservando perfis e overrides. AWS retorna somente à linha anterior de cada parâmetro, conservando alterações concorrentes e usando blue-green. Não alterar marcações feitas por Rodrigo ou outros operadores. Issue995 continua aberta até aceite funcional e reconexão real.

## Release independente somente de configuração

A decisão por conta já existe no SHA 28e1e0ac, publicado nas duas instalações e aprovado nos checks obrigatórios. Revisão independente autorizou publicação somente de configuração nessa versão; o teste Linux vermelho continua bloqueando a otimização da PR1163. Esta atualização operacional substitui a exigência anterior de instalar o candidato VPS antes da configuração: preservar o runtime VPS 61f saudável sem alteração. Não promover qualquer código da PR1163.

Preflight: ambas as sessões disponíveis, filas zero, oito units ativas; parser oficial com chave presente e vazia validado nas 22 contas. Gravação alterou somente a linha da allowlist, preservando KMS/Tier/Description/metadados; Hub2You16→17 e Autonom.ia8→9, readback exato. SSM não tem CAS: houve lock local, conferência de versões antes/depois e ausência de deploy concorrente; não alegar atomicidade contra todo escritor externo. As tentativas via stdin falharam na validação dos parâmetros sem gravação; arquivo JSON temporário 0600 descartado resolveu o formato.

Deploys na main 28e1e0ac: [Hub2You37904867855](https://github.com/autonom-ia2/chat/actions/runs/37904867855) e [Autonom.ia37904870757](https://github.com/autonom-ia2/chat/actions/runs/37904870757). Concluídos com SUCCESS no mesmo SHA 28e1e0ac. ENV carregada em web/worker, saúde e continuidade VPS verificadas abaixo. Marcações admin não foram alteradas.

## Resultado final da configuração

Ambos os deploys concluíram com SUCCESS. Hub2You passou para i-061330f256a9d353c; Autonom.ia para i-0778723cd842e8e37. Web e worker nas duas instalações permaneceram no SHA 28e1e0ac e comprovam variável presente e vazia, automação global true. As 22 contas mantêm as marcações: Hub2You 2 ON / 13 OFF e Autonom.ia 2 ON / 5 OFF; agora as 4 ON estão habilitadas, sem divergências. Sessões disponíveis e filas zero. Não houve gravação de marcações nem convite/DM/grant Meta.

GET autenticado de configuração retornou 200, enabled=true/available=true nas contas 16 e 18 Hub2You e 1 Autonom.ia, usando credenciais já existentes, sem criação. Os dois painéis públicos retornam 200. Esses GETs comprovam disponibilidade da assistência; não são medições de busca/status nem prova de novo OAuth concluído. Os 104 testes focais de UI/OAuth/reconexão passaram na revisãocdd0591b.

VPS permaneceu em 61f20cfd com 8 units, mesmos PIDs, NRestarts e quotas. Rollback aponta para as instâncias anteriores i-0766dae3f3f99e4a6 e i-0dd78dbf247a21b12; valores anteriores dos parâmetros continuam nas versões 16/8. Arquivos temporários de requisição descartados; zero sobras. A otimização de velocidade da PR1163 não foi mergeada nem instalada.

Leitura final adicional da conta 18: mesmo canal e caixa 112, sem marca de reautorização, vencimento futuro e created_at/updated_at inalterados. Conta 16 permanece marcada como ligada e agora configuration.enabled=true. Isso preserva a conexão existente e libera o teste manual da conta 16.
