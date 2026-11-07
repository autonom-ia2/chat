# Conversa de quem não tem e resposta em outra conversa (#2680)

Lote 3 da auditoria de 07/11 (`docs/audit/2026-11-07-automacao-auditoria-termos.md`, itens b e h), parte do #2414.

## O problema

- O card do lead do formulário nasce sem conversa e sem dono (`Crm::MetaAds::LeadForms::Importer#create_card`). O
  contato do gatilho `contato.data` também não tem conversa. Nesses alvos, mensagem, espera, IA e agente pulavam com
  `sem_conversa`, e nenhum passo abria uma conversa.
- O "esperar resposta" olhava só a conversa do alvo. O passo "email" abre uma conversa nova, e a resposta chegava nela.
- O texto e a situação da mensagem que a automação mandou não eram valores da receita.

## O que mudou

**Caixa da conversa nova.** O gatilho de card ou de contato aceita `conversa_nova: { caixa_id }`: a caixa por onde
abrir a conversa de quem não tem uma. Só caixas de WhatsApp, SMS ou API da conta (`ConversaNova::CANAIS`). Quem salva
e quem liga precisam poder começar conversa nela (`Acesso.comeca_conversa?`, a mesma pergunta do "Nova conversa" do
painel e do passo "email"), conferido ao salvar e a cada abertura. Sem acesso na hora de abrir, a automação pausa.

**O passo "mensagem" abre a conversa.** Sem conversa e com a caixa na receita, ele abre a conversa como o "Nova
conversa" (`ContactInboxBuilder` + `ConversationBuilder`) e manda, juntos. A janela, o modelo aprovado e o opt-out são
os de sempre: conversa nova no número oficial só sai com modelo. O que não sai (janela fechada sem modelo, valor vazio,
robô) desfaz a conversa, e nada fica vazio na caixa. Contato sem telefone pula com `contato_sem_telefone`.

**No card, a conversa vira a principal.** Efeito colateral registrado no passo (`conversa_principal_do_card`), que o
histórico mostra ("Abriu uma conversa, que virou a principal do card").

**Os outros passos usam essa conversa.** `Contexto#conversa` do card sem conversa principal e do contato acha a
conversa do contato na caixa da receita, a mais recente não resolvida. Espera, IA, aviso e agente passam a agir nela,
sem guardar nada na execução e sem migration. Com a caixa, o contato alcança também os valores `conversa.*`.

**Resposta em outra conversa.** `conversa.cliente_respondeu` conta a mensagem recebida em qualquer conversa do contato
na conta, e a mensagem nova acorda quem espera pelo contato (`Escuta#acordar` com `contato_id`).

**A mensagem que a automação mandou vira valor** (`Autonomia::Automacao::Envio`):

| Valor | O que lê |
|---|---|
| `envio.texto` | o texto da última mensagem que a execução mandou ao cliente (mensagem, escrever ou e-mail) |
| `envio.situacao` | saiu, entregue, lida ou falhou |

A mudança de situação acorda o "esperar até" (`Escuta#envio_atualizado`, pelo `message.updated` da mensagem com a
marca da automação). É o ramo "se o WhatsApp recusar, manda por e-mail o mesmo texto" sem gatilho de falha:

```json
[
  { "id": "aviso", "tipo": "mensagem", "texto": ["Sua apólice vence em 30 dias."] },
  { "id": "chegou", "tipo": "esperar_ate", "prazo": { "valor": 1, "unidade": "horas" },
    "condicao": { "campo": { "$valor": "envio.situacao" }, "op": "diferente", "valor": "saiu" } },
  { "id": "falhou", "tipo": "se", "condicao": { "campo": { "$valor": "envio.situacao" }, "op": "igual", "valor": "falhou" },
    "entao": [{ "id": "email", "tipo": "email", "caixa_id": 9, "assunto": ["Sua apólice"], "texto": [{ "$valor": "envio.texto" }] }],
    "senao": [] }
]
```

## Tela

No painel do gatilho de card ou de contato, o campo "Caixa para falar com quem ainda não tem conversa" (ChoiceSelect,
com "Nenhuma"). Trocar para outro gatilho de card ou de contato mantém a caixa; trocar para um de conversa a tira.

## Exemplos que avançam

- **2**, passos 2 e 3 (e 5, 6 e 8 quando a conversa existe): o lead recebe a mensagem e a espera lê a resposta.
- **6**, passo 2: a mensagem no contato do aniversário.
- **1**, passo 3: o ramo do envio que falhou. Passo 12: a resposta do e-mail conta.
- **19**, passos 2, 3 e 6: o mesmo texto por e-mail e a resposta na conversa do e-mail.

Nenhum fecha inteiro: o 19 ainda precisa do gatilho de falha (G8) e do texto da IA dentro do modelo; o 6, da data que
se repete todo ano e do modelo de propaganda; o 2, da origem do lead, do dono do lead e de decidir a cada resposta.

## Provas

`spec/services/autonomia/automacao/conversa_nova_spec.rb`, `valores_envio_spec.rb`, `resposta_spec.rb` e
`spec/fechamento/automacao/lote3_conversa_spec.rb` (montado e ligado pela API da tela).
