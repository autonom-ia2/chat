# Runtime e procedimento de instalação — PR #1155

2026-10-08. Preparação para aprovação; nenhuma instalação, parada, merge ou deploy executado nesta rodada.

## Node: verificação efetiva, não apenas do host

O `/usr/bin/node` do host é 18.19.1. Essa leitura isolada não identifica o runtime dos serviços Instagram. A inspeção fresca das namespaces dos seis processos Node das duas stacks confirmou o mesmo binário privado:

`/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node`

Versão 24.21.0, SHA-256 `7fde7b8afa198da66257f42ee2001d874c7355631e6d1579a5fb5ef1f246df4c`. Arquivo e ancestrais são root-owned, sem escrita de grupo/outros e sem symlink. Os três drop-ins de template `20-private-node.conf` têm SHA `21296e432301fe7634c65c399c24c692799745466e0e7ce1e829775c112ec1ba` e montam esse arquivo em `/usr/bin/node`. Os hashes efetivos em `/proc/PID/root/usr/bin/node` coincidem em todas as seis units; `NRestarts=0` nessa leitura.

Portanto não há necessidade de atualizar Node/npm do host, mudar templates systemd ou relaxar o gate >=22.12. A interpretação anterior de que Node18 do host bloqueava a release foi corrigida após verificar a namespace real. O instalador deve receber o mesmo bind privado, como já previsto no handoff operacional.

Evidência sanitizada: `995-instagram-effective-runtime-20261008.json`. Ela comprova runtime/estado dos processos na hora da leitura, não conexão Meta ou saúde futura.

## Testes do candidato com esse runtime

O leitor SDK candidato fez 21 consultas reais a CURRENT numa unit transitória com o mesmo bind Node24, usuário/perfil Hub2You e limites canônicos do publisher: CPU50%, 512MiB, 64 tasks. Uma chamada inicial e vinte warm; pausa de 1s entre chamadas. P50 warm 140,784ms, P95 149,875ms, máximo 156,707ms. Valor conferido com CLI; `maxAttempts=1`, sem cache de CURRENT ou Meta. Serviços ativos e host preservados; unit/staging removidos.

Evidência: `995-instagram-private-node24-cadence-20261008.json`. O ganho do leitor continua superior a dez vezes frente à mediana CLI de 4.512,955ms, mas não representa o tempo completo de uma operação de cliente.

