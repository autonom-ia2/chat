# #931 — deploy e recuperação: revisão P1/P2

Correção somente de código dos dois workflows blue-green, do helper `scripts/deploy/blue-green-recovery.sh` e de `tests/instagram_testers/deploy-recovery_test.py`. A revisão `tmp/instagram-931/review-runtime-deploy-result.md` reprovou a versão anterior por um P1 e dois P2. Esta versão aguarda nova revisão independente. Nenhum resultado aqui autoriza merge, deploy ou homologação de infraestrutura.

## Comportamento corrigido

- A instalação mantém os 13 passos obrigatórios encadeados com AND explícito. O padrão anterior `if ! ( set -e; ... )` engolia falhas 1–12 quando o último passo passava; a correção interrompe cada falha, limpa o staging e retorna erro.
- O helper lê envelopes reais em forma (`Listeners`, `TargetHealthDescriptions`) usando jq local. Exige um grupo com tráfego e uma instância na porta 3000. Aceita forward direto e o modelo existente de pesos 100/0; não escolhe primeiro alvo quando existem vários, não inventa blue e não adivinha bindings.
- Rollback valida PREVIOUS target→instância antes de iniciar EC2, enviar comandos SSM, parar o worker atual ou alterar o listener. Cleanup também valida o blue conhecido antes de mutar e interrompe se faltarem identificadores necessários.
- PREVIOUS é gravado a partir do par blue validado. Se qualquer resposta de escrita falha (inclusive depois de aplicar), as duas chaves são reparadas com aquele par, mantendo o erro original. Uma flag de tentativa permite ao cleanup reparar um erro parcial persistente quando a escrita volta a funcionar. Se o reparo ainda falha, a recuperação permanece vermelha e preserva recursos; um rollback que veja par divergente não altera estado.
- Deploy, rollback e cleanup conferem listener→target→instância antes de gravar CURRENT. Uma resposta de erro em modify-listener não prova que a troca foi rejeitada: o helper confirma o destino e os ponteiros e entrega o status original ao caller.
- Nos caminhos de recuperação, uma troca aplicada e confirmada permite completar start/wait do worker blue, depois devolver o erro original não zero. Se a confirmação ou os ponteiros falham, não se presume recuperação, não se inicia o worker escolhido e não se destroem recursos.
- As duas stacks param/aguardam o worker atual antes de retomar o anterior. Repetir rollback quando o destino já é o anterior não para o próprio worker restaurado. Os comandos SSM obrigatórios mantêm `set -eu`.
- Cleanup, no caminho confirmado sem erro, aguarda 30 segundos após CURRENT voltar a blue (o transporte declara orçamento de 25 segundos), depois desregistra green e aguarda `target-deregistered` antes de deletar o target group ou terminar a instância. Falha na espera mantém recursos. Uma recuperação com resposta de erro confirmada retoma blue e devolve o erro antes de remover green.
- Blocos SSO, permissions/env/roles/environments e preparação do overlay foram comparados com a base e preservados. Publisher, manager e `runtime-publisher.test.mjs` não foram editados por DEPLOY.

## Receipts sintéticos históricos — anteriores à correção de boot abaixo

Todos os comandos de infraestrutura usados nos testes são falsos, com ambiente mínimo e temporários isolados. O teste executa Bash dos workflows/helper, substitui os executáveis absolutos do bloco de instalação antes de executar e nunca executa user-data, bootstrap, instalador ou publisher reais. O fake valida serviço, operação, projeções SSM e envelopes ALB. Sleep apenas registra um marcador e avança tempo virtual; drenagem também é virtual. AWS, SSM, SSH, Docker e systemctl reais não foram executados.

Reprodução contra a versão existente **antes** destes novos fixes:

- `tmp/instagram-931/deploy-review-red.log`: 4 grupos, 17 failures, 40,492 s. Par divergente/ausente/ambíguo alterou o listener antes de falhar; falha na segunda escrita deixou PREVIOUS parcial; resposta perdida não retomou blue; remoção ocorreu em tempo virtual zero, antes dos 25 segundos de transporte.
- `tmp/instagram-931/deploy-review-before-hashes.json`: SHA-256 dos três arquivos de produto antes do fix. A reprodução rodou antes de editá-los.

Após os fixes:

- `tmp/instagram-931/deploy-review-green.log`: os mesmos 4 grupos passaram, 70,069 s.
- `tmp/instagram-931/deploy-review-retention.log`: 2 grupos focais passaram, 6,831 s; falhas de confirmação/drenagem e escrita persistente preservam recursos.
- `tmp/instagram-931/deploy-review-final.log`: suíte completa nova passou, **16 grupos, zero falhas, 150,713 s**, com `python3 -B tests/instagram_testers/deploy-recovery_test.py`. Os 10 grupos e o receipt do coordenador anteriores não foram usados como validação final desta versão.
- `tmp/instagram-931/deploy-review-final-hashes.json`: quatro fontes congeladas (helper, dois workflows e teste); os mesmos SHA-256 foram conferidos ao final, sem alteração durante a validação.
- YAML dos dois workflows, `/bin/bash -n scripts/deploy/blue-green-recovery.sh`, sintaxe de todos os run blocks/shell aninhado e `git diff --check` passaram.

