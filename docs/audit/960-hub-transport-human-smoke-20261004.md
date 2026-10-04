# #960 — instalação auxiliar Hub2You e próximo teste humano

Rodrigo informou execução pessoal do instalador preparado em `/run/instagram-transporte.WP8qdI`.
Saída: `NRestarts=0`, `ActiveState=active`, `SubState=running`; wrapper informou aplicação
sem mudança na comparação dos containers e arquivos. É recibo fornecido pelo operador,
não nova inspeção remota do coordenador. Não comprova transporte Redis/proxy nem Meta.

## Próximo bloco, ainda não executado no servidor

Diagnóstico Ruby com gems existentes, sem Rails, imagem imutável local igual à de web/worker.
Cria/remove somente container temporário, rede bridge, limites de recursos e `--pull=never`.
Recebe apenas env dedicado e CA; não recebe env geral, banco ou volumes da aplicação.
Redis: TLS/hostname, autenticação, PING e GET exato do marcador; nenhuma escrita ou varredura.
Webshare: proxy explícito, HTTPS verificado, um GET público; resposta limitada a 128 bytes,
sem retries/redirecionamento/fallback. Compara egress com identidade upstream, como o preflight.
Não chama Meta; não realiza prova de exclusão entre stacks ou de persistência.

Gauss revisou `tmp/manual-transport-smoke-m14fehb6/{command.sh,smoke.rb}` sem bloqueador.
Coordenador acrescentou `Running` à comparação dos containers antes/depois da execução.
Sintaxe Bash/Ruby conferida. Oito cenários mockados passaram: sucesso, usuário incorreto,
Redis indisponível, marcador divergente, alias errado, 407, egress errado e resposta excessiva.
Testes usaram ambiente sintético, Redis/HTTP substituídos e bloquearam rede não mockada;
nenhum Docker, AWS, SSH ou serviço Redis real foi executado nessa validação.
Recibos: `synthetic-tests.json` e `gauss.md` no mesmo scratch.
Timeout Ruby de 45s cobre operações, não o startup Docker/carregamento das bibliotecas.
Código da aplicação, Redis e serviços produtivos não foram alterados nesta preparação.
Resultado real e avanço para Autonom.ia aguardam retorno do operador, um passo por vez.
