# Auditoria de tempo da busca e confirmação do Instagram

Data: 2026-10-08. Issue #995. PR #1155, HEAD `a54572a6d3103375845183bd622102485140c940`.

## Decisão e escopo

Merge suspenso por solicitação do Rodrigo. O PR permanece aberto, sem auto-merge e sem merge commit na consulta desta auditoria. Não houve deploy, alteração funcional, chamada à Meta nem mutação de produção nesta auditoria. O Project registra o bloqueio de merge.

Objetivo do Rodrigo: **reduzir o tempo real da pesquisa e confirmação**, preservando o máximo de 120 segundos. Mudar o timeout não resolve esse objetivo. Esperar o usuário aceitar um convite, fazer login ou concluir 2FA é uma dependência humana separada.

**Conclusão:** houve um defeito funcional na busca, já corrigido, e há um desenho de execução caro que continua tornando busca e confirmação lentas. O PR #1155 remove a verificação adicional antes do OAuth, mas **não estabelece o limite total de 120 segundos** para busca e confirmação. Não deve ser apresentado como solução completa de desempenho.

## Evidências de tempo

Horários abaixo em Brasília (UTC−3), em 08/10/2026. O início foi recuperado diretamente de `Started` nos logs do web da AWS; o fim é `complete_received` no journal do manager da VPS. As ações foram correlacionadas pela sequência isolada do piloto, não por um identificador comum, pois o journal sanitizado omite esse identificador. Esses tempos medem **chegada do pedido ao servidor → reconhecimento da publicação pelo worker**, não clique → renderização no navegador do usuário.

| Etapa | Início HTTP | Conclusão do worker | Duração |
| --- | --- | --- | --- |
| Busca | 07:48:45.941 | 07:50:06.907 | **80,966 s** |
| Primeira consulta de status | 07:50:26.303 | 07:51:08.809 | **42,506 s** |
| Tentativa de convite, resultado incerto | 07:54:41.438 | 07:55:47.744 | **66,306 s** |
| Reconciliação do convite | 07:56:07.641 | 07:56:52.658 | **45,017 s** |
| Confirmação de aceite | 07:59:01.282 | 07:59:52.310 | **51,028 s** |
| Etapa adicional antes do OAuth | 08:00:22.239 | 08:02:31.583 | **129,345 s** |

Fontes: `.codex/pr1139-current-renewal-diagnostics.json` do worktree operacional e `.codex/instagram-action-http-times-20261008.json` do worktree deste PR. O novo leitor consultou somente os logs históricos de 10:48:30 a 11:03:10 UTC da conta autorizada, validou o runtime `8589beb5504fe59a21ed907db9c1d434c6eec0e9`, examinou 3.015 linhas sem truncamento e devolveu apenas ação, horário, status HTTP e duração. Não chamou Meta, OAuth ou operações de navegador, nem alterou produção.

Os pedidos iniciais responderam `202` em 24–69 ms; isso só confirma o enfileiramento. A demora principal veio **depois** dessa resposta rápida. Na tentativa de convite, o executor registrou `invite_unknown` às 07:55:23.350, mas a confirmação de publicação só veio às 07:55:47.744: **24,395 s adicionais depois do erro do navegador**, incluindo o retorno/limpeza do executor e o transporte de conclusão. Não atribuir esse intervalo inteiro à Meta ou ao Rails sem tempos individuais.

A leitura sem resposta às 08:00:34.112 pertence à janela da etapa adicional antes do OAuth. Os 117,471 s anteriormente apresentados contavam a partir dessa leitura, deixando de fora 11,874 s desde a entrada HTTP. O tempo total recuperado dessa etapa é 129,345 s.

Os snapshots de fila registram **quando o operador observou** `queued`, `running` e `ready`. Subtrair esses horários não fornece o tempo exato de entrada na fila, claim ou conclusão. Não há evidência suficiente para atribuir uma quantidade exata de segundos à Meta, ao Rails ou à fila em cada uma das ações acima.

## Causas identificadas

### 1. Perfis válidos eram rejeitados depois de encontrados — corrigido

`BrowserOperations#materialize_candidate` compara as chaves ordenadas do resultado com `SEARCH_RESULT_KEYS`. Antes da correção, a constante estava fora da ordem alfabética. Um resultado com todas as chaves corretas era recusado como `meta_unavailable`.

Correção: commit `36260e86c5`, incorporado pelo PR #1139. A constante passou de `%w[id username name avatar_url]` para `%w[avatar_url id name username]`. Isso explica falhas anteriores de encontrar o perfil no painel; não explica, sozinho, os tempos altos depois da correção.

### 2. Três transportes completos para uma busca ou confirmação — presente

O manager executa `read`, `claim` e `complete` separadamente. Cada chamada passa pelo broker, abre um transporte SSM/SSH e inicia `bundle exec ruby session_publisher.rb`, carregando Rails novamente. O broker e o Chrome persistentes não tornam o processo Ruby persistente. Um convite que chega à permissão de escrita acrescenta `invite_permit`.

Fontes: `scripts/instagram_testers/session-manager.mjs:575-670`; `runtime/vps/publisher-broker.mjs:91-109`; `runtime/publisher-tunnel.mjs:463-634`; `runtime/forced-publisher.sh:15`; `session_publisher.rb:8-20`.

