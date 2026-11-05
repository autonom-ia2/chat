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
| `conversa.cliente_respondeu` | chegou mensagem do cliente na conversa |
| `conversa.equipe_respondeu` | uma pessoa da equipe escreveu ao cliente, pela tela ou pelo app do celular (eco) |

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
reconciliador e não vira mensagem; se chegar antes do id, vira mensagem, mas é descartado pelo id. A `PessoaDaEquipe`
(a régua da IA) não muda.

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
  atrasado.
- **Resposta que chega depois do prazo** não muda o caminho já seguido: o "se vencer" já rodou.

## Editor

O catálogo marca os dois valores com `so_na_espera`. O editor só os oferece na condição do "esperar até" (o
`LivreCondicao` recebe `naEspera`); no "se", no "Só se" do gatilho e no texto da mensagem eles não aparecem.

## Fora daqui

- **Prazo como data** ("até dia X") **ou unidade nova** (meses): hoje o prazo é minutos, horas ou dias, e
  `due_at - prazo` volta exato ao começo. Com data, ou com meses (que não invertem exato), o começo deixa de sair dessa
  conta (`Executor#janela_da_espera`) e precisa ser gravado ao entrar na espera.
- "Esperar a resposta de uma pessoa específica" (a Fernanda, e não qualquer pessoa da equipe). Nos exemplos, quem
  responde é a responsável pela conversa, e "a equipe respondeu" basta.
