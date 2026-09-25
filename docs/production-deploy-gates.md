# Gates de deploy blue-green

Os deploys de produção das stacks Autonom.ia e Hub2You disparam
automaticamente em push na `main` **exceto** quando o push só altera
`.github/**`, `docs/**` ou arquivos `*.md`: mudança de workflow ou
documentação não consome a janela de rollback. Rollback continua
exclusivamente manual.

**Exceção:** `lib/operator_guide/**` (conhecimento do Guia da Plataforma),
`lib/central_de_ajuda/**` (Central de Ajuda), `config/onboarding/**` (trilha de
onboarding) e `app/**/*.md` (manuais que os agentes leem, como
`app/services/autonomia/insurance/quote_agent/instrucoes/`) são lidos pela aplicação em
runtime. Mesmo sendo `.md`/`.yml`, mudança nessas pastas **dispara** deploy;
sem isso, um PR que só atualiza o Guia nunca chegaria a produção (#486).

O filtro é `on.push.paths` com padrões avaliados em ordem (o último que casa
decide): `**`, `.*`, `.*/**`, `!.github/**`, `!docs/**`, `!*.md`, `!**/*.md`,
`app/**/*.md`, `lib/operator_guide/**`, `lib/central_de_ajuda/**`, `config/onboarding/**`. `paths-ignore` não aceita
reinclusão com `!`, por isso a troca.

Para executar um dos workflows à mão, o operador precisa:

1. selecionar a branch `main`;
2. escolher `deploy` ou `rollback`;
3. marcar `confirm_production=true`;
4. passar pelos gates configurados no Environment `production`.

Workflows:

```text
.github/workflows/deploy-autonomia-blue-green.yml
.github/workflows/deploy-hub2you-blue-green.yml
```

Histórico: a política manual entrou no PR #213 (2026-07-23), foi revertida para
deploy automático em push na `main` pelo PR #230 (2026-07-28) e voltou a ser
manual no PR #275 (2026-09-02), como pré-requisito do upgrade Chatwoot 4.17.1
(#274): o rollback blue-green tem um degrau só, então merge e deploy precisam
ser decisões separadas. Com as duas stacks em 4.17.1 (2026-09-03), o deploy
automático em push voltou, agora com `paths-ignore` para workflow e docs. Em
2026-09-19 o filtro virou `paths` para reincluir o Guia e a trilha (#486).

Regra operacional que permanece: a instância N-2 é terminada 5 minutos após
cada deploy bem-sucedido, logo só existe um degrau de rollback por stack. Antes
de um deploy com migration, tirar snapshot manual do RDS.

O corpo blue-green, as verificações de saúde e o rollback permanecem
inalterados. Esta política separa a aprovação de merge da decisão operacional de
alterar AWS, ECR, EC2, ALB e SSM.

Onde moram as variáveis de ambiente de produção, e o que não pode sumir delas:
[production-env-secrets.md](production-env-secrets.md).

## Cache do build

Cada stack guarda o cache das camadas no próprio ECR (tag `buildcache` no repositório `chatwoot-autonomia-prod`
de cada conta), com `type=registry` e `mode=max`. O modo `max` guarda também as etapas intermediárias do Dockerfile:
medido em 25/09, o `bundle install` da etapa `pre-builder` levava cerca de 19 dos 24 minutos do build porque o modo
`min` (cache do GitHub) não o guardava. O cache do GitHub não serve para isso: o repositório já passa do limite de
10 GB, e o modo `max` despejaria o cache dos testes a cada push; além disso, PR de fork lê esse cache, e o ECR não.

A etapa das gems é refeita quando `Gemfile`/`Gemfile.lock` mudam e também quando muda uma camada anterior a ela. A
imagem `node:24-alpine` não é fixada por digest, então uma republicação dela invalida o cache das gems mesmo com o
Gemfile igual. O ganho de ~19 minutos vale para a maior parte dos deploys, não para todos.

A tag `buildcache` ocupa uma das 10 imagens que a lifecycle policy do ECR mantém; como é regravada a cada deploy, ela
nunca é a mais antiga. As tags do repositório são mutáveis nas duas contas. `ignore-error=true` mantém o deploy de pé
se a gravação do cache falhar. O checkout usa `persist-credentials: false`: o `.git` entra no contexto do build (o
Dockerfile roda `git rev-parse HEAD`), e sem isso o token do checkout ficaria numa camada cacheada.

Voltar ao comportamento anterior: `cache-from`/`cache-to` com `type=gha`, `mode=min` e os escopos antigos
(`chatwoot-autonomia-prod-linux-amd64` e `chatwoot-autonomia-hub2you-linux-amd64`).
