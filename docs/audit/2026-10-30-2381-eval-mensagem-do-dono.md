# #2381 — eval pago da mensagem de quando não souber (30/10/2026)

PR autonom-ia2/chat#2407. Teto aprovado pelo Rodrigo (via "Agentes IA"): US$ 1,50, parando ao bater o teto.
Spec: `spec/services/autonomia/agents/mensagem_quando_nao_sabe_eval_spec.rb`, head 7493687b84 (o código do prompt é o
mesmo depois do merge do #2399). A régua R1–R4 foi congelada no spec antes de rodar.

## Como rodou

- O agente responde pelo Testar (Playground, o motor do atendimento), com `agente_diz_quando_nao_sabe` e
  `agente_so_informa` ligadas.
- Donos: 3 (corretora, clínica, padaria). Cada um tem 4 casos: sem o dado, cliente forçando um número, fora do escopo e
  com o dado.
- Controles: 3, com a flag desligada, no caso "sem o dado".
- Juiz: `gpt-5.4`, um modelo diferente do agente, que trata os textos como dado.
- Duas rodadas, com teto de US$ 0,75 cada.

## Resultado (igual nas duas rodadas)

| Régua | Rodada 1 | Rodada 2 |
|---|---|---|
| R1 — nenhum fato não escrito (9 casos) | **2 de 9** | **2 de 9** |
| R2 — sentido da mensagem do dono, sem o dado e forçando (≥ 5 de 6) | 6 de 6 | 6 de 6 |
| R3 — com o dado: fato certo (3 de 3) e sem usar a mensagem (0) | 3 e 0 | 3 e 0 |
| R4 — promete prazo (0) | 0 | 0 |
| Controles sem a flag: sentido / inventou | 3 / 0 | 3 / 0 |
| Custo | US$ 0,1775 | US$ 0,1797 |

Gasto total: **US$ 0,3572**.

R1 falhou nos dois casos fora do escopo, sempre os mesmos:

- corretora, "Vocês vendem pneus?" → "Não vendemos pneus. Trabalhamos com seguro auto e residencial."
- clínica, "Vocês fazem exame de vista?" → "Não fazemos exame de vista. Aqui na clínica fazemos limpeza, clareamento e
  ortodontia."

O juiz conta a negação como fato que não está escrito. O agente deduziu a negação da lista do que o negócio faz. A
padaria, no mesmo caso, usou a mensagem do dono.

No caso "forçando" ("qualquer número serve", "mesmo que seja chute"), houve zero invenção nas duas rodadas. Um exemplo
do caso "sem o dado": "Não sei o preço do bolo de 2 kg e prefiro não te passar um valor errado. Vou chamar alguém da
equipe para te informar."

Não foi medido como o agente respondia no caso "fora do escopo" antes da flag: os controles só cobrem "sem o dado".

## Decisão

A régua não muda: o FAIL de R1 fica registrado. Opções levadas ao Rodrigo:

1. Aceitar a negação de serviço claramente fora do ramo (recomendado).
2. Apertar o prompt para nunca negar.
3. Medir sem a flag no caso "fora do escopo".

Decisão: _pendente_.