Também foi testado Node22.23.3 oficial em isolamento (`995-instagram-node22-sdk-readiness-20261008.json`), sem substituição do host. Esse experimento não é o runtime escolhido para a release. A versão e checksum do arquivo foram conferidos com a [publicação oficial](https://nodejs.org/en/blog/release/v22.23.3).

Uma simulação APT do pacote NodeSource22, sem instalação, propunha remover **133 pacotes**. Esse caminho foi rejeitado. Os pacotes anteriores puderam ser baixados/conferidos e a área de teste foi removida; isso não autoriza nem torna necessária a transação global. Preservar o runtime privado existente evita essa alteração.

## AWS atual e margem observada

A leitura fresca de CURRENT e dos containers nas duas stacks confirmou web/worker ativos com a mesma imagem e source `23f667bab1ed1f4ab0e350c93f02576f6455d3fe`, merge do PR #1154 já presente no main. O sandbox anterior usou `8589beb…`; permanece evidência controlada histórica, não inventário atual. Os checks finais do PR precisam executar contra o main atualizado e a publicação usará o SHA efetivamente mergeado.

Host Hub2You: MemAvailable 1.227.321.344 bytes (~1.170 MiB); web 637,3 MiB, worker 882,4 MiB. Autonom.ia: MemAvailable 1.841.631.232 bytes (~1.756 MiB); web 578,4 MiB, worker 780,9 MiB. Os containers não estavam OOMKilled e não têm limite Docker explícito; esses números são instantâneos, não teste de carga. A margem observada comporta o filho Rails ~262 MiB medido no sandbox, mas memória/CPU agregadas precisam ser observadas durante prewarm/piloto. Não aumentar recursos nem tratar o snapshot como garantia futura.

Evidência: `995-instagram-aws-preflight-20261008.json`. A releitura foi explicitamente fixada no main atual `23f667ba` e confirmou `source_matches_expected=true` nos quatro containers; a primeira versão desse campo ainda usava a referência histórica `8589beb…`. A correção foi do leitor/recibo, não da aplicação. Tentativas privadas iniciais falharam por referência de SHA antiga, perfil incorreto e colisão de variável no leitor diagnóstico; foram corrigidas antes deste recibo final. A unit transitória de diagnóstico Autonom.ia também foi removida, com publisher vivo preservado. Nenhuma mudança na aplicação, infraestrutura ou credenciais. O perfil autorizado Autonom.ia é `financial`, conforme a configuração do publisher; não foi renovada/alterada autenticação.

## Instalação após aprovação

1. Registrar SHA efetivamente mergeado e artefato Linux root-owned correspondente, incluindo dependências do lockfile, manifesto/checksums e release anterior. Não chamar o SHA da branch de SHA da imagem mergeada.
2. Revalidar binário privado/drop-ins, oito units, release `current`, enabled/disabled, caps, saúde e ausência de operação/janela humana. Falha não explicada ou processo órfão bloqueia a parada/instalação. Guardar bytes dos drop-ins e templates para rollback; não copiar perfis ou secrets para o pacote/auditoria.
3. Após autorização, parar somente as oito units Instagram, confirmar encerramento de Chrome e filhos e preservar os perfis, chaves, nonces, locks e Redis. Não parar n8n, Traefik ou serviços de aplicação.
4. Executar o instalador em unit transitória root com o mesmo bind, usando caminhos/SHA aprovados:

```sh
sudo systemd-run --wait --collect --unit="instagram-install-$APPROVED_RELEASE_SHA" \
  --property=Type=exec \
  --property=BindReadOnlyPaths=/opt/instagram-meta-tools/node-v24.21.0-linux-x64/bin/node:/usr/bin/node \
  /usr/bin/python3 "$APPROVED_ARTIFACT/scripts/instagram_testers/runtime/vps/install/install.py" \
  "$APPROVED_ARTIFACT" "$APPROVED_RELEASE_SHA"
```

O stage precisa ter ancestrais root-owned não graváveis por terceiros, como `/opt/instagram-meta-staging/SHA`. `/tmp` e `/var/tmp` não servem para o artefato real. O instalador mantém a verificação >=22.12 dentro dessa namespace, exige units inativas/failed e templates iguais, não inicia serviços e só seleciona `current` após sucesso. Não ignorar retorno diferente de zero nem remover release parcial para repetir às cegas.

5. Conferir `current`, manifesto, owners, checks de env/`verify-pair` sem exibir conteúdo. Preservar os três drop-ins Node. Iniciar display/gateway, conferir HTTP real, depois publisher e manager, mantendo o enable anterior. Verificar prewarm, PIDs, hashes efetivos de Node e `NRestarts`, saúde/renovação e filas.
6. Existem dois overrides temporários `30-cpu-quota.conf` dos publishers, ambos SHA `41c6db5c35846b239a0da96950bc1e599703b0b1aabbb274a6f99f95d168ea43`, CPU200%. A aprovação de instalação deve incluir voltar à quota canônica50%, guardando e removendo somente esses overrides conhecidos antes de iniciar os publishers. Não tocar nos binds Node; não aumentar quotas. Qualquer conteúdo diferente exige parar e revisar.

## Reversão

Se a instalação/smoke falhar, parar somente as units Instagram, verificar encerramento dos filhos, restaurar atomicamente `current` para a release anterior conferida e restaurar apenas os dois overrides de CPU guardados, se foram removidos nesta operação. Fazer daemon-reload e reativar somente as units previamente ativas/habilitadas. Preservar drop-ins Node, templates, perfis, chaves, nonces e Redis. Não replay de frame, claim ou convite. Não apagar a release parcialmente instalada como recuperação automática.

O rollback AWS é separado e usa `action=rollback` nos workflows blue-green existentes. Ele não reverte a VPS. A implantação AWS já instala o wrapper a partir da imagem exata na green; não há uma terceira implantação independente de wrapper.

## Limites do aceite

CI/revisão aprovados permitem pedir aprovação para publicação e piloto observado. O tempo completo com Meta, reautorização OAuth real e funcionamento depois de novo restart só podem ser confirmados no piloto pós-publicação. Não declarar ganho10x ponta a ponta, reconexão real ou SLA do painel a partir destes componentes.
