# Runbook: convite de testador Instagram (#910)

Use junto ao [guia do fluxo](../instagram-tester-onboarding.md),
[segredos de produção](../production-env-secrets.md) e [gates de deploy](../production-deploy-gates.md).
Este documento prepara uma operação futura; **nenhuma alteração de produção está autorizada**.
O coordenador registra o aceite e as evidências em `docs/audit/`, sem dados de clientes ou segredos.

## 1. Gate de publicação e ativação

A flag vem OFF; habilitar exige aprovação do Rodrigo e allowlist explícita de contas.
Merge, SSM, auth e deploy são ações sujeitas a essa aprovação.
Seguir Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback plan.

**Push de código na `main` dispara automaticamente deploy de Autonom.ia e Hub2You.**
`lib/operator_guide/**` também dispara deploy. Os workflows podem iniciar juntos;
não há garantia de deploy sequencial. As duas stacks precisam estar prontas antes do merge.
A flag controla a ativação do fluxo, não a publicação do código.

Antes do gate, preencher a matriz sem supor que Apps, businesses ou sessões são iguais ou diferentes:

| Item operacional | Hub2You | Autonom.ia |
|---|---|---|
| App pai Meta confirmado | PENDENTE | PENDENTE |
| Business correspondente confirmado | PENDENTE | PENDENTE |
| Nome exato do app exibido ao convidado | PENDENTE | PENDENTE |
| Relação com OAuthApp `INSTAGRAM_APP_ID` | PENDENTE | PENDENTE |
| `doc_id` corresponde ao adaptador atual | PENDENTE | PENDENTE |
| Sessão autorizada validada ao vivo | NÃO EXECUTADO | NÃO EXECUTADO |
| Contas permitidas aprovadas | PENDENTE | PENDENTE |
| Pedido mínimo autenticado/novo adaptador ao vivo | NÃO EXECUTADO | NÃO EXECUTADO |
| Aceite e OAuth real do perfil selecionado | NÃO EXECUTADO | NÃO EXECUTADO |
| Webhook e DM real, recebimento/resposta | NÃO EXECUTADO | NÃO EXECUTADO |
| SHA, saúde e ponto de rollback | PENDENTE | PENDENTE |

O probe anterior encontrou bloqueio da ferramenta. Não repetir nem delegar a chamada bloqueada.
Os critérios externos continuam abertos; POC e fixtures não os encerram.

## 2. Configuração exata

Fonte: `app/services/instagram/testers/configuration.rb` e `.env.example`.
Estas configurações novas são lidas diretamente de ENV; não ficam no cadastro público de InstallationConfig.

| Nome | Contrato |
|---|---|
| `INSTAGRAM_TESTER_AUTOMATION_ENABLED` | Só a string `true` liga; ausente/padrão `false` |
| `INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS` | IDs numéricos separados por vírgula; todos válidos; conta atual incluída |
| `INSTAGRAM_META_DEVELOPER_APP_ID` | ID numérico do App pai de papéis, não OAuthApp |
| `INSTAGRAM_META_BUSINESS_ID` | ID numérico do business usado no formulário/Referer |
| `INSTAGRAM_TESTER_APP_NAME` | Nome real e não vazio mostrado no aceite |
| `INSTAGRAM_TESTER_ROLES_DOC_ID` | ID numérico obrigatório da consulta observada, sem versão implícita |
| `INSTAGRAM_TESTER_SESSION_JSON` | Objeto JSON completo da sessão administrativa; segredo |

IDs: strings de 1–40 dígitos ASCII. Lista vazia ou com elemento inválido não habilita a conta.
`available` verifica formato/configuração, não faz teste de autenticação.
Preservar `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, versão OAuth e demais configurações existentes.
Não preencher nome, App, business ou clientes a partir de fixtures de teste.

Schema do JSON: somente `cookie`, `fb_dtsg`, `lsd`, `jazoest`, `user_id`, `user_agent`
e `extra_form`. Os seis primeiros são obrigatórios, strings não vazias de até 32 KiB,
sem CR/LF; `user_id` é numérico. É o usuário administrativo, não o `user_id` do OAuth.
`extra_form` é opcional e aceita somente strings válidas nas chaves:
`__aaid`, `__req`, `__hs`, `dpr`, `__ccg`, `__rev`, `__s`, `__hsi`, `__dyn`, `qpl_active_flow_ids`.
Campos/headers/endpoints arbitrários são recusados. Não publicar valores em PR, logs ou exemplos.

## 3. Preparar arquivo privado, offline

Ferramenta: `scripts/instagram_testers/prepare_session.py`, biblioteca padrão Python.
Lê um arquivo UTF-8 contendo **uma captura Chrome Copy as cURL como texto**.
Não executa cURL, shell, arquivos referenciados nem pedidos de rede.
A captura deve ser obtida pelo operador autorizado; não pedir credenciais ao cliente.

Salvar a entrada em local privado fora de Git; não usar argumento com conteúdo da captura.
O caminho abaixo é ilustrativo, não instrução de capturar ou alterar sessão de produção:

```sh
python3 -B scripts/instagram_testers/prepare_session.py \
  --input /private/tmp/instagram-operador/captura.txt \
  --output /private/tmp/instagram-operador/session.json
