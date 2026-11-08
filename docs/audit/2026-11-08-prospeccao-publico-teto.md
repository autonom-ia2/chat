# Teto do "Guardar para mandar mensagem" da Prospecção (#2695, F3b)

Decisão: `Autonomia::Prospecting::AudienceFromLeads::MAX_LEADS = 100`, o mesmo número no front
(`LIMITE_DO_PUBLICO` em `achar/composables/useDonoDaLista.js`).

## Por quê

O pedido é síncrono: cada lead passa pelo `ContactConverter` (contato e empresa, cada um na própria transação)
e o Público é gravado no fim, dentro da mesma requisição. O alvo da revisão (r1, item 5) era ficar abaixo de
~5 s por pedido.

## Método

- Spec descartável (fora do repositório), rodada uma vez, com `MAX_LEADS` trocado por `stub_const` para 1000.
- Uma conta e um administrador criados pela factory; leads de provedor `mock`, todos com telefone brasileiro
  válido e sem decisor, ou seja, cada lead vira um contato novo (o caminho mais caro).
- Para cada tamanho (500, 200 e 100, nessa ordem), mede `AudienceFromLeads#perform` com
  `Process.clock_gettime(Process::CLOCK_MONOTONIC)`, do início ao Público gravado.
- Sem dado de cliente: só dados gerados no banco de teste.

## Ambiente

- Teste local, MacBook Air M4, `RAILS_ENV=test`, Postgres e Redis de teste do MacCluster (banco próprio da
  worktree), Ruby 3.4.4.
- Um processo, sem concorrência. Produção tem outra máquina e outra carga: o número é ordem de grandeza, não
  promessa.

## Tempos

| Leads | Segundos |
|------:|---------:|
| 100   | 4,24     |
| 200   | 7,67     |
| 500   | 21,72    |

Cerca de 40 ms por lead, crescendo de forma linear. 100 é o maior número redondo abaixo de ~5 s.

## Se precisar de mais

Acima disso, o caminho é fila (job) com aviso de pronto, não aumentar o teto síncrono.