Existe uma medição histórica de **bootstrap**, realizada em 07/10/2026 às 10:52:32 UTC, de 23,276 s por transporte, com aproximadamente 7,682 s antes do SSH remoto e 15,587 s no segmento remoto. STS e CURRENT ocorreram em paralelo; listener e host key também se sobrepõem. Esses tempos não devem ser somados como fases sequenciais. Recibo privado: `.codex/transport-105230-receipt.txt` do worktree operacional. O preflight anterior apontava release VPS `9a48a2de08e93f2f7dc6916d7a4c79729f88dec4`; não é uma medição atual do piloto.

Essa medição mostra que o custo fixo pode ser relevante, mas não mede `read`, `claim` e `complete` no runtime atual e não autoriza dizer que cada uma custa exatamente 23 s. A otimização `eager_load=false` já está no código atual; não é uma correção nova disponível.

### 3. Espera de fila e recarregamento da Meta — presentes, custo exato não medido

O worker consulta a fila em ciclos com pausa de 15 s **mais o tempo da própria consulta**. Trabalha serialmente e intercala operações com renovação da sessão. Quando sobra menos de 120 s para a próxima renovação, encerra o ciclo de operações e inicia a renovação; não fica parado por uma janela fixa de 120 s.

Busca e consulta de status fazem nova navegação à página de funções da Meta. O Chrome e seu contexto já são reutilizados; não existe inicialização de um Chrome novo para cada ação. Há esperas de interface de até 5 s por controle, mas um máximo configurado não prova que esse tempo foi gasto.

Fontes: `session-manager.mjs:23-26,544-575,705`; `browser-operations.mjs:1460-1551,1591-1705`.

### 4. Verificação repetida depois do aceite — removida pelo PR #1155, ainda não publicado

Mesmo após confirmar que o testador estava aceito, o fluxo criava outra operação na VPS antes de devolver a URL do Instagram. O PR #1155 usa a comprovação assinada e vinculada à seleção recém-verificada para gerar a URL original de OAuth diretamente, mantendo validade curta, uso único e validação atual de permissões.

Isso elimina uma rodada cara nessa transição. Busca, convite e confirmação continuam usando o transporte existente. O tempo de carregamento da página externa do Instagram não foi medido separadamente.

### 5. O limite de 120 s está aplicado à parte errada — presente

`BrowserOperationStore::RECORD_TTL` é 300 s. O painel acompanha a operação até esse prazo. O orçamento de 120 s do manager começa antes de `read`/`claim`, mas **depois da espera para ser atendido**. Não há um prazo único de clique até resposta, nem reserva explícita para publicar o resultado quando a execução consome quase todo o orçamento.

O claim tem validade de 120 s a partir do claim, portanto a igualdade dos dois números não prova ausência total de margem. O problema confirmado é o limite incompleto da experiência inteira.

Fontes: `app/services/instagram/testers/browser_operation_store.rb:7-8`; `app/javascript/dashboard/api/channel/instagramClient.js:101-149`; `session-manager.mjs:555-670`.

## O que os testes atuais provam e o que falta

O PR passou nos testes funcionais e de segurança e na simulação com imagem de produção. Essa simulação usa provedor sintético e não percorre o transporte real VPS → SSM/SSH → AWS nem a interface real da Meta. **Não prova desempenho real nem cumprimento dos 120 s.**

Não há evidência para culpar falta de RAM, recomendar mais CPU ou aumentar timeouts. Os logs atuais registram principalmente o resultado final, sem duração individual de fila, leitura, claim, navegação, execução e publicação. Isso também dificultou o diagnóstico.

## Plano mínimo registrado nesta auditoria inicial (antes dos experimentos)

1. Medir por etapa, sem dados de cliente, cookies, URLs ou tokens: entrada na fila, início de atendimento, transporte, claim, navegação, execução, publicação e resposta. Primeiro observar o transporte atual, preservando permissões e limites.
2. Reduzir trabalho repetido. Avaliar `read_claim` atômico como opção menor que manter Rails residente ou reutilizar túneis, preservando seleção, ACL, exclusividade e bloqueio de escrita do convite. A escolha depende da medição; não é decisão de implementação desta auditoria.
3. Comparar os tempos reais antes/depois da mudança escolhida, especialmente os **80,966 s da busca** e **51,028 s da confirmação**, incluindo a publicação final. Não aumentar ou cortar timeout como substituto de redução de trabalho. Convite de resultado incerto precisa reconciliação, sem repetir a escrita.
4. Manter a transição direta ao OAuth após aceite implementada no PR #1155. Validar busca, confirmação, convite e transição com o transporte equivalente ao real, registrando tempo total e comportamento quando há renovação concorrente.

Na auditoria inicial não foi feita nenhuma dessas alterações. Os experimentos posteriores estão em `995-instagram-latency-candidate-tests-20261008.md`: publisher persistente e SDK fresco foram medidos, e o candidato de pausa de 1 s passou em testes de ciclo. A revisão permite apenas piloto observado; não houve publicação. TTLs e orçamentos permaneceram iguais. Merge e deploy continuam suspensos até aprovação explícita.
