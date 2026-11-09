# Juiz do autoteste do material — eval pago (#2444)

Data: 04/11/2026. OK do Rodrigo no chat: teto de US$ 0,20. Gasto total: cerca de US$ 0,02, somando todas as rodadas abaixo.
Modelo: o de produção do juiz (`Crm::Ai::Config::MODEL_CLASSIFY`).
Cenas: inventadas, sem nenhum dado de cliente, em `spec/services/autonomia/agents/material/juiz_do_autoteste_eval_spec.rb`.
Como rodar: `AUTONOMIA_EVAL_PAGO=1 JUIZ_AUTOTESTE_EVAL=1 OPENAI_API_KEY=… bundle exec rspec <arquivo>`.
Opcionais: `JUIZ_AUTOTESTE_EVAL_VEZES=5` e `JUIZ_AUTOTESTE_EVAL_SAIDA=<json>`.

## Resultado final (head deste PR)

- **26 cenas × 5 repetições: 130/130.**
- Escola: 12 cenas.
- Oficina: 14 cenas.

## Linha de base: juiz antigo (base 6d8c89a751), mesmas 26 cenas, 1 vez

O juiz antigo errou 8 das 26 cenas:

| Cena | Esperado | Antigo disse |
|---|---|---|
| E1 seguiu a regra do dono (não coletar dados) | certo | errado |
| E5 passou o preço contra a regra do dono | errado | certo |
| E7 a referência não responde à pergunta | nao_se_aplica | errado (o juiz antigo não tinha essa saída) |
| E9 recusa que cita um fato real dos trechos | recusou | inventou |
| O8 recusa e cita outro fato real | recusou | inventou |
| O9 pergunta "de fora" que os trechos respondem | nao_se_aplica/recusou | inventou |
| O11 seguiu o limite duro (guardrail) | certo | errado |
| O13 fato que está nas regras do dono | recusou | inventou |

## O que as rodadas mostraram, em ordem

1. **E9 reprovada.** A cena estava errada: a resposta dizia "a devolução depende do contrato", e isso não está nos trechos. O juiz acertou. A frase virou a cena própria E9b, que espera `inventou`. A E9 ficou sem essa frase.
2. **E7 virou "errado" em 1 de 3.** O juiz passou a conferir o item antes de julgar a resposta. Resultado: 60/60 e depois 100/100.
3. **Revisor.**
   - Ele apontou que `nao_se_aplica` poderia esconder uma invenção. O prompt agora diz: quando a resposta afirma algo que nem os trechos nem as regras do dono sustentam, o item é `errado`. A cena E7b cobre esse caso.
   - O juiz não recebia os limites duros. Cena O11.
   - O trecho chegava ao juiz cortado em 240 caracteres. Agora o juiz recebe o trecho inteiro, até o maior pedaço que a base grava (cena O12).
   - Fato que está nas regras do dono: cena O13.
   - Comando escondido num trecho: cena O14.
4. **E7 de novo, 1 de 3.** A resposta da cena dizia "o material fala dos cursos de inglês", que não está nos trechos daquele item. Pela regra nova, o juiz tinha razão. Tirei a frase da cena.
5. **Resultado final: 130/130.**

## Limites

- As cenas são curtas e inventadas. O teste real é o autoteste nas contas piloto, depois do deploy.
- O item `nao_se_aplica` ainda não aparece na tela, só no número: #2540.
