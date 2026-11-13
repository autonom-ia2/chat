# Busca da base no simulador com respostas numéricas

Em 12 de novembro de 2026, o simulador enviava ao modelo o histórico da conversa, mas buscava na base com o número isolado. Isso podia deixar a tabela do serviço fora dos trechos enviados ao modelo.

A consulta usa até quatro mensagens recentes, limitadas a 400 caracteres por mensagem, quando o cliente responde com um número e o turno anterior do agente termina com uma pergunta de quantidade. A mensagem original e o histórico continuam sendo enviados ao modelo. O ajuste se aplica ao simulador.

## Validação local

- `ruby -c app/services/autonomia/agents/playground.rb` e `git diff --check` passaram.
- A validação isolada com Minitest executou o simulador com um substituto do Answerer. Antes do ajuste, os quatro casos que esperavam consulta contextual falharam. Depois, passaram os seis casos e as 21 asserções, incluindo duas quantidades, ausência de histórico, mudança de assunto, pergunta em inglês e limite do histórico.
- A suíte Rails requer Ruby 3.4.4 e Bundler 2.5.16, ausentes no ambiente local. A validação isolada conferiu os argumentos da busca, sem consultar o provedor de IA.
- A worktree não tinha o Husky instalado. O commit usou as verificações manuais acima, além do `bin/validate_push`.
- O GitHub recusou a publicação do branch com HTTP 403. A conta autenticada na CLI tem permissão `READ` em `autonom-ia2/chat`. O conector do GitHub disponibilizou acesso de escrita para publicar o branch de revisão.
