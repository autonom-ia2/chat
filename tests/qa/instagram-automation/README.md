# QA independente do painel Instagram — #950

## Preparação posterior às correções de produto

Esta preparação altera somente `server.rb` e `run.mjs`, com documentação aqui. Não inicia Rails, banco ou browser. A próxima sessão precisa de slot explícito do parent depois de RSpec/build; o histórico de 18 casos/179 asserções/16 PNGs permanece inalterado e não aprova estas fontes novas.

Capturas de queued/running/failed/succeeded rolam a região real de solicitação no `main` com scroll próprio, exigem o texto do estado e a região inteira dentro do viewport antes do PNG e usam screenshot de viewport. Capturas de identificadores e matrizes continuam separadas. Não se captura login. O heartbeat passa a comparar o `datetime` ISO3 do DOM diretamente com `LocalStatus.manager.observed_at`, sem obter o valor esperado do helper que renderizou a tela. EN/PT exigem ausência de `Translation missing` sem depender de maiúsculas.

O wrapper test-only responde somente ao caminho de dependência `/packs/js/sdk.js` com SDK de suporte explicitamente simulado: `chatwootSDK.run`, `$chatwoot.setUser` no-op e evento `chatwoot:ready`. O receipt declara `support_sdk_simulated=true` e conta os requests. Nenhum 404 é ignorado. A nova página deve provar seu optout: nenhum request adicional ao SDK e runtime `chatwootSDK` ausente após a navegação real. Isto não valida a integração de suporte externa. Não foi acrescentado caminho público para capability ou assets do harness.

A submissão inválida deve produzir uma resposta POST HTML 422 real e exatamente um diagnóstico Chromium 422 no URI/caso exatos. Eventos excedentes entram como erro fatal; nenhum filtro global de 422 ou pageerror foi adicionado. Form labels, textos de inputs, títulos e botões novos usam o compositor existente de `instagram-testers/visual-helpers.mjs`, com cores computadas, alpha, opacity e brightness: contraste mínimo 4,5. CSS não suportado falha. A medição é instrumentação de teste, sem alterar CSS/layout ou abrir rede.

O dispatch Ruby foi extraído em handlers de bootstrap, receipt, heartbeat, operator e publication, todos chamando os serviços reais. A única exceção de métricas é ABC da projeção de receipt; a exceção `Style/GlobalVars` cobre exclusivamente o pool exigido pelo adaptador real, neste processo de teste. Não há config global de lint. CLI JavaScript documenta execução serial de loops/await e stdout sanitizado; ternários aninhados e variáveis inválidas foram corrigidos, com Prettier somente no runner.

**Isolamento de etapas:** o browser usa o banco exclusivo #950, mas deixa os cinco `InstallationConfig` de metadata e os IDs sintéticos de conta/usuários/canal/inbox. Parent precisa resetar/recarregar o schema descartável entre browser e RSpec; apenas encerrar o server não restaura o banco. Os controles/session Redis ficam no namespace único `qa950-*` registrado no receipt, com TTLs de produto. Não há FLUSH, limpeza de banco compartilhado nem remoção de canais/outcomes. Nenhum cleanup é usado para tornar uma asserção verde; o parent coordena o reset fora deste harness.

As primeiras falhas históricas de boot pertenciam à fixture: factories duplicadas e senha aleatória sem garantia do caractere especial requerido. A criação atual usa prefixo com classes obrigatórias mais entropia aleatória; a senha permanece efêmera e não é publicada. Isso não altera regra de senha ou MFA de produto.

O runner abre Chromium headless existente, autentica pela página Devise real e percorre Settings → automação Instagram. O Rack isolado entrega Rails/ERB, controllers e serviços de produto reais; os assets vêm do build real em `public/vite-test`. Não há cópia da tela, bypass de login, instalação de dependências nem download de browser.

