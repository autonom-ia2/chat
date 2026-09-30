# Liberação de Relacionamentos #776 — frontend

Data de autorização e merge: 29/09/2026, America/Sao_Paulo. Os horários dos
workflows abaixo estão em UTC.

## Autorização e gates anteriores ao merge

Rodrigo autorizou merge e deploy depois de implementação, revisão e testes
verdes. A autorização foi aplicada à apresentação da Issue #776 e aos pipelines
blue/green existentes de Hub2You e Autonom.ia. Não houve ativação/desativação de
flags nem uso de dados de clientes como fixture.

A [PR #777](https://github.com/autonom-ia2/chat/pull/777) foi mergeada por squash
em `2026-09-30T00:22:35Z`, com SHA de aplicação
`4ba863913d42141a358db95cf2f32a61924e7d59`. O candidato testado foi
`afda185eed23a26df5507b76ffb0c8030b9e2935`; a comparação das árvores Git confirmou
conteúdo idêntico. A base permaneceu
`6c89c4bc5dd3826c81a68cf72e6f7809d10eb351` até o merge. Não havia outro deploy
em andamento. A Issue #776 foi encerrada pelo vínculo `Closes` da PR.

O [CI do candidato final](https://github.com/autonom-ia2/chat/actions/runs/36647839836)
concluiu com sucesso:

- Frontend completo: 614 arquivos / 6.826 testes aprovados.
- Backend e compatibilidade: 288 exemplos, zero falhas e uma pendência;
  `Account has_many autonomia_account_links` já estava em quarentena na base,
  em `spec/models/account_spec.rb:52`. São 287 aprovados, não 288.
- Conversores nativos: 18 exemplos, zero falhas.
- Imagem Linux do SHA candidato: 11 checks aprovados, incluindo PNG, PDF, MP4,
  JPG/WebP, rejeição de entradas inválidas, limites de memória/arquivo e timeout.
- Guia e Central aprovados. Os checks de Email foram dispensados pelo detector
  de escopo; não foram apresentados como testes executados.

Antes do merge, todos os checks aplicáveis da PR estavam concluídos e verdes,
com `mergeStateStatus=CLEAN`. A regressão local final passou 115 testes
direcionados e 22 E2E, sem retries. A matriz final tem 60 capturas, em
390/1024/1630 e temas claro/escuro, no SHA candidato. Os manifestos registram
zero erros JavaScript e zero overflow do documento; o 404 conhecido da rota
Enterprise de limites permaneceu distinguido de falhas inesperadas. As capturas
usaram Chrome 154.0.8037.58, depois de crash nativo do Chromium no macOS; os 22
E2E passaram no Chromium do Playwright.

A revisão independente encontrou um P2 em paginação de mídias, corrigido com
regressão reproduzida antes do ajuste. A inspeção das capturas encontrou corte
do botão da Central em 390 px, também reproduzido e corrigido. A revisão do
conteúdo final não encontrou achados demonstráveis restantes. Ela não executou
as suítes nem certificou igualdade de pixels com os mockups originais, que
continuam indisponíveis. Detalhes em
[frontend](2026-09-29-relationships-776-frontend.md) e
[contrato visual](../relationships/visual-contract.md).

## Publicação e conferência

Os dois pipelines foram disparados automaticamente pelo merge em `main` e
concluíram com sucesso:

| Stack      | Pipeline                                                                    | SHA da aplicação                           | Resultado |
| ---------- | --------------------------------------------------------------------------- | ------------------------------------------ | --------- |
| Hub2You    | [36650021185](https://github.com/autonom-ia2/chat/actions/runs/36650021185) | `4ba863913d42141a358db95cf2f32a61924e7d59` | Sucesso   |
| Autonom.ia | [36650021080](https://github.com/autonom-ia2/chat/actions/runs/36650021080) | `4ba863913d42141a358db95cf2f32a61924e7d59` | Sucesso   |

Depois da conclusão de cada deploy, o
[preflight 36650762685](https://github.com/autonom-ia2/chat/actions/runs/36650762685)
passou nas duas stacks. Foi usada somente a ação `preflight`, com
`confirm_production=false` e o SHA exato acima. Nenhuma ação
`enable`/`disable`/`verify` foi executada. O relatório confirma:

- Serviços web e worker ativos, ambos com `.git_sha` igual ao SHA publicado.
- Alvo atual saudável no ALB e listener HTTPS alinhado aos ponteiros SSM.
- Instância anterior disponível, parada e registrada no target group de rollback.
- Os alvos anteriores são exatamente os que serviam a base `6c89c4bc5d` antes
  desta publicação. As flags das contas existentes e a composição do snapshot de
  contas permanecem iguais à conferência anterior; nenhum identificador de conta
  ou conteúdo de cliente está registrado neste documento.

| Stack      | Instância atual       | Target group atual  | Instância para rollback | Target group de rollback |
| ---------- | --------------------- | ------------------- | ----------------------- | ------------------------ |
| Hub2You    | `i-06d1625d3e7b17947` | `cw-hub2-green-453` | `i-0b0ccd289aabf1b1c`   | `cw-hub2-green-452`      |
| Autonom.ia | `i-0df75aaa0996c31a4` | `cw-auto-green-438` | `i-0489c3ad63cfa158f`   | `cw-auto-green-437`      |

Os pipelines também passaram o smoke de redirecionamento SSO. A conferência
pública em `2026-09-30T00:38:10Z` retornou HTTP 200 em
[Hub2You](https://chat.hub2you.ai/) e
[Autonom.ia](https://agents.autonomia.site/). O Project foi atualizado para
Mergeada / Produção com os links das execuções.

Esta é prova de versão, serviços, alvo HTTPS e rollback em produção, com um
smoke HTTP público por stack. A validação completa das telas e das gravações
aconteceu no ambiente sintético local. Não houve jornada autenticada com dados
de clientes em produção. A comparação de pixels com os mockups originais
continua sem certificação.

## Comandos e preservação

```sh
gh pr view 777 --repo autonom-ia2/chat --json state,headRefOid,baseRefOid,mergeable,mergeStateStatus,statusCheckRollup
gh pr merge 777 --repo autonom-ia2/chat --squash --match-head-commit afda185eed23a26df5507b76ffb0c8030b9e2935
git fetch origin main
git rev-parse afda185eed23a26df5507b76ffb0c8030b9e2935^{tree} 4ba863913d42141a358db95cf2f32a61924e7d59^{tree}
gh run view 36650021185 --repo autonom-ia2/chat --json status,conclusion,headSha,jobs
gh run view 36650021080 --repo autonom-ia2/chat --json status,conclusion,headSha,jobs
gh workflow run relationships-operations.yml --repo autonom-ia2/chat --ref main -f action=preflight -f tenant=both -f expected_sha=4ba863913d42141a358db95cf2f32a61924e7d59 -f confirm_production=false
gh run view 36650762685 --repo autonom-ia2/chat --json status,conclusion,headSha,jobs
```

O rollback segue [o plano existente](../relationships/rollout-rollback.md) e os
pipelines de cada stack, ação `rollback`, com o alvo anterior retido. O delta não
inclui migrations ou backfill; os pipelines usam o `db:chatwoot_prepare`
padrão. Não foi necessário rollback nem remoção de originais/valores. Não houve
alteração ad hoc de secrets, autenticação, billing, DNS ou IAM.

Este registro é uma alteração exclusiva de documentação. Os dois workflows de
publicação excluem `docs/**`; sua integração posterior não dispara outra
publicação da aplicação. O SHA efetivamente publicado deve ser conferido no
runtime, separado do SHA de eventuais commits posteriores de documentação.
