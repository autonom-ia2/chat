# Canal persistente: fronteira SSH → sudo (#995)

## Estado observado

PR #1155 foi integrada em 2026-10-08T15:07:26Z, revisão a09729a7eca6a787d169efc0b8a77294084bee90. Deploys AWS concluídos: Hub2You, execução 37798175221; Autonom.ia, execução 37798175242. Verificação independente confirmou revisão dos containers web/worker, CURRENT do SSM, destino do listener HTTPS e target saudável nos dois ambientes.

A ativação do mesmo artefato na VPS falhou na leitura de bootstrap do publisher. O rollback restaurou a revisão anterior 61f20cfd107361a431fda51f02cace751cc4978d e os limites anteriores. Última verificação: oito unidades ativas, NRestarts=0, Node privado v24.21.0 efetivo. Cookies, perfil, Redis e credenciais foram preservados. Nenhum teste real de busca/status Meta foi executado durante essa ativação.

Durante a primeira parada, um lock vazio do manager antigo permaneceu sem processo proprietário. Foi preservado por renomeação atômica somente após comprovar inode, proprietário, modo, tamanho zero, serviços parados e ausência de processos do usuário. Os links Singleton do Chrome não foram removidos. Paradas posteriores enviaram SIGTERM apenas ao processo principal do manager antes de parar a unidade, evitando o envio redundante ao grupo. A hipótese de sinal duplicado não equivale a um rastreamento comprovado de sinais.

## Causa confirmada por configuração e caminho de execução

O SSH usa um comando forçado que chama sudo sem argumentos adicionais. O wrapper escolhe o canal persistente pela variável SSH_ORIGINAL_COMMAND, comparada com o literal instagram_publisher_channel_v1. O sudo remove essa variável por env_reset; a regra dedicada instalada não a preserva. O wrapper então entra no caminho legado, que espera EOF de stdin. O cliente persistente mantém stdin aberto e expira esperando o primeiro frame.

Diagnóstico isolado na VPS contra a revisão AWS publicada: abertura do canal 14.092 ms; primeira leitura CURRENT SDK 1.495 ms e leitura aquecida 153 ms; primeiro bootstrap expira após 25.016 ms. Nenhum pedido Meta, convite ou claim de operação. O runtime confirmou sudo_command_selector_preserved=false, dedicated_rule_preserves_selector=false e wrapper_selects_channel_from_env=true.

## Correção mínima

Preservar exclusivamente SSH_ORIGINAL_COMMAND para /usr/local/libexec/instagram-tester-publisher-root por Defaults com escopo de comando. Manter a regra NOPASSWD apenas para esse wrapper e somente sem argumentos. Não conceder SETENV, comandos adicionais, grupo docker, shell root ou variável global. O wrapper continua aceitando apenas comando vazio ou o literal do canal, validando frames antes de expor respostas. O instalador continua validando com visudo antes da substituição atômica.

Nenhuma alteração de timeout, cadência, limite de CPU/memória, regra do produto ou fluxo OAuth. A confirmação de testador autorizado continua entregando o fluxo original, sem operação de preparação do Instagram na VPS.

## Validação e limites

Sintaxe shell, AST Python e git diff --check aprovados localmente. Fixture Linux descartável executa sshd real, chave com comando forçado, sudo real e o wrapper de produção; somente Docker/Ruby/provider são sintéticos. Verifica resposta de três frames antes de EOF, caminho legado, comando não autorizado, sudo não relacionado e argumento adicional negados. Remove a nova diretiva dentro do container para reproduzir a espera pela regra anterior. CI deve comprovar esses resultados antes de liberação. Não equivale a comprovação de latência real Meta ou reconexão OAuth completa.

Revisão independente confirmou o escopo restrito e exigiu a fixture SSH/sudo real. Macs disponíveis não têm Docker utilizável; M4 tem pouco disco e o planejador excluiu o build local. O teste de infraestrutura roda em runner Linux descartável, com rede desabilitada durante a execução.

## Aplicação e rollback

Antes de aplicar, conferir revisão publicada, wrapper esperado, proprietário/modo da regra dedicada e seu conteúdo anterior exato. Preservar backup e SHA-256. Validar novo arquivo por visudo; trocar apenas a regra dedicada atomicamente. Não reiniciar web/worker para a regra sudo. Validar bootstrap real antes de nova ativação da VPS. Se falhar, restaurar somente essa regra do backup validado e manter VPS anterior saudável.

Depois de canal funcional: ativar artefato imutável da revisão publicada com rollback preservado, limites canônicos e Node privado; executar busca/status do piloto já autorizado e medir enfileiramento → publicação. Não reenviar convite nem conceder nova permissão. A meta de 10 vezes deve ser comparada às medições antigas reais; os benchmarks anteriores de componentes não satisfazem essa prova.

## Resultado da primeira CI e corrida adicional

Na CI 37803145872, a fixture SSH/sudo real passou, incluindo reprodução da regra antiga. O contrato sintético existente falhou no wrapper por ETIMEDOUT: o publisher rápido podia fechar o FIFO antes de o pai abrir a leitura. Essa corrida é independente da variável removida pelo sudo. Correção mínima: abrir o descritor de leitura antes de criar o publisher, fechar descritores auxiliares no filho e consumir pelo leitor já aberto. Mantém validação, frames e limites. A próxima CI deve validar ambos os casos; nenhum resultado Meta é inferido desses testes.
