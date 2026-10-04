# Runbook: onboarding Instagram Tester (#910 / PR #913)

Este runbook prepara a operação. Merge, deploy, configuração de produção, segredos,
auth e infraestrutura exigem aprovação explícita do Rodrigo. Não executar a chamada
Meta anteriormente bloqueada por outra ferramenta, host, proxy ou agente.

## Gate antes de publicar

Push na `main` dispara deploy automático de **Autonom.ia e Hub2You**. A flag OFF
controla a ativação, não impede a publicação do código. Seguir Issue → Branch → PR →
Project update → Review → Approval → Merge → Deploy/Rollback.

| Evidência necessária | Autonom.ia | Hub2You |
|---|---|---|
| App pai, Business, administrador e nome do app conferidos | PENDENTE | PENDENTE |
| Relação do App pai com `INSTAGRAM_APP_ID` OAuth e isolamento do fluxo legado conferidos | PENDENTE | PENDENTE |
| Namespaces de instalação diferentes e binding de tester conferidos | PENDENTE | PENDENTE |
| `doc_id` observado na interface autorizada corresponde ao adaptador | PENDENTE | PENDENTE |
| Proxy Static Residential Direct e opções de substituição conferidos | PENDENTE | PENDENTE |
| Mesmo Redis TLS de coordenação acessível pelas duas stacks | PENDENTE | PENDENTE |
| Perfil dedicado, volume protegido, gestor supervisionado e alertas | PENDENTE | PENDENTE |
| Sessão gerenciada publicada/renovada ao vivo sem redeploy | NÃO EXECUTADO | NÃO EXECUTADO |
| Convite, aceite, OAuth, callback, webhook e DM reais | NÃO EXECUTADO | NÃO EXECUTADO |
| Allowlist aprovada, SHA, saúde e ponto de rollback | PENDENTE | PENDENTE |

O código Terraform define ElastiCache separado em `infra/aws-chatwoot/main.tf` e
`infra/aws-chatwoot-hub2you/main.tf`. Isso não prova o runtime atual. Não presumir
Redis comum: configurar e verificar a conexão de coordenação explicitamente.
As sessões ficam no Redis local de cada instalação, cifradas com a chave existente;
a conexão comum contém somente locks/resultados de convite, sem cookies ou OAuth.

## Configuração do backend

Entregar no SecureString separado `/chatwoot/prod/instagram-tester-env`, sem
reconstruir `/chatwoot/prod/env`. O workflow aplica esse overlay como segundo
env-file, aceita somente as 13 variáveis backend da tabela abaixo e rejeita
duplicatas; não executa seu conteúdo como shell. Sessão JSON, usuário/senha de
proxy e variáveis do gestor não são permitidos. Ausência do parâmetro mantém a configuração
legada; falha de permissão ou configuração inválida interrompe o deploy.
Antes de publicar o workflow, conceder ao role EC2 somente os dois ARNs de leitura
novos declarados em IaC, sem apply amplo. O parâmetro base continua intacto.
Essa integração operacional é suportada pelo workflow blue-green. Os templates
Terraform de bootstrap direto não instalam o overlay/publisher; não usar recriação
fora desse workflow para uma instalação com a funcionalidade ativa.
Preservar todas as chaves, especialmente `SECRET_KEY_BASE` e as três chaves
`ACTIVE_RECORD_ENCRYPTION_*`. Nunca trocar essas chaves para preparar este fluxo.

| Configuração | Uso |
|---|---|
| `INSTAGRAM_TESTER_AUTOMATION_ENABLED` | Padrão OFF; somente `true` habilita |
| `INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS` | Allowlist de contas, todos os IDs válidos |
| `INSTAGRAM_META_DEVELOPER_APP_ID` | App pai de papéis, distinto do conceito de OAuthApp |
| `INSTAGRAM_META_BUSINESS_ID` | Business da página autorizada |
| `INSTAGRAM_TESTER_APP_NAME` | Nome real exibido ao convidado |
| `INSTAGRAM_TESTER_ROLES_DOC_ID` | Consulta `RolesTable_Query` legitimamente observada |
| `INSTAGRAM_TESTER_SESSION_SOURCE` | `managed` obrigatório em produção |
| `INSTAGRAM_TESTER_SESSION_NAMESPACE` | Identificador estável e exclusivo por instalação |
| `INSTAGRAM_TESTER_ADMIN_USER_ID` | Administrador autorizado; deve bater com `c_user` e `__user` |
| `INSTAGRAM_TESTER_PROXY_AUTH_MODE/HOST/PORT` | `ip` obrigatório, IPv4 Direct fixo e IP de saída autorizado; sem usuário/senha |
| `INSTAGRAM_TESTER_COORDINATION_REDIS_URL` | Mesmo endpoint `rediss://` autenticado nas duas stacks |

