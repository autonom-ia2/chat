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

As duas stacks montam a mesma imagem (`docker/Dockerfile`, `linux/amd64`) e dividem o cache do GitHub Actions no
escopo `chatwoot-prod-linux-amd64`, em `mode=max`. O modo `max` guarda também as etapas intermediárias do Dockerfile:
medido em 25/09, o `bundle install` da etapa `pre-builder` levava cerca de 19 dos 24 minutos do build porque o modo
`min` não o guardava. A etapa só é refeita quando `Gemfile`/`Gemfile.lock` mudam. `ignore-error=true` mantém o deploy
de pé se o cache falhar ou for despejado pelo limite de 10 GB do repositório. Voltar ao comportamento anterior é
trocar `mode=max` por `mode=min` e os escopos pelos antigos (`chatwoot-autonomia-prod-linux-amd64` e
`chatwoot-autonomia-hub2you-linux-amd64`).
