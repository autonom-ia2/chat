# "Criar com IA" e "Melhorar com IA": desenho e calibração (#1333)

Estes são os artefatos da calibração de 12/10/2026, guardados como estavam naquele dia:

| Arquivo | O que tem |
|---|---|
| `DESENHO.md` | Pesquisa (OpenAI e Meta), desenho de tela e proposta de implementação |
| `calibracao-12-10.md` | A bateria de 30 casos: 29/30 e 8/8 armadilhas no `gpt-6-luna` low, com custo de US$ 0,24 |
| `NOTA-canal.md` | Como o prompt e o schema viraram o canal `whatsapp_modelo` do `Ai::Redacao` |
| `SCHEMA.json` | O schema estrito calibrado, que o código monta em `Ai::Redacao::Canais::{Base,WhatsappModelo}.schema` |

O prompt que vale é o do código:
- `app/services/ai/redacao/prompts/comum.md`;
- `app/services/ai/redacao/prompts/whatsapp_modelo.md`.

Os dois juntos são a v3 citada nos documentos (`PROMPT.md`).

**O que não veio para cá.** Os arquivos de trabalho da bateria ficaram no scratchpad da sessão e não foram preservados:
`bateria.jsonl`, `gen_bateria.py`, `run_bateria.py`, `PROMPT_v1/v2.md` e `custo.json`.

A conferência com IA real depois da implementação está em `docs/audit/modelos-whatsapp-ia-1333.md`.

**Diferença em relação ao desenho.** A regra "no máximo 5 campos, um a cada 4 palavras" ficou só no prompt, fora da
conferência do código: no "Mais curto" de um texto com 4 campos, ela descartava todas as opções.

**Ajustes da calibração de 13/10, todos no código:**

| Caso | O que acontecia | Como ficou |
|---|---|---|
| AG11 | "Manter como aviso de serviço" ficava impossível quando a oferta estava num campo: tirar o campo descartava a opção | Em "manter como serviço" e "corrigir recusa", a opção pode tirar campo da base. Campo fora da lista continua barrado |
| PN12 | O campo de um botão (`publico.link`) contava como "campo novo no mais curto" | A comparação com a base olha só o corpo (`Canais::Base`, com OK do Agendamento). A lista permitida continua conferindo a soma de corpo, cabeçalho e botões |
| AG15 | O nome sugerido fora do formato descartava a opção | O nome é normalizado (minúsculas, sem acento, "_", até 40) e a opção fica |

**Ajustes da calibração r2 (v4), no código:**
- **AG15:** o campo da base que sai do corpo e vai para um botão de link ou telefone continua presente.
- **"Mais curto" medido:** o código mede o texto fixo (sem os campos), da base para a opção. Abaixo de 30% de corte, a
  opção cai (`corte_pequeno`); com 4 campos ou mais na base, o mínimo é 25%. Na gaveta, a tela mostra o corte medido
  no lugar do "o que mudou" escrito pela IA.
