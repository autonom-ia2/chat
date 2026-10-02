# WAHA 2026.9.2 — publicação do lote5 e fechamento operacional

Data: 2026-10-02. Componente [#872](https://github.com/autonom-ia2/chat/pull/872),
release [#873](https://github.com/autonom-ia2/chat/pull/873), auditoria operacional
[#870](https://github.com/autonom-ia2/chat/pull/870). Issues #871 e #869.
Estado: **correção permanente publicada nas duas instalações; 25 caixas elegíveis do Hub2You conformes**.

## Autorização, escopo e revisão

Rodrigo autorizou concluir o tombamento/backfill de configuração do lote elegível do Hub2You e publicar
somente a correção permanente de Status nas duas instalações. A janela exclusiva foi confirmada para
as sessões restantes durante aplicação e eventual recuperação. Autonom.ia recebeu o código, sem backfill.
Sem UI, refatoração, schema, dependências, importação ou limpeza de histórico. R1–R5/N1–N3 preservados.
M4 identificado para Git, arquivos, AWS e demais operações com estado local.

O lote reutilizou release/2026-10-02-lote5; incluiu apenas #872, cinco arquivos permitidos.
#864 e demais componentes ficaram fora. Revisão independente do código: No issues, usando cavecrew.
Squash do componente f9fa2d11047c2396c830b7fd62f6b05f249b471c; árvore
31462ef7eff79c1663cf5ac8ece4fad7f7c0a1d4 idêntica à árvore local testada.
Main recebeu **um merge commit**: `0ee03e9be768fc77d7a3a5652002e4542b651878`, em 2026-10-02T22:59:52Z.
Os dois parents foram conferidos: main 0fec5c828af18f8cecde64eb15e1f5a86367c81c e o squash do lote.
Nenhum workflow_dispatch adicional de deploy foi enviado.
Revisão independente das auditorias: precisão documental corrigida e prova direta conferida; resultado final No issues.

## Validação anterior ao merge

Saídas completas lidas; testes e commit executados separadamente. Sem --no-verify.
Specs focados: 57 exemplos, 0 falhas. Regressão delimitada: 323 exemplos, 0 falhas, 3 pendentes antigos.
União do componente com a bateria fixa do release: **5587 exemplos Ruby, 0 falhas, 12 pendentes**,
0 erros fora dos exemplos; Vitest **133 arquivos, 1354 testes passando**.
Os 12 pendentes incluem três evals pagos desativados e nove quarentenas anteriores; não são testes passados.
RuboCop: três arquivos Ruby alterados, 0 infrações. git diff --check passou; hooks normais passaram.
Guia build/check: 174 fluxos, 171 telas, 0 sem explicação, sem mudança nos gerados.
Central check: 175 artigos, 171 telas; avisos anteriores de referências de linha preservados.
CI aplicável da #873 passou; jobs de Email fora do escopo foram SKIPPED, sem presumir execução.
Suítes locais usaram banco isolado; avaliações com provedores pagos permaneceram desativadas.

## Tombamento/backfill e proteção de recuperação

O lote configurou as 21 caixas restantes, completando 25 elegíveis; 63 comandos SSM Success/0,
zero skips/falhas/recuperações. A confirmação GET-only/READ ONLY anterior ao deploy validou as 25,
plano vazio, WORKING, filtro de Status ligado, sessões distintas e estado local inalterado.
Detalhes e limites em [auditoria do lote elegível](2026-10-02-waha-hub-full-eligible-batch.md).
As oito caixas excluídas ficaram sem APPLY; falha de consulta não identifica causa de autenticação.

58 arquivos before/after preservados fora da instância: 50 das operações finais e oito originais do
piloto/primeiras migrações. Transferência cifrada com AES-256-GCM/RSA-OAEP, autenticação, hashes internos
e comparação contra os hashes originais das operações conferidos. Diretórios 0700/arquivos 0600.
Credenciais, configuração completa, identidades exatas e backups não estão em Git/GitHub.
GET/PUT da WAHA permanece não atômico; N1 compara o snapshot e exige a janela exclusiva confirmada.
Não houve retry cego, restauração global ou remoção de Apps concorrentes.

## Deploy e prova direta de produção

Workflows automáticos, ambos SUCCESS no SHA `0ee03e9be768fc77d7a3a5652002e4542b651878`:

- [Hub2You: 37075390266](https://github.com/autonom-ia2/chat/actions/runs/37075390266).
- [Autonom.ia: 37075390103](https://github.com/autonom-ia2/chat/actions/runs/37075390103).

| Instalação | Nova instância | Instância anterior de rollback | WAHA conferida |
| --- | --- | --- | --- |
| Hub2You | i-085d5248762384f19 | i-0f5f268683059c096 | https://wa-hub.autonomia.site |
| Autonom.ia | i-0c63c73b9af1d2c15 | i-0e9bb7cb5e2a8a2c2 | https://wa-autonomia.autonomia.site |

Contas AWS separadas verificadas. Imagens atuais terminam no SHA publicado; targets healthy e listener
HTTPS direcionado ao target atual em cada instalação. Instâncias novas running e anteriores stopped.
Rollback anterior conserva imagem d28a87ad9b7264042a92823c5b6f4d04831d1713.
Provas SSM somente leitura: Hub2You `47509319-bbcd-43d9-82d1-b04ff7386ded`, Autonom.ia `309a2ba3-ff4a-4901-a288-b6126dcc2348`, ambas Success/0.
Web e worker ativos, containers running, Git SHA e imagem iguais ao release em ambos.
WAHA autenticada dentro de cada serviço: versão 2026.9.2, HTTP 200, endpoint próprio preservado;
API local HTTP 200. Nenhuma chave foi exibida no resultado dessa verificação ou publicada.
Saúde pública em 2026-10-02T23:15:10.273636+00:00: /api HTTP 200 nas duas, versão Chatwoot 4.18.0,
queue_services=ok e data_services=ok.

Conferência final das 25 caixas no runtime novo: SSM `b63943a9-9a40-4662-9a24-ee5f7265e7dd`, Success/0,
2026-10-02T23:16:24.016Z–2026-10-02T23:17:15.016Z.
Todas unchanged=1, would_update=0, WORKING, filtro ligado, sessões distintas, hash local antes/depois igual.
Banco READ ONLY e cliente GET-only; nenhuma escrita local/remota nessa confirmação.
Nas janelas posteriores à aplicação/filtro de cada caixa: **8 mensagens comuns e 0 mensagens de Status**.
Esse tráfego observado não constitui E2E novo nas 25 caixas; o aceite manual e o ciclo de 135 segundos
ficam vinculados ao piloto anterior. Não foram enviados testes extras.

## Rollback e limites finais

Nenhum rollback foi necessário. Se houver regressão do código, usar o procedimento blue-green de um
passo dos dois workflows, action=rollback e confirm_production=true, após conferir os parâmetros atuais.
Os alvos anteriores esperados estão na tabela. Voltar imagem não desfaz configuração WAHA ou estado local.
Restaurar uma caixa exige confronto com o pós-estado e decisão concreta; não enviar snapshot antigo cegamente.
Não houve alteração de QR/pareamento, logout, importação, exclusão ou recálculo de histórico.
As oito excluídas e eventual inventário/piloto da Autonom.ia exigem trabalho próprio, fora desta entrega.
Os registros somente docs #866/#868/#870 não geram outro deploy; branches remotas preservadas.
