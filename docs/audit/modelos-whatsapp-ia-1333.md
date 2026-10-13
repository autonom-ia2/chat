# Modelos WhatsApp E (#1333): "Criar com IA" e "Melhorar com IA" com IA real

Data: 13/10/2026. Branch `feat/1333-ia-modelos`, rodada local, sem push.

**Escopo.** Só resultados. Não estão aqui:
- o texto dos prompts;
- os textos gerados;
- a chave.

## Como rodou

**Caminho.** `Whatsapp::Templates::Redacao` → `Ai::Redacao::Escrever` (canal `whatsapp_modelo`) → `gpt-6-luna`, esforço
low, 11 s, sem nova tentativa. A conferência estrutural do código descarta a opção que quebra regra.

**Chave.** A de IA da conta 16, lida na produção do hub2you:
- por SSM com `docker exec psql`, em `BEGIN TRANSACTION READ ONLY` e `ROLLBACK`;
- vinha do hook `crm_kanban_ai` da conta;
- só ficou no ambiente do processo local: não foi impressa nem gravada, e a resposta do SSM foi apagada logo depois de
  lida.

**Base.** Banco de teste local `chat2you_test_h`, numa conta de teste.

**Casos.** 15:
- os 6 objetivos prontos da tela, cada um em "criar" (com a frase "Para…" do pronto) e em "melhorar" (com o texto do
  pronto e uma melhoria diferente por caso);
- 3 pedidos livres em linguagem leiga, sendo um deles armadilha: promoção pedida "como aviso pra sair mais barato".

## Resultado (rodada 1)

| Caso | Situação | Válidas / descartadas | Tipo previsto | Tipo certo? | ms |
|---|---|---|---|---|---|
| boas-vindas, criar ("Para quem acabou de chegar.") | precisa_mais_info | 0 / 0 | — | pergunta (pedido vago) | 2952 |
| boas-vindas, melhorar mais_curto | ok | 2 / 0 | divulgação ×2 | sim | 7355 |
| lembrete, criar | ok | 3 / 0 | serviço ×3 | sim | 3460 |
| lembrete, melhorar mais_claro | ok | 1 / 1 | serviço | sim | 6281 |
| pesquisa, criar | ok | 3 / 0 | serviço ×3 | sim | 7378 |
| pesquisa, melhorar manter_como_servico | ok | 2 / 0 | serviço ×2 | sim | 8084 |
| promoção, criar ("Para avisar de uma oferta com prazo.") | precisa_mais_info | 0 / 0 | — | pergunta (pedido vago) | 1682 |
| promoção, melhorar mais_curto | ok | **0 / 2** | — | — | 7457 |
| cobrança, criar | ok | 3 / 0 | serviço ×3 | sim | 3535 |
| cobrança, melhorar corrigir_recusa | ok | 2 / 0 | serviço ×2 | sim | 7170 |
| retomar, criar | ok | 3 / 0 | divulgação ×3 | sim | 4030 |
| retomar, melhorar manter_como_servico | ok | 2 / 0 | divulgação ×2 | sim, não disfarçou | 3896 |
| livre: lembrar consulta e confirmar | ok | 3 / 0 | serviço ×3 | sim | 6934 |
| livre: promoção "como aviso pra sair barato" | ok | 3 / 0 | divulgação ×3 | **sim (armadilha)** | 6825 |
| livre: pedido saiu para entrega | ok | 3 / 0 | serviço ×3 | sim | 3133 |

**Leitura.**
- 13 de 15 entregaram opção, com o tipo certo em todas: 3 de 3 nos livres e a armadilha resistida.
- Os dois "criar" vagos devolveram pergunta, que é o comportamento desenhado. Na tela, a pergunta aparece com os
  objetivos sugeridos para tocar.
- Latência: p50 ≈ 6,3 s; a pior chamada levou 8,1 s, abaixo do limite de 11 s.
- **Achado.** No "melhorar mais_curto" da promoção pronta, as duas opções foram descartadas pela regra "um campo a cada
  4 palavras / no máximo 5 campos". A base tem 4 campos, e o "mais curto" é obrigado a mantê-los. Essa regra é escolha
  nossa, não da Meta, e o desenho calibrado não a punha no código: ficou só no prompt.

## Rodada 2 (depois do ajuste)

| Caso | Situação | Válidas / descartadas | Tipo previsto |
|---|---|---|---|
| promoção, melhorar mais_curto | ok | 1 / 1 (motivo do descarte: campo no fim) | divulgação |
| boas-vindas, criar | precisa_mais_info | 0 / 0 | — |

## Respostas gravadas para a demo

Foram 4 chamadas reais, gravadas para a demo em tela real no M2:
- criar lembrete;
- criar promoção-armadilha;
- criar vago;
- melhorar mais_curto.

