# #1802, lote 6: bloco de segmento dos agentes (19/10/2026)

**Commit avaliado:** f962e73386 da branch `feat/segmentos-f2-lote6-guia`.

**OK do Rodrigo:** "ok eval lote 6" (19/10, 10:46 UTC, no chat Agentes IA). Teto de US$ 2.

**Como rodou:** `spec/services/autonomia/agents/segmento_eval_spec.rb`.
- Passa pelo Responder de verdade, com a Fase 2 ligada e `AUTONOMIA_PACOTES_ENABLED` ligado.
- A conta tem nome neutro ("Grupo Vale") e o agente, instrução genérica. Assim, o tipo da conta só chega ao modelo pelo bloco.
- Duas variantes, intercaladas:
  - `sem_bloco`: `Bloco.for` devolve nil, como hoje;
  - `com_bloco`: o texto de `config/pacotes/seguros/<tipo>/agentes.md`.
- O juiz é o gpt-5.4 e não sabe qual variante está julgando.
- A Lia (`insurance_quote`) e a conta 43 ficaram fora. Os dados são de teste, no banco `chatwoot_test_1802l6`.

## Resultado: 3 execuções por cenário e variante

| Tipo | Sem bloco | Com bloco |
|---|---|---|
| Corretora | 6/9 | 9/9 |
| Seguradora | 9/9 | 9/9 |
| Insurtech | 9/9 | 9/9 |
| Saúde e benefícios | 8/9 | 9/9 |
| **Total** | **32/36** | **36/36** |

**Onde o bloco fez diferença:**
- **c2, "vou trocar de carro, preciso mexer no seguro?"**
  - Sem o bloco (0/3), o agente só diz que vai confirmar com a equipe.
  - Com o bloco (3/3), ele explica que a mudança é um endosso e passa para a equipe.
- **h1, "colocar minha filha no plano"**
  - Sem o bloco (2/3), uma resposta não pede nada.
  - Com o bloco (3/3), o agente pede a operadora e a idade da filha.

**Nenhuma execução com o bloco teve:**
- valor inventado (inclusive nos 4 cenários de preço);
- promessa de cobertura ou resultado;
- "segurado" sem apólice;
- a empresa no papel errado.

Também não houve cópia de trecho do bloco: nenhuma sequência de 6 palavras do bloco aparece nas respostas.

**Limite:** os cenários são de uma mensagem só, e o agente genérico já passa para a equipe com facilidade. Por isso a diferença aparece só nos casos que pedem vocabulário do ramo (endosso, inclusão de dependente).

## Gasto

US$ 0,46 de US$ 2,00, com o juiz incluído. Foram 72 execuções em 11 minutos.
