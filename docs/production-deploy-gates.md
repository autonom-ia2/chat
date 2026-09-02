# Gates de deploy blue-green

Os deploys de produção das stacks Autonom.ia e Hub2You são exclusivamente
manuais. Merge ou fechamento de pull request não dispara deploy nem rollback.

Para executar um dos workflows, o operador precisa:

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
ser decisões separadas.

O corpo blue-green, as verificações de saúde e o rollback permanecem
inalterados. Esta política separa a aprovação de merge da decisão operacional de
alterar AWS, ECR, EC2, ALB e SSM.
