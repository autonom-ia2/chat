# Contexto da busca contado por interacoes do cliente

Data: 2026-11-18. Branch nova a partir de main; entrega anterior preservada.

## Evidencia e decisao

- Na investigacao anterior, metadados de recuperacao mostraram uma correcao de quantidade sem a tabela de precos entre os trechos recuperados. Nao houve erro de provider ou timeout. A tabela estava pronta na base.
- A consulta textual nao estava no log. Sua reconstrucao local pelo codigo mostrou perda do assunto inicial apos respostas divididas do assistente: oito mensagens brutas podiam representar poucas interacoes do cliente. A ultima pergunta de procedimento ainda entrava na busca de quantidade.
- O ajuste usa os limites existentes de `Config`: ate 25 interacoes `user`, com teto de 150 mensagens. Respostas divididas do assistente nao consomem o limite de interacoes, mas continuam contando no teto de seguranca.
- A selecao do assunto e dos detalhes acontece nessa janela antes do corte de 400 caracteres por pista. Permanecem no maximo dois trechos do cliente. Uma pergunta completa ou assunto mais longo continua prevalecendo sobre o assunto anterior.
- Somente numero isolado ou sim/nao acrescenta a ultima pergunta do assistente. Correcao textual de quantidade usa o assunto e os detalhes do cliente, sem incluir perguntas de procedimento ou cotacoes anteriores do assistente.
- Pergunta e historico enviados ao modelo, override explicito, instrucao, conhecimento, tools e handoff nao mudam. Nao ha regra de empresa, segmento, produto, preco ou prazo especifico.
- Nao ha migration, dependencia, variavel de ambiente ou chamada adicional de IA/banco. Nao ha override correspondente em `enterprise/`.

## Validacao local

- Antes do ajuste: 22 exemplos isolados do `RetrievalQuery`, quatro falhas, reproduzindo perda de assunto, pergunta irrelevante e respostas divididas.
- Depois do ajuste: os mesmos 22 exemplos passaram. Cobrem sequencia de quantidade 3/10/2, detalhe do cliente, numero como prazo, sim/nao, mudanca de assunto, limites exatos de 25 interacoes e 150 mensagens e preservacao dos textos originais.
- Um spec de integracao do Answerer foi ampliado para exigir o assunto em historico com mais de oito mensagens, tanto no Playground como no motor compartilhado, preservando pergunta e historico do modelo. A execucao desse spec depende do CI Rails.
- Harness temporario dos callers existentes: 9 testes, 30 assercoes passaram. Usa construtores reais e o metodo `Responder#answer` extraido, substituindo dependencias de framework/geracao; nao equivale a executar a suite Rails.
- O RSpec isolado executa a classe real sem Rails. Seus dois limites sao carregados das declaracoes reais de Config; o restante da aplicacao nao e inicializado.
- A tentativa da suite Rails focada ficou bloqueada antes dos testes: Ruby local 2.6.10, sem Bundler 2.5.16; projeto requer Ruby 3.4.4. Validacao completa e lint do projeto devem ser conferidos no CI.
- `git diff --check` e `sh bin/validate_push` passaram.
- Nenhuma chamada paga, acesso a producao, mudanca de dados, merge ou deploy nesta implementacao.

## Limite da prova

Os testes comprovam a composicao da consulta, nao garantem a classificacao vetorial nem a resposta final do modelo. O teste funcional pago depende de autorizacao propria apos deploy aprovado. Esta PR nao ativa merge automatico nem altera workflows.