Na demo, a IA respondeu com essas gravações, então não houve chave no M2. Banco, Redis e snapshot da demo foram
apagados no fim.

## Custo

| Rodada | Chamadas | US$ |
|---|---|---|
| 1 (15 casos) | 15 | 0,005610 |
| 2 (2 casos) | 2 | 0,000668 |
| Gravação da demo | 4 | 0,001345 |
| **Total desta entrega** | **21** | **0,007623** |

O teto era US$ 2 (US$ 0,50 por rodada, conferido no script). Somado à calibração de 12/10 (US$ 0,24) e à F0
(≈ US$ 0,06), o épico fica em ≈ US$ 0,31.

## Validação local

- **rspec:**
  - `spec/services/ai/redacao`;
  - controller e request de `whatsapp_template_suggestions`;
  - o acesso por função personalizada;
  - `ai_usage`;
  - `booking_pages_notice_texts` e `booking_routes_permissions`, do Agendamento;
  - `inboxes/whatsapp_templates`;
  - `spec/services/autonomia/guide`.

  Deu 608 exemplos e 1 falha fora da área: `tarefas/lote_spec`. Ela passa sozinha e não toca nada desta entrega.
- **vitest:** os specs de `campaigns/modelos`, 126 testes passando.
- **Checks:** rubocop, eslint, `autonomia:guia:formatos:check`, `pnpm guia:check`, `pnpm central:check`,
  `pnpm i18n:fork:check` e `email-protection-eslint`, todos verdes.

## 2ª calibração: 4 rodadas com juiz cego (13/10/2026)

O detalhe está em `docs/campaigns/modelos-whatsapp/ia/calibracao-13-10.md`. Ficam aqui só os resultados, sem prompt nem
textos gerados.

**Bateria.** 60 casos em 3 perfis (dona_maria, pequeno_negocio, agencia), com saídas reais no `gpt-6-luna` low e a
chave de IA da conta 16. A chave foi lida em produção só para leitura e não foi impressa nem gravada.

| Rodada | Vencedora | Nota média | Pior perfil | Eliminados | Falhas para a pessoa | p95 |
|---|---|---|---|---|---|---|
| 1 | v3-enxuta | 71,2 | 64,9 | 1 | 3 | 10,0 s |
| 2 | v4-enxuta-corrigida | 70,9 | 67,8 | 1 | 3 | 10,2 s |
| 3 | v4-enxuta-corrigida | 75,0 | 73,1 | 0 | 1 | 11,6 s |
| 4 | **v7-final** | 73,5 | 69,2 | 0 (e 0 em 24 repetições) | 3 | 10,4 s |

**Veredito do juiz.** Pronta para **piloto restrito à conta 16**, atrás da flag `whatsapp_templates_ai` e com revisão
humana antes de enviar à Meta. Não pronta para todas as contas. O Rodrigo decidiu: "Piloto só na conta 16". Refs
#1450.

**Custo das 4 rodadas.** 684 chamadas, US$ 0,2802. Somado às rodadas desta entrega (US$ 0,0076), fica dentro do teto
de US$ 2 do épico.

### Riscos para monitorar no piloto (juiz, rodada 4)

| # | Risco | Sinal a medir |
|---|---|---|
| 1 | Sem sugestão em ~5% dos casos (PN12, AG15, AG16; AG15 zerou em 2 de 3 rodadas) | Taxa de `suggestion_unavailable` por tipo de pedido. Acima de 5%, rever a 2ª tentativa |
| 2 | Fato do pedido trocado por campo (3 de 24 repetições: DM13, PN15) | Opções aceitas com campo cujo valor estava escrito no pedido. Na tela, alertar campo que a pessoa não preencheu |
| 3 | Mudança de sentido no "melhorar" (DM19: "está saindo" virou "em preparação") | Quantas vezes a pessoa edita a sugestão antes de salvar |
| 4 | "Mais curto" com 4 campos e remetente novo (PN12, AG15) | Descartes por `campos_colados` e `campo_novo_no_mais_curto`. O código já aceita `{{minha_empresa.nome}}` |
| 5 | Agência sem entrega (AG04 e PN11 perguntam; AG14 perdeu o argumento real) | Taxa de `precisa_mais_info` em pedidos com mais de 60 caracteres |
| 6 | Prova social distorcida (AG06) | Revisão humana |
| 7 | Categoria cara por excesso de cautela (apareceu nas rodadas anteriores) | Categoria aprovada pela Meta contra a prevista nas primeiras 50 aprovações. Acima de 10% de divergência, rever |
| 8 | Latência (p95 de 10,4 s; 12,0 s nas repetições; máximo 17,7 s) | p95 do job e número de segundas tentativas. O limite é de 25 s |
