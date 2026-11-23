# #3143 — Guia: nunca deixar a pessoa no escuro

Data: 23/11/2026. Entrega 2 da lista de valor do Guia.

## Decisões

- **Interrupção sem botão e sem lista de palavras** (decisão do Rodrigo). A mensagem que chega durante o trabalho
  entra na fila do pedido em curso (`Pedido.acrescentar`, Redis, com trava). A cada rodada de ferramentas, o
  `Answerer` pergunta ao operador por `mensagens_novas` e as põe na conversa do modelo, depois das saídas da rodada,
  com um aviso curto. Quem decide parar, mudar ou seguir é o modelo (`guia-instrucao.md` §6.2).
- **Núcleo compartilhado.** O gancho no `Answerer` só age quando o operador responde a `mensagens_novas`. Só o
  `Contexto` do Guia responde; os agentes de atendimento não têm operador.
- **Mensagem depois da última rodada.** O fim do turno (`ChatJob#encerrar`, sob a mesma trava) pega o que sobrou na
  fila. Isso vira a pergunta seguinte, que roda logo depois e já lê a resposta no histórico. A tela sabe por
  `seguinte`/`tardias`.
- **Um Guia por vez.** A mensagem do meio não sobe um segundo job mexendo na mesma conta.
- **Etapa ao vivo.** É o nome da última ferramenta, numa chave à parte do pedido. A tela traduz para uma frase, sem
  inventar texto do servidor.
- **ActionCable fora** do escopo.

## Revisão independente (cavecrew-reviewer, 23/11)

3 bugs e 10 riscos; consertados no segundo commit:

- Mensagem lida no meio do trabalho só conta como respondida se o Guia respondeu de fato (texto). Em falha ou
  resposta retida, ela segue adiante como a pergunta seguinte (fila `:lidas`, decidida em `ChatJob#encerrar`).
- "Tentar de novo" manda a pergunta do pedido que falhou (guardada no pendente), não a última bolha da pessoa.
- Ao reabrir, a pergunta seguinte aparece depois das mensagens que ela cobre; o histórico do modelo segue a mesma
  ordem, e a junta cujo turno saiu da janela entra sozinha.
- O turno da mensagem do meio fica `junto` já na chegada, dentro da trava: recarregar a tela no meio não troca o
  pedido que ela acompanha.
- Trava ocupada ou Redis fora na chegada: a mensagem vira pergunta comum, sem erro 500. Só pedido da mesma conversa.
- Erro no fim do turno não reescreve a resposta pronta como falha. A pergunta seguinte não relê os anexos da anterior.
- A tela esvazia a fila de perguntas na falha, na conversa nova e na troca de conta; a mensagem marcada depois da
  resposta que devia ficar antes desce para o lugar certo; o campo só abre depois de o servidor aceitar a pergunta.
- Ficou de fora: `Redis::LockManager#unlock` apaga a trava sem conferir o dono. É lib compartilhada; o bloco do Guia
  mexe só em chaves do Redis, muito abaixo dos 10 s da trava.

## Limites conhecidos

- Anexo mandado no meio do trabalho espera o Guia terminar (os arquivos são lidos no começo do turno).
- Se o processo do job morrer sem passar pelo `discard_on`, a mensagem do meio fica sem resposta. A tela do pedido
  original termina em falha, com "Tentar de novo".
- Se a pergunta seguinte não puder ser enfileirada (Sidekiq/Redis fora), as mensagens que iam adiante ficam sem
  resposta; o log diz quantas.

## Validação local

- vitest dos componentes e da store do Guia: 172 arquivos, 1764 testes passando (depois da revisão).
- eslint sem erro (os avisos `no-missing-keys` são do catálogo `crm.json`, que já existiam).
- rubocop nos 16 arquivos Ruby tocados: sem ofensa (Ruby 3.4.4 local; o 3.4.13 do repo não está instalado no M4).
- `guia:check`, `central:check`, `i18n:fork:check`: em dia.
- rspec: só na CI (sem rspec local desde 12/11).
