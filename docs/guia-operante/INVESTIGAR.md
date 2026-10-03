# Investigar um relato sobre o Guia (#861)

## O que existe

Cada pergunta ao Guia vira um **turno** guardado na conversa da pessoa (`autonomia_guide_turns`), com
a pergunta, a resposta e um **diagnóstico** do pedido: o que o Guia chamou, com quais argumentos
seguros, quanto tempo cada chamada levou, os fluxos da base que ele usou, a confiança, se a resposta
foi retida, quantas idas ao modelo, quanto custou e, se falhou, a classe do erro.

O diagnóstico **não** guarda instrução, catálogo, trecho da base, o conteúdo do que foi lido nem o
valor que a pessoa mandou gravar. Dos argumentos de cada ferramenta só ficam os que ela declara
seguros (`args_registraveis` em `app/services/autonomia/agents/tools/native/guia_*.rb`); dos outros
fica só o nome, em `omitidos`. De `ler_pagina` fica só o domínio. Quando o portão retém a resposta,
fica o texto retido, cortado em 2.000 caracteres.

A conversa fica guardada sem prazo, sem limpeza automática (decisão do Rodrigo, 03/10/2026). Só sai
quando a pessoa apaga pelo histórico do painel — e aí os turnos e o diagnóstico saem junto, sem volta.

## Como consultar

Pelo caminho de produção que já existe (SSM → `docker exec` no `chatwoot-web` → `rails runner`). Só
leitura. O `pedido_id` é o `id` que a tela recebe em `POST guide/chat` (aparece no log
`[autonomia][guide][chat_job] pedido=...` quando o job falha).

Um pedido, com a linha do tempo:

```sh
bundle exec rails runner 'puts Autonomia::Guide::Investigacao.new(pedido_id: "8c1f...-uuid").relatorio'
```

Os pedidos de uma pessoa numa conta, nos últimos dois dias:

```sh
bundle exec rails runner 'puts Autonomia::Guide::Investigacao.new(account_id: 18, user_id: 7, desde: 2.days.ago).relatorio'
```

Todos os pedidos de uma conta na última semana:

```sh
bundle exec rails runner 'puts Autonomia::Guide::Investigacao.new(account_id: 18, desde: 7.days.ago).relatorio'
```

O relatório mostra até 50 turnos, do mais antigo ao mais novo. Cada um sai assim:

```text
== pedido 8c1f... | 2026-10-03T14:02:11Z | conta 18 | usuário 7 | conversa 311 | tela inbox_view | done
  pergunta: quero que o time de marketing veja as conversas da caixa de vendas
  chamou: ler_da_conta | {"recurso":"inboxes"} | 412ms | 3100 caracteres
  chamou: executar_acao | {"acao":"POST inboxes/:id/members","descricao":"..."} | 380ms | 52 caracteres | sem valor: caminho_json, corpo_json
  decidiu: fluxos [#12 Caixas de entrada] | check - | confiança 0.71 | ancorada true | escalou false | retida false | telas inbox_view | artigos
  custo: US$ 0.0123 | 3 idas ao modelo gpt-5.6-sol (low) | tokens in 18200 cached 9100 out 640 | 11840ms
  respondeu: Pronto: a Carla agora é membro da caixa Vendas...
  fez: Coloquei a Carla na caixa Vendas. (ok)
```

## Do caso real à bateria

O relato vira teste, não `if` no código. O esqueleto de um exemplo para
`spec/services/autonomia/guide/bateria_admin_eval_spec.rb` sai da conversa do pedido, com as perguntas
reais na ordem e os recursos que o Guia leu:

```sh
bundle exec rails runner 'puts Autonomia::Guide::Investigacao.new(pedido_id: "8c1f...-uuid").cenario'
```

Antes de commitar o exemplo, **troque à mão** nomes, telefones, e-mails e números do cliente — o
esqueleto avisa. Depois monte o estado da conta com `conta_corretora!` e escreva o estado final
esperado no lugar do `# TODO`. Como rodar a bateria: [BATERIA.md](BATERIA.md).

## Custo do Guia na Gestão IA

Desde #861 o gasto do Guia sai com a etiqueta `guia` (e `guia_midia` para anexo e voz), no grupo
**Guia da Plataforma** da tela Gestão IA. Antes ele saía como `agente_resposta`, dentro de
"Assistente de respostas": a partir do deploy, esse grupo cai e o do Guia aparece. Não é aumento de
gasto, é o mesmo gasto separado.
