# Automação livre · esperar a resposta (G11)

- **Épico:** #2414 · lacuna G11 do fechamento dos 20 exemplos (F9.6).
- **Destrava:** exemplos 1, 2, 10, 12, 15, 17, 19 e 20 ("espera a resposta, por até N; sem resposta, faz X").

## O que a receita escreve

Um "esperar até" cuja condição lê a resposta, com o prazo e o caminho "se vencer":

```json
{ "id": "espera", "tipo": "esperar_ate", "prazo": { "valor": 30, "unidade": "minutos" },
  "condicao": { "campo": { "$valor": "conversa.equipe_respondeu" }, "op": "igual", "valor": true },
  "se_vencer": [ { "id": "avisa_dono", "tipo": "avisar", "para": { "pessoas": [1] }, "texto": ["Ninguém respondeu"] } ] }
```

| Valor | Verdadeiro quando, **durante esta espera** |
|---|---|
| `conversa.cliente_respondeu` | chegou mensagem do cliente em qualquer conversa dele na conta (#2680: o e-mail abre outra) |
| `conversa.equipe_respondeu` | uma pessoa da equipe escreveu ao cliente, pela tela ou pelo app do celular (eco) |
| `conversa.responsavel_respondeu` | a pessoa atribuída à conversa (na hora da conferência) escreveu ao cliente pela tela; o eco do celular não conta, porque não diz quem mandou (lote 4, #2682) |
| `gatilho.repetiu` | o gatilho da execução aconteceu de novo (a Partida grava `repetiu_em` em vez de só descartar com `ja_aberta`) (lote 4) |
| `conversa.cliente_mandou_documento` | chegou do cliente uma foto ou um PDF (`FotoOuPdf`: figurinha, áudio, vídeo, texto e outro arquivo não contam), só na conversa da execução, a mesma que o `le: anexos` lê, e só se quem ligou a vê (G46, exemplo 14). O passo de IA logo depois lê com `le: anexos_novos` só o que chegou nesta espera |

G46 (o laço dos documentos, exemplo 14): o "decidir" com `de_novo.desde` volta ao "esperar até" que lê
`conversa.cliente_mandou_documento` (ou `conversa.cliente_respondeu`). Na volta dentro da mesma rodada, a janela começa
no instante em que esse "esperar até" foi cumprido, não agora: a 2ª e a 3ª foto que chegaram enquanto a IA lia a 1ª
contam (`EsperaNoExecutor#janela_da_espera`). Texto e áudio ("já mando") acordam a espera, mas não a cumprem: o prazo
não recomeça.

Lote 4 (#2682): no "esperar até" de um card, a mudança do card numa coluna que a receita lê (título, etapa, funil,
situação, valor, responsável, time, motivo da perda, atributos) acorda a espera na hora (`Crm::CardAvisaAutomacao` →
`Despertador.card_mudou`). Antes só a conversa e o contato acordavam.

"Equipe" usa a régua da IA que responde (`Autonomia::Agents::Operate::PessoaDaEquipe`). Não contam: a nota interna,
o robô, o envio automático em nome de alguém (follow-up, convite de reunião, campanha, regra), a mensagem da própria
automação e a mensagem que falhou na entrega.

**O eco do que nós mandamos não é a equipe.** A IA ou a automação mandam pelo WhatsApp, e o eco volta. Normalmente o
reconciliador o junta à bolha (`WhatsappHybrid::EchoReconcilerExtension`; na Cloud, pelo mesmo `source_id`). Quando o
eco chega antes de a bolha ter o id gravado, nasce uma mensagem a mais, sem remetente e com a marca do celular, igual
ao eco de uma pessoa que respondeu pelo app. A diferença está no id: o eco leva o wamid da mensagem que saiu (no
Híbrido, o id físico dentro dele, `WhatsappHybrid::Wamid`). Se outra mensagem de saída da caixa tem esse id, o eco é
dela e não conta. No exemplo 10, a agente de IA respondendo não encerra o "esperar a gerente responder". Nem a própria
mensagem da automação ("A Fernanda já está vendo seu caso"): na caixa Híbrida, o eco dela casa na bolha pelo
reconciliador e não vira mensagem. A `PessoaDaEquipe` (a régua da IA) não muda.

**A corrida do eco.** O eco vira mensagem nova justamente porque a bolha ainda não tem o id, e a espera acorda no
mesmo instante, quando ainda não há par. Regra: eco sem par, com uma mensagem nossa de saída da conversa ainda sem id
(robô, automação ou envio automático; não falhou; anterior ao eco), é **ambíguo e não conta agora**. A espera segue, e
no prazo a varredura confere a janela inteira de novo, com o id já gravado: o eco da bolha é descartado. Se uma pessoa
respondeu de verdade pelo celular nesse intervalo, a resposta conta, mas só no prazo (atrasada). Uma mensagem nossa
que nunca ganha id (envio preso, sem falha marcada) deixa os ecos seguintes da conversa ambíguos até o prazo.

**A mensagem conta no instante em que é lida.** Se a resposta da equipe for marcada como falha depois que a espera já
seguiu, o caminho não volta atrás.

## Decisões

- **"Durante a espera", não "desde o passo X".** O começo é o do "esperar até": na primeira conferência, agora; ao
  retomar, o prazo gravado menos a duração. Não precisa de coluna nova: a execução já guarda o `due_at`.
- **Só no "esperar até".** Fora dele (num "se", num filtro do gatilho, no caminho de uma ação) não existe começo de
  espera, e o valor daria sempre falso, em silêncio. O salvar recusa com a frase `resposta_so_na_espera`; sem o começo,
  o `Valores` lê vazio, nunca "respondeu".
- **Acorda na hora.** A mensagem já acordava o "esperar até" da conversa. Agora acorda também o do card cuja conversa
  principal é a da mensagem. Sem isso, o card só conferiria a resposta no fim do prazo: o resultado sairia certo, mas
  atrasado. Desde o #2680, a mensagem do cliente acorda também quem espera por ele em outra conversa, no card dele e
  no próprio contato.
- **O cliente responde de qualquer conversa dele** (#2680). O passo "email" abre uma conversa nova; a resposta chega
  nela, não na do alvo. Por isso `conversa.cliente_respondeu` lê do contato, e vale também no alvo contato. A equipe
  continua na conversa do alvo.
- **Resposta que chega depois do prazo** não muda o caminho já seguido: o "se vencer" já rodou.

## Editor

O catálogo marca os dois valores com `so_na_espera`. O editor só os oferece na condição do "esperar até" (o
`LivreCondicao` recebe `naEspera`); no "se", no "Só se" do gatilho e no texto da mensagem eles não aparecem.

## Fora daqui

- **Prazo como data** ("até dia X") **ou unidade nova** (meses): hoje o prazo é minutos, horas ou dias, e
  `due_at - prazo` volta exato ao começo. Com data, ou com meses (que não invertem exato), o começo deixa de sair dessa
  conta (`Executor#janela_da_espera`) e precisa ser gravado ao entrar na espera.