A matriz final mantém todas as falhas obrigatórias anteriores e acrescenta reparo de PREVIOUS (sem sucesso após erro), zero mutações em par divergente/ausente/ambíguo, worker restaurado com exit original 77, falha de confirmação com recursos preservados, orçamento de transporte, drenagem e falha do marcador de espera. Não houve redução de coverage/gates.

## Integração e limites

Arquivo exato para CI: `tests/instagram_testers/deploy-recovery_test.py`. Comando: `python -B tests/instagram_testers/deploy-recovery_test.py -v`. A leitura atual de `.github/workflows/instagram-tester-onboarding.yml` já mostra o step incluído pelo coordenador. DEPLOY não editou esse workflow; leitura do wiring não é execução nem aprovação do CI.

As duas chaves SSM não são uma transação. Erros persistentes podem impedir reparo, mas continuam falhando e não liberam mutações baseadas em par inválido. Estes receipts comprovam controle de erro e sequenciamento sintéticos; não comprovam conectividade, consistência temporal da AWS, semântica operacional da drenagem, serviços ou publicação em produção. Nova revisão independente posterior permanece obrigatória; sem commit, push, merge ou deploy nesta etapa.

## 2026-10-03 — P1 de autostart no boot: snapshot congelado para revisão

O item 1 de `tmp/instagram-931/review-integracao-result.md` é legítimo: a unit anterior habilitada podia iniciar Sidekiq em `start-instances`, antes da parada do atual. A suíte histórica de 16 grupos acima só modelava starts explícitos SSM e não comprovava essa exclusividade. Ela não é aceite do snapshot atual. A execução parent PID 62624 foi informada pelo coordenador como CANCELLED, sem aceite, e não é usada como PASS.

Fix mínimo nas duas stacks: após `validate_target_pair PREVIOUS`, parar e aguardar o worker atual, com guarda de instâncias diferentes, antes de consultar/iniciar a instância anterior. O bloco de parada foi apenas movido; payloads, unit e configuração produtiva ficaram iguais. O helper permanece byte a byte igual. A reversão apenas dessa movimentação em memória reproduziu os SHA-256 anteriores dos dois workflows; SSO, permissions, secrets, overlays, deploy-existing e demais invariantes anteriores não sofreram mudança nesta rodada.

O fake agora modela autostart de unit habilitada em EC2 start, mantém workers ativos e registra eventos de conclusão SSM. Submeter stop não remove o worker ativo; somente o `wait command-executed` concluído o remove. O teste exige a sequência stop concluído → boot start, zero sobreposição nas duas stacks, e comprova que falha no envio/espera da parada impede boot/listener/ponteiros. Repetir rollback para a mesma instância não para o worker restaurado. Par PREVIOUS divergente/ausente/ambíguo mantém zero mutações inclusive com autostart habilitado.

Receipts exclusivamente sintéticos:

- `tmp/instagram-931/deploy-boot-red.log`: 3 grupos contra workflows antes do fix, **12 falhas**, 12,732 s. O evento de boot registra blue e green ativos simultaneamente.
- `tmp/instagram-931/deploy-boot-before-hashes.json`: hash dos workflows/helper pré-fix e do teste de reprodução já preparado.
- `tmp/instagram-931/deploy-boot-green.log`: **9 grupos focados aprovados**, zero falhas, 45,610 s. Inclui os mesmos 3 grupos, mesma instância, validação PREVIOUS, erro de switch aplicado e confirmado, falha de confirmação/drenagem, orçamento de publisher e parsing de todos os shells.
- `tmp/instagram-931/deploy-boot-final-hashes.json`: quatro fontes idênticas antes/depois da validação. SHA-256 do manifesto: `5f3b2df58b18dbadafcc477cd4ab38618f4c379a84323bb3a81c8fb45575de79`.
- `tmp/instagram-931/deploy-boot-receipt.json`: comando exato, hashes e limites desta execução. `/bin/bash -n` do helper e `git diff --check` aprovados.

Gap de disponibilidade conservado e testado: se EC2 start falhar antes de aplicar, o atual já está parado e o anterior permanece desligado. Se a resposta do boot se perder depois de aplicar ou `instance-running` falhar, o anterior pode estar ativo, mas não foi confirmado. Em todos esses casos o rollback devolve 77, não muda listener/CURRENT, não termina instâncias e não apaga target group. Não tenta escolher/reiniciar outro worker sob incerteza. Será necessário diagnóstico/recuperação com autorização própria; este fix não promete recuperação automática de falha do boot.

Arquivo exato de CI permanece `tests/instagram_testers/deploy-recovery_test.py`; o wiring observado pertence ao coordenador e já usa esse arquivo. São agora 19 grupos disponíveis, sem redução dos anteriores. A suíte completa não foi repetida nesta rodada: coordenador executará após este congelamento. Nova revisão independente posterior obrigatória permanece **PENDENTE**, sem aceite conjunto, CI final ou homologação de infraestrutura. AWS/SSM/SSH/SSM agent/Docker/systemctl reais não executados; nenhum commit, merge ou deploy. Nenhuma edição em publisher/manager/runtime-publisher.test.mjs ou em arquivo de outro agente.
