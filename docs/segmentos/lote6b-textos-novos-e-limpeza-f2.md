# F2 corretora · Lote 6b: telas novas e limpeza do pacote

autonom-ia2/chat#1802, 21/10/2026. Vem em cima do lote 6 e entra na mesma leva da fila, com um deploy só (OK do Rodrigo ao plano: "Pode seguir assim").

O texto geral mudou depois dos lotes 1 a 5: entraram a tela Números por papel (#1871), os Anúncios sem login e o arquivamento "não é negócio" da IA de etapa (#1970), e o #1885 trocou "negócio" por "card" no geral. Este lote leva as telas novas à língua dos pacotes de seguros e tira da corretora o que ficou igual ao geral.

## O que entra

### Telas novas no pacote

| Onde | Geral | Seguros | Corretora | Saúde e benefícios |
|---|---|---|---|---|
| Números, topo | "{n} vendas" | "{n} seguros fechados" | herda | "{n} planos fechados" |
| Números, botão | "negociações paradas" | herda | "cotações paradas" | herda |
| Números, A IA te ajudou | "te passou {n} clientes… viraram venda" | "te passou {n} pessoas interessadas… fecharam o seguro" | herda | "…fecharam o plano" |
| Anúncios sem login, situação | "Comprou" | "Fechou o seguro" | herda | "Fechou o plano" |
| Anúncios sem login, exemplo | "Promoção de inverno", "Frete grátis" | "Seguro auto com desconto", "Proteja sua família" | herda | "Plano de saúde para sua empresa" |
| Histórico do card | "Não é negócio: ninguém pediu o que a gente vende." | "Não é venda: ninguém pediu um seguro." | herda | "…um plano." |

"Pessoas interessadas" porque "cliente" é só quem já comprou. "Venda", "Vendendo" e as regras de **Como contamos** ficam como no geral: os pacotes de seguros já falam em venda ("Funis de venda", "meta de vendas").

### Guia

- Números (`ver_meus_numeros_do_mes`): o topo fala em seguros/planos fechados, e na corretora a lista é de cotações paradas.
- Anúncios sem login (`ver_anuncios_sem_login`): "venda é o card com o seguro fechado", não "marcado como ganho"; na corretora, "Cotações" no lugar de "Propostas", como no painel.

### Limpeza

- Saem 40 chaves do pacote da corretora (painel, en e pt_BR) que ficaram iguais ao que ela herdaria, quase todas pelo #1885. Com elas fora, a corretora passa a acompanhar as próximas mudanças do texto geral nessas telas.
- Ficam as que só se repetem num idioma: o pacote tem de ter as mesmas chaves em en e pt_BR (`i18n:fork:check`).
- No servidor não havia repetidas (só uma, em en, que fica pelo mesmo motivo).

## Conferido sem mudança

- Central de Ajuda: nenhum artigo herdado pelas camadas fala em ganho ou perda do card (o que aparece é "ganhou o selo", "chamada perdida").

## Validação

- `guia:check`, `central:check` e `i18n:fork:check` em dia; prettier nos pacotes.
- Vitest do painel (i18n, CRM, agentes, modelos): sem falha.
- RSpec do Guia, da Central, dos segmentos e dos requests de pacote: sem falha (pendentes = eval pago).