```

A ferramenta aceita POST explícito ou inferido do corpo, URL posicional/`--url`,
headers, cookie e formulário previstos pelo parser. Só admite HTTPS no host exato
`developers.facebook.com` e as três rotas do adaptador; não admite relay arbitrário.
GraphQL exige `RolesTable_Query` e `variables` contendo apenas `app_id` numérico string.
Confere `c_user` contra `__user` e LSD do header contra formulário.
A captura tem limite de 256 KiB; cada valor exportado, 32 KiB.

A saída exige diretório privado do usuário, criado com 700 quando necessário, fora
de qualquer árvore Git. Rejeita symlinks nos ancestrais; grava arquivo 600 com publicação atômica.
Arquivo existente só pode ser substituído com `--replace`, se regular e do usuário.
Sucesso é silencioso, retorno 0; erro retorna 2 com mensagem estática, sem imprimir captura.
Só exporta o schema da sessão; não exporta App/business/docID/alvo para configurar o produto.
Entrada e saída continuam sensíveis: manter no cofre/local privado segundo a política operacional.
Preparar o JSON não verifica se a sessão está válida ou quais campos mínimos funcionam ao vivo.

## 4. Entrega pelo SSM existente, somente após aprovação

Cada stack usa `/chatwoot/prod/env`, SecureString, na respectiva conta AWS.
O operador fornece o JSON completo em `INSTAGRAM_TESTER_SESSION_JSON` pela entrega
de segredos existente. O preparador não importa para SSM; este runbook não cria comando de importação.
Não rotacionar sessão, chaves ou credenciais de produção durante a implementação.

Após aprovação específica, aplicar atualização cirúrgica com o mecanismo operacional existente:

1. Preservar uma cópia privada conforme política de segredos e registrar apenas nomes de chaves.
2. Comparar o conjunto de chaves antes/depois; conservar todas as chaves preexistentes.
3. Alterar somente as configurações autorizadas para a stack correta; manter flag OFF no preparo.
4. Conferir carregamento/versão em runtime sem exibir valores e registrar evidência sanitizada.

Nunca reconstruir o parâmetro do zero. Preservar especialmente
`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
e `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`: perder/trocar essas chaves torna
credenciais existentes ilegíveis. O histórico limitado do SSM não substitui o cofre.
SSM cifra em repouso; JSON em ENV/runtime não é automaticamente cifrado pela aplicação.
Não há migration, infraestrutura ou dependência nova a preparar para #910.

## 5. Validação local e evidência

Usar ambiente de teste isolado; nunca Rails/RSpec com ENV ou banco de produção.
Inicializar rbenv e usar o wrapper de testes autorizado conforme AGENTS.md/MacCluster.
Escopo backend completo, incluindo caminhos legados, callback #898 e webhook:

```sh
bundle exec rspec spec/services/instagram spec/requests/api/v1/accounts/instagram \
  spec/requests/instagram spec/controllers/instagram \
  spec/controllers/api/v1/accounts/instagram spec/controllers/concerns/instagram_concern_spec.rb \
  spec/controllers/concerns/instagram_concern_security_spec.rb spec/helpers/instagram/integration_helper_spec.rb \
  spec/controllers/webhooks/instagram_controller_spec.rb spec/jobs/webhooks/instagram_events_job_spec.rb \
  spec/builders/messages/instagram spec/models/channel/instagram_spec.rb
pnpm test app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/TesterOnboarding.spec.js \
  app/javascript/dashboard/routes/dashboard/settings/inbox/channels/instagram/Reauthorize.spec.js \
  app/javascript/dashboard/api/channel/instagramClient.spec.js \
  app/javascript/dashboard/composables/spec/useAbortableRequest.spec.js
python3 -B tests/instagram_testers/test_prepare_session.py -v
pnpm i18n:fork:check
pnpm guia:build
pnpm guia:check
```

Coordenador executa geração/check do Guia e revisão final. Comandos listados não significam execução.
Navegador: seguir [README do harness](../../tests/qa/instagram-testers/README.md), com CSS do build
e Chromium existentes. Monta `Instagram.vue` e filhos reais com API simulada e tráfego externo
bloqueado; não é E2E completo. Manifest atual vincula screenshots ao código; zoom CSS não é zoom nativo.
Relatórios anteriores de teste/revisão não substituem revalidação de código posteriormente alterado.

## 6. Homologação futura e interrupção segura

Após autorização e desbloqueio operacional, o operador precisa validar por stack sessão/pedido mínimo,
adaptador atual, convite/aceite, OAuth do mesmo perfil, callback, webhook e DM real.
Usar perfil de teste autorizado; não remover/reconvidar cliente confirmado para obter evidência.
Verificar sem registrar bodies, cookies, headers, tokens, HAR ou dados de clientes.
OAuth usa `user_id` como `instagram_id` e `id` como `app_scoped_user_id`; não usar `uniqueID` de papel.

Em erro de status, não concluir ausência. Envio incerto exige consulta e respeita proteção de 24h;
não automatizar POST de retry, limpar marcadores manualmente ou revogar testadores para testar.
HTTP 401 permite `meta_session_expired`; outras falhas exigem diagnóstico, sem pedir senha ao cliente.

Para interromper ativação, após aprovação, desligar a flag e confirmar o runtime atualizado;
restringir a allowlist conforme decisão aprovada. Preservar caixas, tokens e conversas existentes.
Não excluir/revogar testadores ou canais automaticamente. Se houver regressão de código,
usar rollback blue-green manual aprovado na stack afetada e verificar ambas separadamente.
Só há um degrau de rollback por stack; confirmar sua disponibilidade antes da publicação.
CI verde, deploy iniciado e convite aceito não comprovam saúde nem funcionamento real de DMs.
