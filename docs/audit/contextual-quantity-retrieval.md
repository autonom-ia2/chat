# Contexto da busca em correcoes de quantidade

Data: 2026-11-17. Escopo: busca de conhecimento, sem mudanca de instrucao, precos, handoff, dados ou integracoes.

## Decisao

- A implementacao anterior reconhecia somente numeros isolados depois de uma pergunta de quantidade e apenas no simulador.
- `RetrievalQuery` retoma o assunto informado pelo cliente em correcoes curtas como `Vou fazer so de 10.` e `Na verdade, serao so 2 usuarios.`. Nao existe regra de empresa, exame, produto, preco ou faixa comercial.
- A funcao roda no `Answerer`, compartilhada entre o simulador e o atendimento. Um `retrieval_query` explicito continua soberano.
- A mensagem e o historico enviados ao modelo nao mudam. A resposta anterior do assistente nao e incluida na busca como cotacao ou fonte de fato; somente sua ultima pergunta de quantidade pode servir como pista.
- A busca olha no maximo oito mensagens, usa o ultimo assunto do cliente e limita cada pista a 400 caracteres. A mensagem atual vem primeiro. Fora dos formatos curtos reconhecidos, a consulta original e preservada.
- Nao ha chamada extra ao modelo, banco ou provider para construir a consulta.
- O log `autonomia.agents.retrieval` registra IDs recuperados, IDs validos declarados como usados, sinal de handoff, uso declarado da base e falha de geracao. Nao registra mensagens, respostas, motivos livres de handoff, instrucoes, valores, URLs ou credenciais. Os IDs declarados pelo modelo sao intersectados com os efetivamente recuperados.

## Validacao local

- Reproducao antes da correcao: dois casos de correcao de quantidade falharam ao atravessar o Playground (analise e licencas de software).
- RSpec isolado do `RetrievalQuery`: 11 exemplos, zero falhas, usando a classe real e sem carregar Rails. Cobertura de portugues/ingles, numero isolado, mudanca de assunto, correcoes repetidas, respostas divididas, ausencia de contexto e limites de tamanho/historico.
- Harness isolado de callers e log: 5 testes, 19 assercoes, zero falhas. Executa os construtores reais de Playground/Answerer e o log; substitui somente as dependencias de framework/formato e a geracao. Confere preservacao da pergunta/historico, prioridade do override e ausencia de texto privado no log.
- A tentativa de executar `bin/bundle exec rspec spec/services/autonomia/agents/retrieval_query_spec.rb spec/services/autonomia/agents/playground_spec.rb spec/services/autonomia/agents/answerer_spec.rb` foi bloqueada antes dos testes: este Mac tem Ruby 2.6.10 e nao possui Bundler 2.5.16. O projeto requer Ruby 3.4.4. A suite Rails completa e o RuboCop do projeto permanecem pendentes de CI; os testes isolados nao substituem esses gates.
- O RSpec 3.13 foi instalado somente em pasta temporaria para os testes isolados; Gemfile e lockfile nao mudaram.
- Sintaxe Ruby, `git diff --check` e `sh bin/validate_push` passaram. O hook local nao iniciou porque falta `.husky/_/husky.sh` nesta worktree; o commit usa as verificacoes manuais, sem substituir lint/CI.
- O push pelo terminal foi recusado com HTTP 403 para a conta autenticada na CLI. A publicacao usa o conector GitHub autorizado, com permissao de escrita confirmada no repositorio.
- Nenhum teste pago, consulta de producao, Rails de producao, merge ou deploy foi executado nesta implementacao.

## Risco residual

A composicao da busca e deterministica e limitada a formas curtas de continuidade. Ela nao garante qual trecho o retriever encontrara nem qual resposta o modelo gerara. A validacao funcional com IA fica para depois do workflow aprovado e exige autorizacao propria. O novo log permite distinguir falta de recuperacao de uma decisao do modelo de nao usar trechos recuperados.

## Ampliacao da PR 3045

- A primeira implementacao nao contextualizava um numero como escolha de prazo nem uma resposta `sim`/`nao` a uma pergunta de procedimento. Seis exemplos novos foram adicionados; cinco falharam antes do ajuste.
- Numero ou `sim`/`nao` so ganham contexto quando o ultimo turno do assistente termina com uma pergunta. A pista usa apenas essa ultima pergunta, sem as afirmacoes ou cotacoes que a antecedem.
- Um detalhe curto do cliente (ate quatro palavras, sem ponto de interrogacao) conserva tambem o assunto anterior: no maximo dois turnos do cliente, mais a ultima pergunta. Pergunta completa ou mensagem mais longa continua sendo o assunto principal, sem puxar o assunto anterior.
- Permanecem os limites de oito mensagens de historico, 400 caracteres por pista e 160 caracteres na resposta curta. Nao ha regra de preco, produto, empresa, exame ou prazo especifico no codigo.
- RSpec isolado da busca: 17 exemplos, zero falhas. Specs de integracao do Answerer adicionados para escolha de prazo no simulador e resposta negativa no motor compartilhado; execucao Rails local continua bloqueada pelo runtime deste Mac.
- O RuboCop do CI e informativo: embora o job tenha concluido com sucesso, apontou cinco avisos nos nossos arquivos (complexidade da selecao de assunto e formatacao de specs). A selecao do turno ganhou um predicado nomeado e a formatacao foi ajustada, sem desabilitar cops nem alterar comportamento.
- A rodada funcional `44189369659`, commit `40ed6f459a9052c63a9fb81d6a054014ec158472`, concluiu com sucesso os 12 shards e agregador RSpec, Vitest e demais jobs. A limpeza posterior de lint passou novamente pelos 17 exemplos isolados e 5 verificacoes de callers/metadados; o push dessa limpeza exige sua propria rodada de CI.

