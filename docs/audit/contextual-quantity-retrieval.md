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

A composicao da busca e deterministica e limitada a formas curtas de quantidade. Ela nao garante qual trecho o retriever encontrara nem qual resposta o modelo gerara. A validacao funcional com IA fica para depois do workflow aprovado e exige autorizacao propria. O novo log permite distinguir falta de recuperacao de uma decisao do modelo de nao usar trechos recuperados.