`INSTAGRAM_TESTER_SESSION_JSON` continua exclusivamente para preparação/teste
sintético; produção não volta a essa ENV quando o store está indisponível.
Nenhuma dessas informações privadas é enviada ao frontend. `available` é uma
checagem local de configuração/sessão, não comprovação de autenticação Meta.
OAuth/reautorização existentes usam suas configurações originais e não passam pelo
proxy administrativo. Os tokens novos de seleção/tester OAuth são vinculados ao
namespace de instalação, que deve ser diferente nas duas stacks; um token da outra
stack é rejeitado antes de consumir o nonce. Tokens antigos de tester sem o claim
precisam reiniciar a busca; o formato do JWT legado permanece preservado.
Refresh do token OAuth **não renova cookies administrativos**.

## Gestor separado e navegador dedicado

O repositório não instala um navegador operacional nem ativa o gestor no host.
O gestor é um processo separado com Node/Playwright fixados pelo lock existente,
perfil privado fora de Git, volume protegido e supervisão/monitoramento existentes.
Preparar esse runtime e entregar segredos é etapa operacional sujeita a aprovação.
Não reutilizar o Chrome pessoal, nem copiar seus cookies ou perfil.

No ambiente aprovado do gestor, definir as configurações App/Business/administrador/
consulta/proxy acima e:

- `INSTAGRAM_TESTER_BROWSER_PROFILE`: caminho absoluto, diretório do usuário com
  permissão 700, sem symlinks e fora de qualquer árvore Git.
- `INSTAGRAM_TESTER_PLAYWRIGHT_MODULE`: caminho absoluto do `index.mjs` de Playwright.
- `INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON`: lista de argumentos para executar o
  publisher no runtime Rails aprovado da instalação. Sem shell ou credenciais nos
  argumentos. Exemplo estrutural: `['bundle','exec','rails','runner',
  'scripts/instagram_testers/session_publisher.rb']` em JSON válido (aspas duplas).
  Num host separado, usar o transporte de execução operacional já autorizado,
  com stdin preservado; não criar endpoint público para publicação.

O transporte fornecido em `scripts/instagram_testers/runtime/publisher-tunnel.mjs`
usa SSH com comando forçado por túnel SSM, valida conta AWS e consulta o ponteiro
blue-green atual a cada publicação. Não abre porta SSH pública. A chave privada
dedicada fica fora de Git no gestor; somente sua chave pública é entregue pelo
parâmetro String `/chatwoot/prod/instagram-tester-publisher-public-key`.
Os workflows instalam o publisher a partir da imagem antes do cutover, inclusive
com a funcionalidade OFF quando há chave pública configurada. Não colocar o usuário
publisher no grupo Docker. Os arquivos LaunchAgent/wrapper são templates: adaptar
caminhos absolutos, PATH e bindings reais antes de instalar; template não é serviço
em execução.

**Inicialização/recuperação somente pelo operador autorizado:**

```sh
node scripts/instagram_testers/session-browser.mjs
```

Quando os bindings ainda estão sendo conferidos, `--initialize` abre somente a
página inicial do Meta Developers com proxy validado. Não inventa App, Business,
administrador ou doc_id. A seleção explícita `channel: 'chrome'` usa Google Chrome
instalado com o perfil dedicado, sem reutilizar o perfil pessoal. O runtime local
operacional fixa Playwright 1.59.1, conforme o lock de `tests/playwright`.

Abre uma janela dedicada pelo mesmo proxy. O humano conclui login e 2FA e fecha a
janela. Não há coleta de senha, tentativa automática de login ou bypass de desafio.
Depois, o processo supervisionado executa:

```sh
node scripts/instagram_testers/session-manager.mjs
```

A cada 15 minutos abre a página legítima de papéis e observa somente a consulta
`RolesTable_Query` emitida pelo navegador. Não fabrica/reexecuta uma captura e não
faz convites. Só permite GET/HEAD e o POST GraphQL exato configurado; outros métodos
e operações são bloqueados. Confere administrador, App, Business, `doc_id`, LSD e resposta completa
antes de publicar a sessão por stdin. Não grava captures, screenshots, HARs ou bodies.

O backend cifra cada payload antes de trocar o ponteiro ativo com WATCH/MULTI.
A publicação exige a versão anterior esperada e captura atual; dois publicadores
concorrentes não sobrescrevem a mesma geração. Cada request usa um único snapshot
para cookie, headers e formulário. Validade máxima de seis horas, imposta pelo servidor.
Falha de candidato/publicação mantém a sessão anterior ainda válida. HTTP 401/403
invalida somente a geração rejeitada por decisão conservadora: 403 também pode ser
permissão/bloqueio e não comprova expiração. Login/2FA/desafio param o gestor e exigem operador.
Não reativar sessão antiga nem repetir convite após resultado ambíguo.

