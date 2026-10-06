# #995 — HTTPS privado após consentimento, 06/10/2026

Este checkpoint sucede `995-serve-consent-and-autonomia-20261006.md`. Registra execução real e os limites dos resultados; não encerra a migração nem substitui os recibos originais. Rodrigo informou o consentimento concluído e enviou o print Success. As autorizações anteriores permanecem válidas.

## Estado confirmado às 10:13:34 UTC

- Os dois mounts Serve estão configurados em HTTPS 443: `/hub2you/` e `/autonomia/`, encaminhados respectivamente para `http://127.0.0.1:18441/hub2you/` e `http://127.0.0.1:18442/autonomia/`.
- A configuração Serve não contém `AllowFunnel`. Não foi executado Funnel, alterada ACL ou exposto gateway em interface pública.
- Display Hub PID 1475711 e gateway Hub PID 1617718 estão ativos. Display Autonomia PID 1547143 e gateway Autonomia PID 1619939 estão ativos.
- Os quatro serviços continuam desabilitados para boot nesta fase. Os quatro managers/publishers VPS permanecem inativos, PID zero. Nenhum corte dos Macs ocorreu.
- Gateways escutam somente em 127.0.0.1, nas portas 18441/18442. O listener temporário 28443 dos testes não existe mais.
- DNS normal para o nome privado ainda não foi corrigido nos Macs. A tentativa de abrir autorização macOS foi bloqueada antes de executar; não há instalação DNS confirmada.
- Nenhuma alteração em Redis, overlay Rails, flags globais, código de produto, main ou deploy Rails foi realizada nesta rodada. Manter assistido OFF até o aceite operacional.

## Consentimento e mounts

A consulta do cliente oficial na VPS `query-feature?feature=serve` retornou `Complete=true` às 09:50:29 UTC. A configuração Serve estava vazia. Isso confirma o consentimento no servidor, não apenas no print.

Os hashes dos executores staged foram revalidados: `serve-mount.py` = `52b5e5b62ed15bb07059dbc599d7ec8a34c03585f7fc4fc5b08c097f778663b5`; `negative-probe.py` = `f1c483ef385a608b211bd3be7be3870e2b53b47b486900e01e0ed55b9cbfa0bf`.

| Ação | PID Mac | UTC | Backup remoto |
| --- | --- | --- | --- |
| apply Hub | 41146 | 09:52:05 | `/tmp/instagram-serve_20261006T095205Z_8badb29ab1a646acb111ded5dcad0f4a.json` |
| apply Autonomia | 48215 | 09:59:03 | `/tmp/instagram-serve_20261006T095903Z_a721df06710e4c8ba2d0616a9876efaf.json` |

Ambos retornaram `applied_pending_https_validation`. Cada um tem o resultado irmão `.result.json`. O mount Hub foi validado pelo peer antes do apply Autonomia. Os listeners públicos preexistentes foram preservados pelo executor. Não executar novamente apply sobre mounts presentes; reconciliar configuração e backup primeiro. O rollback existente remove somente o mount da stack, sob lock, preservando os demais.

## Caminho real do TLS e limite do autoacesso

O primeiro negativo HTTPS feito na própria VPS falhou: curl exit 60, verificação 18, certificado autoassinado, destino 100.78.34.82. O recibo de falha foi preservado em `/opt/instagram-meta-staging/https-approved-1023-20261005/negative-https-hub2you-20261006T0952.json`. Foi uma tentativa de um caso; não foram executados os 21 nesse caminho.

A VPS tinha docker-proxy preexistente em wildcard 443. Não alteramos Docker, listeners ou validação TLS para fazer o teste passar. A evidência direta demonstra que o autoacesso não produziu o mesmo resultado do acesso pelo peer; não foi feita inspeção adicional para atribuir o certificado a um container específico.

Pelo M4, a consulta explícita `dig @100.100.100.100` resolveu o nome para 100.78.34.82. Curl para o hostname original com esse endereço explícito retornou 401 sem cookie e `ssl_verify_result=0`, sem `-k`, CA alternativa ou fallback HTTP. Pelo M2, os dois endpoints também retornaram 401/TLS=0 com resolução explícita.

A resolução normal do M4 falhou, e a consulta pelo resolvedor do sistema no M2 não encontrou o nome. Estes testes com endereço explícito **não comprovam navegação pelo DNS normal dos Macs**.

## Negativos HTTPS — 42 verificações aprovadas pelo M4

Os mesmos 21 casos do `negative-probe.py` revisado foram executados por stack a partir do M4. O wrapper somente acrescenta `curl --resolve` para o endereço obtido do MagicDNS, mantendo URL, hostname, SNI, validação TLS, métodos, headers e expectativas originais. Rejeita `-k`/`--insecure` e transporte diferente de HTTPS.

| Stack | PID | Conclusão UTC | Resultado |
| --- | --- | --- | --- |
| Hub2You | 48113 | 09:58:52.268919 | 21/21 |
| Autonomia | 48332 | 09:59:17.876537 | 21/21 |

