# Parte 6 — Nova oportunidade: screenshots reais

Capturas integrais da aplicação local, com Rails, APIs e PostgreSQL reais e cadastros fictícios. Não são imagens conceituais nem produção AWS. Os pixels não foram editados.

| Arquivo | Estado para aprovação |
|---|---|
| [01 — Nova oportunidade](01-nova-oportunidade-desktop.png) | Duas seções, busca inicial e nenhuma validação prematura. |
| [02 — Contato existente](02-contato-existente-selecionado.png) | Pessoa e empresa canônicas; dados comerciais separados. |
| [03 — Sem vínculo](03-oportunidade-sem-vinculo.png) | Criação somente da oportunidade e retorno à escolha de contato. |
| [04 — Mais opções](04-mais-opcoes-preservadas.png) | Descrição, prioridade, previsão, score, moeda e caixa opcional preservados. |
| [05 — Descartar](05-confirmacao-de-descarte.png) | Confirmação nativa antes de perder o preenchimento. |
| [06 — Criada](06-oportunidade-criada-com-relacionamento.png) | Card real criado, aberto no mesmo contato em Relacionamento. |
| [07 — Celular](07-nova-oportunidade-mobile.png) | Viewport de 390px e ação fixa de criação. |
| [08 — Notebook](08-nova-oportunidade-notebook.png) | 1366×768, com lateral de 640px. |
| [09 — Repetição segura](09-retentativa-sem-duplicacao.png) | Falha de rede provocada após gravação real. O teste repetiu a solicitação e recuperou o mesmo ID. |

Desktop 1620×928; notebook 1366×768; celular 390×844. A lateral usa os mesmos 40rem de Editar funil e respeita o viewport. `manifest.json` registra 14 verificações, posições/dimensões, hashes das fontes e imagens, console e a falha controlada. `persistence.json` confere contagens antes/depois: quatro oportunidades confirmadas, nenhuma pessoa, empresa, mensagem ou conversa adicional.

O cenário 09 não é uma falha espontânea do produto: o servidor confirmou a criação, o roteiro interrompeu deliberadamente somente a entrega da resposta e a interface refez a mesma solicitação. Não foram fabricadas respostas de sucesso.

A Nova oportunidade com contato novo e empresa opcional continua pendente de implementação em outro incremento. A próxima parte depende do aceite de Rodrigo. Sem merge ou deploy.

[Testes, contratos e limitações](../../../audit/2026-09-30-792-crm-relationships-part-6.md).
