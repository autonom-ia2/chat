# #960 — fechamento da correção de publicação loopback, 04/10/2026

## Escopo desta retomada

Retomada no HEAD local `46afe5f7e16992caee4ea752a0f80f61557e53b9`, sem reinicializar o Redis dedicado. Preservadas as duas alterações locais preexistentes, no provisionador e seu teste. Nenhum merge, entrada na fila, deploy, transferência de credenciais, instalação de túneis ou alteração de Redis remoto foi executado nesta retomada.

Gauss revisou o diff de rede e aprovou sem ajuste obrigatório. Nexo conferiu CI/fila e apontou a descrição antiga de bridge interna no runbook; documentação corrigida. Íris conferiu o procedimento humano dos parâmetros e separou as provas já registradas da operação ainda pendente. Pareceres completos em `tmp/resume-1630-20261004/`, sem prompts ou credenciais publicados.

## Código publicado

- Bridge dedicada deixa de usar `--internal`, mantendo publicação explícita `127.0.0.1:6381` e `host_binding_ipv4=127.0.0.1`.
- O provisionador confere `NetworkSettings.Ports` antes de inicializar epoch/configurar SSH. Binding apenas solicitado não é prova de publicação efetiva.
- Publicação ausente, pública, duplicada ou adicional bloqueia a continuação e preserva recursos. Isso não é remoção automática de uma publicação incorreta já existente.
- Permanecem TLS, ACL, restrições SSH, limites de recursos e TTL aprovado. A bridge permite saída NAT; não é um filtro de destinos de saída.
- NEW ONLY continua recusando recursos existentes. **Não executar o provisionador no Redis já instalado.**

Publicação pelo conector nativo GitHub na branch isolada, após leitura dos resultados e aprovação de código. Blob do script: `89f63b3a634ca76f95c65fbcb8290a6dc17addbb`; blob do teste: `dca3f150c53b8c2231c156163d130ed56a5dc7b8`. Ambos coincidem com os blobs locais revisados/testados. Commits de código/teste: `26d3546de8fe1312ae4d68399bcc7b37171d6078` e `510ed5933da92c6a5a647e89a6499f98644da911`.

## Validação local desta rodada

Executada pelo coordenador com ambiente limpo e serviços externos simulados, às 16:34 UTC:

| Bateria | Resultado |
| --- | --- |
| Provisionador, incluindo publicação ausente e pública | 6 testes, zero falhas |
| Runtime de coordenação | 16 testes, zero falhas |
| Utilitário de parâmetros, somente mocks | 19 testes, zero falhas |
| Bash syntax e git diff --check | Exit 0 |

Recibo `tmp/resume-1630-20261004/local-checks.json` e logs correspondentes. Gauss fez revisão estática; estes resultados executados são do coordenador. Não comprovam criação de parâmetros AWS, túnel ou login Meta.

## Evidência operacional anterior preservada

`tmp/final-orchestration-20261004/network-repair-result.json` registra às 16:20:24 UTC reparo real da rede dedicada com TLS acessível pelo host, volume/epoch/credenciais e serviços existentes preservados. Não foi reexecutado nesta retomada. Evidências de persistência/ACL e proxy M4/n8n permanecem no relatório `960-final-orchestration-20261004.md`; não equivalem a prova AWS→n8n.

O último recibo de pré-condições lido ainda registra oito parâmetros AWS ausentes. Transferência automática anteriormente bloqueada não foi repetida nem emulada. O procedimento humano revisado está em `docs/runbooks/instagram-coordination-parameters.md`; verificar metadados primeiro, sem `--apply`, e só depois proceder com confirmação humana. Não pedir cookies ou credenciais pelo chat.

## Estado local e continuação

Após os testes e início dos revisores, novos comandos via terminal retornaram `Native routing blocked: enrollment outcome unavailable; no local replay`. Leituras continuaram disponíveis. Não foi usada outra execução local para repetir os comandos bloqueados. Código e documentação foram publicados pelo conector GitHub; **a worktree local permanece no HEAD anterior com as duas alterações preservadas**. Na próxima execução autorizada, comparar os blobs e reconciliar com a branch remota, sem reset destrutivo ou duplicar commits.

O CI precisa ser vinculado ao último SHA remoto, incluindo RSpec agregado, Vitest, trava, central, fork-i18n e checks Instagram. Não reaproveitar o resultado de `46afe5f7e1` como prova do novo SHA. Se houver falha de ordem, usar o `rspec-plan` da rodada; não reduzir assertions ou desabilitar checks. Enqueue não significa merge; somente estado `MERGED` e aprovação explícita permitem avançar.