Cobertura: recursos sem sessão, query, Origin inválida/ausente/null, Authorization alternativa, cross-site, formulários e JWT inválidos e WebSocket sem autorização. Os recibos declaram `normal_dns_proven=false` e `positive_auth_proven=false`.

Raiz local dos novos artefatos:

`/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005/https/post-consent-20261006/`

Recibos: `negative-https-peer-hub2you.json` e `negative-https-peer-autonomia.json`. Wrapper `peer-negative.py`, SHA256 `78f418b54067db8b39e8e798e56b08a79e3ed835535bf2eafae43a870582c872`. O teste local/loopback anterior de 42 casos permanece um conjunto histórico diferente.

## Autenticação HTTPS sintética — 21 assertions por stack

O parecer anterior de gateway foi finalmente lido. Duas lacunas reais de cobertura foram corrigidas no probe, não no produto: aud e stack agora têm casos inválidos individuais, além do caso combinado; a sessão curta precisa responder 200/waiting antes do prazo, antes de se verificar a expiração.

As chaves continuam lidas e usadas somente na VPS; não foram copiadas para os Macs. Para atingir o Serve pelo mesmo caminho de entrada do cliente, o teste usou temporariamente:

`VPS 127.0.0.1:28443 → SSH temporário → M4 → Tailscale → Serve 443`

Os bytes são TLS de ponta a ponta entre o probe e o Serve. O agente TLS mantém SNI fixo, `rejectUnauthorized=true` e `tls.checkServerIdentity` para o hostname original. Isso não é HTTP de fallback, não instala rota permanente e não comprova autoacesso direto da VPS443 ou DNS dos Macs. O listener temporário foi confirmado somente em loopback e removido depois.

O lock Serve foi mantido pelo coordenador remoto durante preflight, probe, reconciliação das units e remoção do túnel. A vida do SSH foi limitada por um comando remoto de 120 segundos, além do encerramento explícito do processo criado. O probe tinha limite global de 80 segundos. Não se encerraram sessões SSH alheias.

| Stack | PID coordenador Mac | Resultado do probe | Encerramento |
| --- | --- | --- | --- |
| Hub2You | 60114 | exit 0; 21 assertions PASS | coordenador exit 0; listener removido e units reconciliadas às 10:06:53 UTC |
| Autonomia | 61218 | exit 0; 21 assertions PASS | coordenador exit 1 na primeira conferência imediata da remoção; reconciliação independente posterior concluída |

As assertions validaram concessão sintética assinada, cookie protegido, espera sem marker, bloqueio de WS sem marker, JWT/issuer/chave/aud/stack/deadline inválidos, replay imediato, persistência do bloqueio de replay após um restart do gateway, revogação do cookie antigo, sessão curta utilizável antes do prazo e rejeitada depois.

Cada gateway foi reiniciado uma única vez; os displays mantiveram seus PIDs. Nenhum marker falso, pedido Rails, login Meta, publicação ou renovação Meta foi criado. Os nonces sintéticos foram preservados; não limpar diretórios para repetir o teste.

### Reconciliação Autonomia — não ocultar a falha do coordenador

O probe Autonomia passou os 21 checks, mas a primeira consulta imediatamente após terminar o SSH ainda encontrou o listener. O coordenador registrou `passed=false`, `AssertionError`; no tratamento do erro já observou o listener ausente e as units preservadas. Os bytes desse resultado continuam intactos.

O PID 62878 realizou somente leitura e gerou recibo separado: duas amostras às 10:09:48.749181 e 10:09:49.414174 UTC confirmaram listener ausente, oito units iguais ao fim do probe e nenhum job systemd dessas units pendente. Não houve repetição de autenticação, restart ou exclusão de nonce. A discrepância de encerramento foi reconciliada; o exit original não foi alterado para verde.

Recibos remotos: `/opt/instagram-meta-staging/auth-peer-{hub2you,autonomia}-20261006.json` e `auth-peer-autonomia-20261006-reconciliation.json`. Cópias locais: `auth-peer-hub2you.json`, `auth-peer-autonomia.json` e `auth-autonomia-reconciliation.json`.

Fontes locais e hashes:

| Arquivo | SHA256 |
| --- | --- |
| `auth-probe-peer.mjs` | `190264a47bf424d4042b35dc143ba7a60e5aec8358c57f81f380544f1ebbedae` |
| `peer-auth-remote.py` | `ba0cfc34e343b0d4ad98feeba3d74ff2cb8f8eb14257cd3507b0b94a22180dfc` |
| `peer-auth-run.py` | `3f60411d03aebbe7f30625989e20feab9be98930edfb2966daae321af04086db` |

O probe staged está em `/opt/instagram-meta-staging/https-auth-peer-20261006.mjs`, root-owned 0600. Node --check e compilação dos wrappers passaram antes de executar. Para um futuro uso do coordenador, tratar a remoção assíncrona do listener com espera limitada e revisão; não repetir agora os grants já testados. Os arquivos de produto não mudaram.