## Bloqueio do CI, nao falha de deploy

- Na rodada `44167554317`, job `134337826122` (`RSpec (6/12)`), o `git fetch` do checkout comecou em 20:17:34 UTC e terminou em 20:53:22 UTC: aproximadamente 36 minutos. O RSpec iniciou somente em 20:54:42 e foi cancelado pelo teto de 40 minutos do job, sem falha de exemplo registrada.
- O agregador `RSpec` falhou porque recebeu `PARTES=cancelled`. Os outros onze shards, Vitest e demais verificacoes terminaram com sucesso. Nao houve deploy desta PR, que permanece aberta.
- Os ultimos deploys reais da main, `44137225375` (Autonomia) e `44137225417` (Hub2You), terminaram com sucesso para `c9d7d24f7a36834d9da95932c7ad3e646e069fc6`. O bloqueio identificado e o check do PR, nao esses deploys.
- O checkout desse job agora tem teto de cinco minutos. `GIT_HTTP_LOW_SPEED_LIMIT=1024` e `GIT_HTTP_LOW_SPEED_TIME=60`, limitados ao passo, abortam transferencias HTTP sem progresso suficiente e permitem as tentativas internas do checkout. O teto do job e todos os gates permanecem intactos.
- Semantica das variaveis conferida na documentacao oficial do Git: `https://github.com/git/git/blob/v2.43.0/Documentation/config/http.txt` (`http.lowSpeedLimit`, `http.lowSpeedTime`).
- YAML conferido localmente: checkout continua `actions/checkout@v4`, limites presentes somente no passo e teto do job preservado em 40 minutos. Nenhuma alteracao nos workflows de deploy, IAM, banco ou EC2.

## Historico do atendimento real: revisao da PR 3045

- O `Responder#history` inclui as mensagens incoming do turno atual; o Playground recebe somente os turnos anteriores. A busca de numero ou sim/nao rejeitava a pergunta anterior no atendimento, pois o ultimo item ja era do cliente.
- `Responder#answer` agora separa uma copia sem o turno incoming atual exclusivamente para construir `retrieval_query`, usando a contagem canonica de `current_turn_incoming`. Nao infere a direcao pela role, pois mensagens outgoing da equipe tambem podem ser mapeadas como `user`. A pergunta e o historico completos seguem intactos para o Answerer/modelo. Nao ha busca extra no banco, alteracao da instrucao nem chamada paga adicional.
- Quatro specs de integracao cobrem numero, negativa com varias mensagens incoming pendentes, primeiro turno sem pergunta anterior e preservacao da mensagem da equipe mapeada como `user`. O simulador e o override explicito dos outros callers nao mudam.
- Prova local isolada: numero e negativa falharam antes e passaram depois. O caso adicional da equipe tambem falhou ao inferir o turno por role e passou usando `current_turn_incoming`. Resultado: 9 testes/30 assercoes passaram, alem dos 17 exemplos RSpec da busca. Como o Ruby 2.6 deste Mac nao interpreta os metodos endless existentes no Responder, o harness temporario executa apenas o metodo `answer` real extraido do arquivo, com dependencias de framework substituidas. A execucao completa da classe e dos novos specs Rails depende do CI com Ruby 3.4.4.
- Na rodada anterior `44193873658`, o shard 11 falhou na instalacao apt de `libvips42 poppler-utils ffmpeg`, apos tres tentativas limitadas. Criacao do banco e RSpec nem iniciaram; o `NoDatabaseError` posterior foi do passo de diagnostico de formatos, nao a causa inicial. Nao foi registrada falha de exemplo nesse shard.
- O usuario desativou o merge automatico, confirmado pela API (`autoMergeRequest=null`, sem entrada na fila). A autorizacao cobre publicar a correcao e repetir/conferir o CI, sem merge ou deploy e sem reativar o merge automatico.

## CI: timeout dos mirrors regionais no apt

- Na rodada `44199479519`, os shards 1, 3, 4, 7, 8, 9, 10 e 11 falharam em `Instalar conversores nativos`, antes da criacao do banco e do RSpec. Os oito logs mostram tres tentativas de 240 segundos esgotadas para `libvips42 poppler-utils ffmpeg`; o agregador RSpec apenas refletiu essas falhas. Os outros quatro shards e Vitest passaram.
- Os downloads lentos usavam `us-east-2.ec2.archive.ubuntu.com`. O instalador trocava apenas `azure.archive.ubuntu.com`, deixando o mirror regional AWS como prioridade 1 mesmo tendo o oficial na lista.
- O mesmo rewrite agora contempla mirrors regionais AWS e Azure, direcionando-os para `https://archive.ubuntu.com/`. Caminhos, prioridades, mirrors de seguranca e terceiros sao preservados. Nao ha aumento de timeout, tentativa extra, pacote removido, teste pulado ou gate flexibilizado.
- Tres testes locais executam a expressao sed real do script com fixtures, sem sudo, apt ou rede: hosts regionais e prioridades, preservacao dos demais hosts e idempotencia. O caso AWS falhou antes e passou depois. O planejador do CI executa esses testes antes de criar os shards.
- Sem alteracao em workflows de deploy, infraestrutura ou producao. Merge automatico permanece desligado.
