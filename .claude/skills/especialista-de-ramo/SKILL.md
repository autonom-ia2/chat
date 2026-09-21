---
name: especialista-de-ramo
description: >
  Use ao criar ou estender o especialista de um ramo de seguro do Agente de Cotação (residencial,
  condomínio, empresarial, vida, acidentes pessoais, fiança locatícia, viagem, celular, bike, vida
  global), ao fazer a Lia chamar um ramo novo, ou ao mexer no formulário, nas travas ou no manual de
  um ramo. Dispare ANTES de escrever código ou instrução. A receita é uma ordem de oito fases com
  critério de passagem: pular fase é o erro que ela existe para evitar.
---

# Especialista de um ramo novo: seguir a receita

Existe uma receita, escrita a partir de auto e mantida neste repositório. Não improvise a ordem e não
reinvente os critérios: cada um foi descoberto pagando por ele em produção.

## Passo 1: leia os dois documentos, nesta ordem

1. `docs/insurance/receita-de-ramo/modos-de-falha.md`: as falhas reais de auto, com sintoma, causa e o
   teste que pega cada uma. **Antes** de escrever código, não durante o debug.
2. `docs/insurance/receita-de-ramo/RECEITA.md`: as oito fases e o critério de cada uma, mais o estado de
   partida medido.

Leia de verdade. O valor está nos detalhes, que não estão resumidos aqui de propósito: resumo copiado
diverge do original.

## Passo 2: confira o estado de partida antes de construir

A receita traz uma tabela do que já existe e do que falta. Ela envelhece. Antes de construir qualquer
coisa, confira no código e na produção as linhas que importam para o seu ramo. Declarar ausente algo que
existe manda construir do zero o que estava pronto; declarar presente algo que não existe manda procurar
código fantasma.

Um ramo novo mexe em **dois repositórios**: `autonomia-adapters` (o portal, o formulário e as travas) e
este (a ferramenta, o especialista, a Lia e a prova). A tabela "Onde cada coisa mora" da receita diz
onde.

## Passo 3: um item de tarefa por fase, e não pule

Fase 0 é uma saída: se o ramo não cota pelo adapter hoje, ou nenhuma corretora real o tem ativo, pare e
diga isso. Critério vermelho bloqueia a fase seguinte.

## Passo 4: antes de declarar pronto

A seção "Antes de declarar pronto" da receita vale em toda fase. Em resumo do que ela exige, sem
substituí-la: o check verde da PR não conta; teste novo é visto falhando antes; expectativa reescrita é
provada por mutação; revisão adversarial independente; merge e deploy só com OK do Rodrigo.

## Quando achar um buraco na receita

Corrija a receita e o catálogo de falhas no mesmo PR que fechar o buraco. Não escreva a correção só aqui.