## M2 + M4 — configuração existente preservada

A busca dos chats de configuração recuperou o arranjo existente: mesma tailnet `autonomia.site`, mesma conta, conectividade M2↔M4 e DNS automático Tailscale desativado. A preferência viva do M4 confirmou `CorpDNS=false`, `WantRunning=true`, sem exit node. Não foram alterados conta, tailnet, accept-dns, SSH, watchdogs ou DNS global.

O ajuste preparado é um resolvedor macOS limitado ao domínio `tail0c0b18.ts.net`, com o conteúdo abaixo em `/private/etc/resolver/tail0c0b18.ts.net`:

```text
nameserver 100.100.100.100
```

Isso foi escolhido porque o MagicDNS explícito respondeu nos dois Macs, enquanto o resolvedor normal não. A documentação Tailscale informa que seu DNS local continua respondendo em 100.100.100.100 mesmo com accept-dns=false. Não é necessário reativar DNS global ou criar outra rede/conta.

O instalador `install-scoped-dns.py` exige macOS/admin e ação explícita `install`. Verifica diretórios root-owned sem escrita por terceiros, recusa symlinks/arquivo existente divergente e usa criação exclusiva. Não substitui arquivos de configuração existentes. Limpa apenas cache DNS depois da gravação, sem reiniciar Tailscale/SSH.

Fonte SHA256: `30c8b02999360df4fbf8fec096a62413fc7aa50474916ac6c7ceadf41b5597b7`. Uma cópia exata foi preparada em **cada Mac**, no caminho `/Users/Shared/instagram-private-dns-20261006.py`, sem executar instalação.

Sudo não tinha autorização não interativa. A tentativa normal de abrir o diálogo macOS com privilégios administrativos foi bloqueada pela plataforma antes de executar. Nenhuma janela ou instalação foi confirmada; não houve repetição por outra rota. A preparação dos arquivos públicos não concede privilégios.

Próxima ação humana, no Mac em uso:

```sh
sudo /usr/bin/python3 -I /Users/Shared/instagram-private-dns-20261006.py install
```

Após o retorno, verificar pelo resolvedor normal e por HTTPS sem `--resolve`; depois tratar o outro Mac. Não afirmar DNS resolvido antes dessas provas. Uma falha pode deixar arquivo parcial, portanto reconciliar lstat/conteúdo antes de repetir. Rollback remove somente o arquivo criado por esta operação após conferir proprietário e bytes esperados, sem remover outros resolvers.

## Revisões e Project

Os três pareceres antigos em `review/codex-20261006T0921/` foram lidos. Não eram aprovação irrestrita; seus achados/limites foram considerados. Nesta rodada foram executados três revisores Codex gpt-6.1-sol, high, read-only, MCPs desativados: DNS, localidade do cliente HTTPS e patch de autenticação. Os três terminaram exit 0, os conteúdos foram lidos e os recibos reportam zero tool_events. São revisões textuais, não testes executados pelos revisores. Os wrappers de coordenação receberam revisão direta do coordenador; não atribuir sua revisão a um subagente.

O conector Project continuou 404, mas a CLI GitHub autenticada conseguiu acessar o board correto. A issue #995 e a PR #1042 foram adicionadas/reconciliadas e seus sete campos preenchidos. Readback exato às 10:11:09 UTC, Project `PVT_kwHOC3T16M4BX9UH`, https://github.com/users/autonom-ia/projects/3. A pendência manual anterior de Project está resolvida para os dois itens; o endpoint do conector não foi reparado.

#995: Projeto=Hub2You, Status=Bloqueada, Tipo=Infra, Prioridade=P1, Risco=Alto, Ambiente=Produção. Próxima ação: DNS específico com autorização macOS, UI, overlay, isolamento composto, corte/B0, produtores e aceite Meta. #1042: Projeto=Hub2You, Status=PR aberta, Tipo=Docs, Prioridade=P1, Risco=Médio, Ambiente=Produção; revisão final dos checkpoints. Recibo local `project-update.json`.

## Próxima etapa e limites finais

O consentimento e o HTTPS privado dos dois mounts estão concluídos. Os 42 negativos HTTPS e as 42 assertions de autenticação sintética passaram; a limpeza Autonomia precisou de reconciliação separada. Isso ainda não comprova DNS/navegador dos Macs, UI SuperAdmin, SameSite no navegador real, fluxo VNC real, login/2FA Meta, publicação ou renovação natural.

Resolver nomes privados nos Macs com autorização local; validar navegação normal; reconsultar fila/CURRENT/overlay antes de qualquer publicação/configuração Rails; concluir prova composta de isolamento, corte controlado, B0 e produtores. Não houve novo merge/deploy ou inventário da fila nesta etapa independente da aplicação. #1042 permanece draft fora da fila e #995 aberta.
