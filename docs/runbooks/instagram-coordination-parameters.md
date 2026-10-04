# Publicação manual dos parâmetros de coordenação

Este utilitário é para Rodrigo executar pessoalmente no terminal, após revisão pelo parent. A transferência automática permanece indisponível: a ferramenta bloqueou antes de iniciar. Este documento não registra parâmetros criados nem validação real deste utilitário.

Escopo fixo: região `us-east-1`; Hub usa profile `hub2you`, conta `354307071110`, usuário `ig_hub`; Aut usa profile `financial`, conta `140023375763`, usuário `ig_auto`. Cada conta recebe quatro nomes sob `/chatwoot/prod/instagram-coordination/`:

| Sufixo | Tipo | Conteúdo |
| --- | --- | --- |
| `ssh-key` | SecureString | Chave de seu próprio usuário |
| `redis-env` | SecureString | Ambiente de seu próprio usuário |
| `ca` | String | CA pública |
| `known-hosts` | String | Host SSH fixo e chave pública ed25519 |

Origem exclusiva: alias SSH já confiável `n8n`, resolvendo `85.31.60.100:22`; quatro arquivos `ig_hub.key`, `ig_auto.key`, `ig_hub.env`, `ig_auto.env` em `/opt/instagram-coordination/private`, CA em `/opt/instagram-coordination/tls/ca.crt` e chave pública em `/etc/ssh/ssh_host_ed25519_key.pub`. Não lê administração, passwords separados, CA privada, dados Redis ou outros arquivos de credenciais. SSH exige known hosts existente, sem aceitar ou atualizar chaves automaticamente.

Pré-requisitos: Python 3 standard library, AWS CLI instalada, profiles locais já autorizados, SSH confiável e `sudo -n python3` no n8n. Os quatro arquivos privados e a chave pública SSH devem ser arquivos regulares root; somente o diretório `tls` e a CA pública podem também pertencer ao UID Redis confirmado por `docker inspect --format '{{.Config.User}}' instagram-coordination-redis`. Esse campo deve conter `UID:GID` numéricos fixados; não consulta ambiente nem valores secretos. Todos os demais ancestrais, incluindo `/`, devem pertencer a root. Todos devem ser regulares, sem symlinks, com diretórios sem symlinks e sem escrita por grupo/outros. Privados não permitem acesso por grupo/outros; CA e chave pública SSH não permitem escrita por grupo/outros. O utilitário abre os arquivos somente para leitura e não altera ownership ou permissões. O Python remoto roda com `-E`, ignorando variáveis de ambiente Python, e rejeita otimização (`not __debug__`); as verificações usam condicionais explícitas. PEM/base64, strings e hexadecimal são validados sem regex.

No checkout revisado, primeiro execute apenas a consulta de metadados (default). Ela confirma STS nas duas contas, consulta nomes/tipos SSM e valida metadados da origem, sem ler conteúdo de segredos:

```sh
python3 scripts/instagram_testers/runtime/publish-coordination-parameters.py
```

Para publicar pessoalmente:

```sh
python3 scripts/instagram_testers/runtime/publish-coordination-parameters.py --apply
```

Exige stdin TTY e a confirmação exata `PUBLICAR INSTAGRAM 354307071110 140023375763`, antes de qualquer subprocesso no apply. Não use pipe para a confirmação. Valores ficam em memória e seguem ao AWS CLI exclusivamente como texto cru no STDIN do put, nunca em argumentos, arquivos, ambiente ou logs. Não há serialização JSON, string adicional, remoção de espaços ou adição de newline: o conteúdo multiline é preservado exatamente. Não habilite debug, tracing de shell ou gravação da sessão; não envie valores ao chat. Stdout contém apenas resultados, profiles e nomes. Falhas exibem `aborted`, etapa, código estático conhecido (ou `unexpected-error`) e explicação de interrupção; quando uma chamada AWS falha, também exibem profile, serviço e operação da allowlist. Nunca exibem stderr bruto nem texto de exceções desconhecidas. Antes de tentar o primeiro put, informam `Nenhuma publicação iniciada nesta execução.`; a partir dessa tentativa, alertam sobre possível publicação parcial. URLs com controles são rejeitadas antes do parsing, inclusive TAB no username.

Nenhuma operação usa `--cli-input-json` ou JSON no stdin. STS usa argumentos normais, sem entrada stdin; describe usa `--parameter-filters Key=Name,Option=Equals,Values=CAMINHO`; get usa `--name` e `--with-decryption`; put usa `--name`, `--type`, `--no-overwrite` e `--value file:///dev/stdin`. Todas as chamadas incluem `--no-cli-auto-prompt`, além de `AWS_CLI_AUTO_PROMPT=off` e `AWS_PAGER=''`. Somente esses quatro pares de serviço/operação e os dois profiles fixos são aceitos; operação desconhecida é recusada antes do subprocesso, sem fallback.

Antes de qualquer criação, compara todos os parâmetros existentes nas duas contas: conteúdo e tipo iguais são preservados; divergência aborta todas as criações planejadas. STS é confirmado novamente antes de cada escrita. Só cria ausentes, com `--no-overwrite`, sem rotação. Após cada PutParameter, faz GetParameter com decriptação e compara nome, tipo e valor antes de imprimir `created`. Divergência ou falha de leitura aborta com erro estático e saída não zero, sem anunciar sucesso daquele parâmetro. Não há transação entre contas: falha intermediária, inclusive no readback, pode deixar criação parcial; ausência de `created` não prova ausência do parâmetro no SSM. Corrida concorrente na criação aborta, sem overwrite.

Retomada: rode novamente o check e, após revisar, o apply com nova confirmação. Valores já iguais serão preservados; divergências exigem investigação humana. Não há exclusão ou reversão automática. Reversão deve ser decidida pelo operador com aprovação explícita, identificando apenas nomes efetivamente criados e verificando consumidores antes de qualquer remoção manual; parâmetros preexistentes permanecem preservados.

Validação offline, sem AWS/n8n:

```sh
python3 -B tests/instagram_testers/publish-coordination-parameters_test.py
```

A validação usa subprocess mock e dados sintéticos; não comprova disponibilidade AWS, permissões reais, transferência, deploy ou ACL. Nenhum commit/push é necessário nesta preparação.

Evidência relatada pelo operador: STS direto confirmou a conta `354307071110`; describe por flags retornou `[]`; `--cli-input-json file:///dev/stdin` falhou com `Invalid JSON`. Um put com texto fictício, `--value file:///dev/stdin --generate-cli-skeleton output --no-sign-request`, passou na validação offline do CLI. Skeleton não publica, não valida identidade/permissão de escrita nem comprova criação no SSM. Prova externa de publicação requer a execução humana autorizada e confirmação real de nome, tipo e valor no readback nas contas corretas; não foi produzida nesta correção.

Validação da correção restrita #960/PR #962: `python3 -B tests/instagram_testers/publish-coordination-parameters_test.py` — 28 testes com mocks aprovados, preservando os 19 anteriores. Cobrem rejeição de JSON stdin, conteúdo cru exato, ausência de valores em argv/ambiente/saídas, create-only, check sem put, comparação completa, readback e diagnósticos antes/depois da primeira tentativa de put. O ambiente da suíte é sintético. Revisão própria do diff restrita aos três arquivos deste utilitário humano; sem execução real, AWS ou SSH e sem commit/push. Não concede bypass nem autorização de publicação automática.