São 18 casos planejados. O número executado, cada asserção concluída e cada falha vêm de `tmp/950-integration/visual/results.json`. Planejamento e análise de sintaxe não contam como PASS de browser. Screenshots PNG reais ficam no mesmo diretório, ignorado pelo Git; não são evidência de produção ou E2E Meta.

## Execução serial pelo coordenador

O coordenador precisa terminar RSpec antes de disponibilizar `tmp/950-integration/browser-ready.json`. O marker apenas libera a janela de banco; o runner não o cria. Sem ele, grava `vega-ready.md` como READY/não executado e termina imediatamente. Exige PostgreSQL exclusivo `127.0.0.1:59510`, Redis exclusivo `127.0.0.1:59511/0`, schema já carregado e build `public/vite-test/.vite/manifest.json` já existente. Não prepara schema, banco, runtime ou build.

Execute da raiz, indicando os caminhos existentes neste computador:

```sh
PLAYWRIGHT_MODULE_PATH=/caminho/existente/node_modules/playwright \
PLAYWRIGHT_EXECUTABLE_PATH=/caminho/existente/chrome-headless-shell \
node tests/qa/instagram-automation/run.mjs
```

O runner inicia `tmp/950-integration/run-local.sh env ... ruby tests/qa/instagram-automation/server.rb`. O ambiente limpo pertence ao coordenador. Não passe `.env`, tokens ou credenciais de produção. O server bloqueia carregamento de dotenv antes de iniciar Rails, exige `RAILS_ENV=test` e `RACK_ENV=test`, valida o destino real do banco e usa capability aleatória só local. Não persista essa capability.

Puma escuta somente `127.0.0.1:39510`, falha se a porta estiver ocupada e tem startup limitado a 60 segundos. Cleanup termina exclusivamente o PID criado pelo runner. O Chromium usa contexto isolado e perfil temporário próprio, sem sessão pessoal, HAR, vídeo, protocolo trace ou export de cookies. Não iniciar o server manualmente sem o runner: ele exige capability efêmera e janela de banco autorizada.

## Fixtures e limites da evidência

Somente dados sintéticos são criados: SuperAdmin, administrador de `empresa_demo`, conta e canal Instagram. A senha é aleatória por execução, retorna apenas ao processo local e nunca entra no JSON/console/screenshots. O log local do servidor usa modo 0600 e não deve ser publicado. Rails/SQL/request logging é desligado antes das factories.

WebMock bloqueia todas as conexões remotas do processo Ruby. A factory do canal registra apenas resposta sintética da assinatura Meta. SMTP usa delivery `test`; ActiveJob usa adapter `test`. O Chromium bloqueia qualquer origem diferente de `http://127.0.0.1:39510`.

O wrapper `/__qa/` vive somente aqui, fora de `app/`, com hard guards de loopback/test/capability. Ele entrega fixtures de evidência do gestor usando `OperatorControl` real, com namespace Redis sintético único. Não limpa requisições, sessão ou outcomes para tornar um teste verde. A fixture de sucesso usa `SessionPublisher`/`SessionStore` reais com documento de roles e sessão totalmente sintéticos e criptografia efêmera. Nenhum serviço/controlador é reimplementado ou substituído por mock.

Os estados unknown, operador desconectado e heartbeat saudável são distintos de configuração e de saúde Meta. A reconexão precisa mostrar queued → running → failed ou succeeded de uma solicitação identificada. O sucesso local não comprova conexão externa. As transições são provocadas pelo wrapper de fixture; nenhum gestor real foi executado.

Desktop 1440×1000, mobile 390×844 e narrow 320×844 têm captura claro/escuro, overflow, alvos 44px e foco de teclado. O tema usa a classe `dark` já suportada pelos estilos reais e exige diferença de cor computada; não existe UI de troca de tema inventada. A conta é editada pela tela real, verificando persistência ON/OFF e preservação do canal/inbox existente. O administrador comum autentica pelo endpoint Devise real e continua bloqueado no SuperAdmin.