Saídas do gestor têm somente códigos estáticos de falha/recuperação. Integrar ao
monitoramento existente e provar o alerta em homologação; código de evento/log não
é evidência de alerta entregue. Lock local impede gestor e janela manual simultâneos.
Após crash abrupto, remover o lock somente depois de verificar que não existe outro
processo usando o perfil. Nunca remover automaticamente um lock possivelmente ativo.

## Proxy fixo e interrupção segura

Usar o `proxy_address` e `port` de **Direct** da lista Static Residential e
configurar `INSTAGRAM_TESTER_PROXY_AUTH_MODE=ip`. O código rejeita hostnames/backbone
(`p.webshare.io`), não roda listas, não muda endpoint por request e não cai para
acesso direto. Nesse modo não há `username`/`password`: o IP público de saída de
cada host autorizado (backend e gestor) precisa estar cadastrado na autorização por
IP do fornecedor no plano Static Residential correto. A documentação permite
selecionar um plano específico; não presumir que o plano padrão seja o escolhido.
Não alterar essa autorização sem aprovação. Falha 407 é controlada; timeout de escrita permanece
`invite_unknown`, pois não prova que o convite não foi enviado.

Conferir no console autorizado se Auto-Replace/Auto-Refresh podem trocar o endpoint.
Não alterar assinatura nem opções automaticamente. Uma substituição real exige
reconfiguração aprovada, nova vinculação da sessão e validação do mesmo IP no gestor
/backend. A documentação oficial descreve [Direct](https://apidocs.webshare.io/proxy-connection)
e o modo [IP Authorization](https://apidocs.webshare.io/ipauthorization). Também
explica que [Auto-Replace pode substituir proxies](https://help.webshare.io/en/articles/9196557-understanding-the-auto-replace-feature).
O runtime rejeita modo ausente, Basic e qualquer usuário/senha; não há caminho de
credencial HTTP no gestor. Não configurar Basic como atalho.
Não usar proxy para contornar bloqueio de ferramenta, login ou desafio Meta.

## Testes seguros e homologação

Os testes Ruby devem usar snapshot MacCluster e serviços isolados conforme AGENTS.md.
Nunca herdar ENV/DB de produção. Os testes de parser, sessão, CAS, concorrência,
expiração, revogação e proxy usam dados sintéticos; CONNECT/timeout usam apenas loopback.
Python/Node e browser QA também não fazem chamadas Meta. O CI dedicado falha em erro,
sem `continue-on-error`. Ver resultados reais em `docs/audit/`, vinculados à revisão.

A [jornada do usuário](../instagram-tester-jornada-910.md) e os screenshots mostram
componentes/CSS reais com backend sintético. Não são homologação da Meta nem captura
do console externo. Essa validação externa continua pendente até estar autorizada e
operacionalmente desbloqueada, sem repetir a chamada anteriormente bloqueada.

Após autorização, homologar por stack com perfil de teste: sessão/proxy/renovação,
busca/convite/aceite, OAuth do mesmo perfil, callback #898, webhook e DM de ida/volta.
Não reconvidar ou revogar cliente confirmado para obter evidência. Não registrar
cookies, senhas, headers completos, bodies, tokens, HARs ou dados de clientes.

## Deploy e rollback

Antes de merge: revisar commit final e CI, screenshots, matriz acima, allowlist e
rollback das duas stacks; obter aprovação explícita. Manter flag OFF no preparo.
A flag não impede o deploy automático da `main`.

Na ativação inicial somente Hub2You/conta 18, manter Autonom.ia OFF e usar coordenação
local apenas enquanto há uma única stack ativa. Para ativar ambas com App
compartilhado, verificar um Redis comum e o isolamento OAuth legado antes. Cada
novo host green recebe IP de origem novo: autorizá-lo no Webshare antes de habilitar
o onboarding; a autorização do host blue não comprova acesso do green.

Para interromper ativação, desligar flag/allowlist no runtime aprovado e parar o
gestor. Preservar caixas, tokens, conversas e papéis existentes. Não limpar marcadores
de convites incertos: respeitar reconciliação e proteção de 24 horas. Em regressão de
código, rollback blue-green aprovado por stack, verificando SHA, saúde e DM novamente.
Não restaurar sessão invalidada como rollback. CI verde ou deploy iniciado não provam
funcionamento real do Instagram.
