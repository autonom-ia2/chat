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

O corpo blue-green, as verificações de saúde e o rollback permanecem
inalterados. Esta política separa a aprovação de merge da decisão operacional de
alterar AWS, ECR, EC2, ALB e SSM.