`results.json` contém HEAD, hashes das fontes e do build, checks individuais, receipts HTTP sem corpos/headers, screenshots e resultados. Console/page errors falham. A única exceção é o diagnóstico Chromium exato HTTP 422 da submissão HTML deliberadamente inválida, no path e caso exatos; ele permanece registrado como receipt esperado. Não ignore erros gerais para aprovar uma rodada.

## Rodada executada em 04/10/2026

Slot exclusivo no M4, três tentativas nesta autorização. As duas primeiras encerraram no boot: factories duplicadas (já carregadas por `factory_bot_rails`) e senha sintética sem garantia de caractere especial. Foram corrigidas somente no harness. A terceira executou **18 casos, 14 passaram, 4 falharam, 179 asserções verificadas e 16 PNGs**. Não houve quarta tentativa. Esses números descrevem as fontes e os hashes registrados em `results.json`, não as correções posteriores do runner.

Passaram o login Devise real, acesso via Settings, cinco campos/labels/distinção OAuth, save HTML/persistência, HTML inválido 422 sem gravação parcial (valor inválido substituído pelo salvo, edição válida preservada), CSRF ausente nas três ações, unknown/operador desconectado, health local, queued/running/failed/succeeded com publicação sintética via serviços reais e bloqueio do administrador comum. ON/OFF e preservação do canal/inbox foram verificados antes da falha de acessibilidade no mesmo caso.

Os bloqueios observados e reproduções ficam em `tmp/950-integration/visual/post-run-review.json` e `vega-ready.md`. Em 390px o painel teve 249px de overflow interno; em 320px, 319px, inputs de 30px e botões de 40px. A sidebar de produto permaneceu visível. Não há CSS de harness escondendo a navegação ou corrigindo a tela. O campo EE não tinha label associado; `/packs/js/sdk.js` respondeu 404 e permaneceu erro de console. A captura também mostra `Translation missing: pt_BR.date.month_names`; o check original de tradução era sensível a maiúsculas e não o detectou, portanto seu PASS não aprova datas traduzidas.

O caso de heartbeat falhou por um erro do harness: o atributo HTML usa `iso8601` em segundos, enquanto o source heartbeat guarda milissegundos. O runner atual compara com o helper de produto real e verifica separadamente o timestamp da leitura local. O diagnóstico esperado 422 foi atualizado para o texto exato observado no Chromium/Rack (`Unprocessable Content`); o 404 SDK continua fatal. O teste de tradução foi fortalecido para detectar `Translation missing` também. Esses ajustes tiveram somente validação de sintaxe nesta rodada, sem reclassificar nenhum FAIL anterior.

O runner agora registra receipts não secretos dos serviços, namespace/IDs sintéticos e dimensões reais dos PNGs; lê HEAD de arquivos locais sem executar Git. A sessão usa Redis real exclusivo para CAS/TTL, jobs:test, dotenv desativado e `CI=true` apenas neste processo para servir manifest build, sem procurar Vite de outro worktree. As screenshots de progresso atuais mostram a região superior do painel devido ao scroll interno de `main`: o DOM/protocolo foi verificado, mas esses PNGs não comprovam visualmente o texto de queued/running/failed/succeeded. A próxima execução, se autorizada, rola o componente real de status para a região visível antes da captura.

Após a terceira execução, os 425 hashes originais foram comparados com os arquivos em disco: nenhuma alteração durante a rodada. O check desse caso foi interrompido antes por erros de console; essa comparação posterior é registrada separadamente, sem aumentar as 179 asserções da execução. O server foi encerrado e a porta 39510 estava sem listener. O parent pode retomar RSpec/banco; o marker fica sob responsabilidade dele. Nenhuma tela de login/senha foi capturada, nenhum artefato representa produção e nenhum serviço externo foi homologado.

O runner termina com código diferente de zero em bloqueio ou caso falho. Parent mantém Issue/PR/Project/auditoria e decide correções, revisão visual, merge e deploy. Este diretório não altera produto nem faz commit.
