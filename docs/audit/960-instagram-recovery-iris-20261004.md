# Recuperação Instagram — Íris, 04/10/2026

Correção local dos dois workflows: recuperação automática/manual suspende o
assistido no alvo com `INSTAGRAM_TESTER_AUTOMATION_ENABLED=false`, somente no
`instagram-tester.env`. Não altera ENV base, Redis, state ou outcomes. Reinicia
web/worker com o processo/imagem anteriormente publicado. Alvo sem
`igcoord/check.sh` é suportado; recuperação não chama check de Redis/proxy.

O helper vem do checkout do workflow via payload SSM. Para unidade antiga sem
overlay, acrescenta esse env-file ao comando publicado por override systemd,
preservando imagem/argumentos. Valida ambos os comandos antes de escrever.
Suspensão falha explicitamente antes de parar o último worker se o alvo estiver
ligado. Alvo desligado precisa iniciar após parar o worker atual para preservar
exclusividade; nesse caso, a suspensão só pode ser validada depois do boot.
O preflight rígido GREEN antes de parar BLUE no deploy normal foi preservado.

Validação exclusivamente offline: testes substituem AWS/serviços por fakes;
helper executado somente contra diretórios temporários e systemctl falso.
Nenhum SSH, banco, commit, merge ou deploy executado. Demais arquivos em revisão
não foram editados.

## Comandos e resultados exatos

`python3 tests/instagram_testers/deploy-recovery_test.py` — exit 0:
```text
Ran 25 tests in 176.204s

OK
```

Após o início da suíte foram acrescentados dois controles e reforçada a
asserção de preservação do worker BLUE; os complementos foram executados:

`python3 tests/instagram_testers/deploy-recovery_test.py DeployRecoveryTest.test_old_blue_fallback_and_unavailable_coordinator_restore_general_services DeployRecoveryTest.test_suspension_failure_preserves_last_online_worker_and_reports_error DeployRecoveryTest.test_suspension_helper_preserves_published_process_base_env_and_outcomes DeployRecoveryTest.test_invalid_published_worker_aborts_suspension_before_writes DeployRecoveryTest.test_coordination_failure_cannot_shift_traffic_or_remove_resources` — exit 0:
```text
Ran 5 tests in 11.751s

OK
```

`python3 tests/instagram_testers/deploy-recovery_test.py DeployRecoveryTest.test_stopped_target_suspension_failure_never_reports_rollback_success` — exit 0:
```text
Ran 1 test in 1.712s

OK
```

`bash -n scripts/deploy/blue-green-recovery.sh` — exit 0, sem output.

`git diff --check -- .github/workflows/deploy-hub2you-blue-green.yml .github/workflows/deploy-autonomia-blue-green.yml scripts/deploy/blue-green-recovery.sh tests/instagram_testers/deploy-recovery_test.py` — exit 0, sem output.

Nenhuma evidência de execução em produção é atribuída a esses testes.
