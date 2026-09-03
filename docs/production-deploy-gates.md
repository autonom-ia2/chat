# Gates de deploy blue-green

Os deploys de produção das stacks Autonom.ia e Hub2You disparam
automaticamente em push na `main` **exceto** quando o push só altera
`.github/**`, `docs/**` ou arquivos `*.md` (`paths-ignore`): mudança de
workflow ou documentação não consome a janela de rollback. Rollback continua
exclusivamente manual.

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
automático em push voltou, agora com `paths-ignore` para workflow e docs.

Regra operacional que permanece: a instância N-2 é terminada 5 minutos após
cada deploy bem-sucedido, logo só existe um degrau de rollback por stack. Antes
de um deploy com migration, tirar snapshot manual do RDS.

O corpo blue-green, as verificações de saúde e o rollback permanecem
inalterados. Esta política separa a aprovação de merge da decisão operacional de
alterar AWS, ECR, EC2, ALB e SSM.
