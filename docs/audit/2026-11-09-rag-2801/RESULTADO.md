# #2801 — o material do agente vem primeiro (Refs #1431)

## Resultado em uma frase

A flag `agente_material_primeiro` faz a definição que está no material sair com a fonte marcada e deixa explícito que o
material vence o segmento e a memória. O acerto ficou igual.

## A causa do caso de produção

O caso: na conta 1, "o que é franquia?" foi respondido sem fonte, com o texto do segmento.

- **Busca:** descartada como causa. Em produção a busca é exata e devolve todos os trechos do agente.
- **Busca na web:** foi oferecida e não foi usada.
- **Reprodução local, no mesmo cenário:** segmento corretora, as flags da conta 1, as ferramentas e o caminho do Testar. O resultado foi 12 de 12 respostas tiradas do material e com fonte.
- **Leitura:** é variação do modelo, sob uma regra que permitia responder definição pela memória. Não é um defeito que se repete sempre.

## Placar

Medido em dois documentos públicos de condições gerais (auto e residencial), segmento `seguros/corretora`. Cada base
teve 3 perguntas de definição e 2 de resposta. Os gabaritos estão em `gabaritos/`.

| | acerto auto | acerto residencial | fonte auto | fonte residencial |
|---|---|---|---|---|
| ANTES (flag desligada) | 0,6 | 0,6 | 0,8 | 0,8 |
| DEPOIS (flag ligada) | 0,6 | 0,6 | 1,0 | 0,8 |

- **Definições:** 6 de 6 certas nas duas rodadas. Com a flag, todas as de auto saem com fonte. Na residencial, uma (LMI) segue certa e sem fonte.
- **Os 4 erros:** são das perguntas de resposta e não mudam com esta regra. A análise está no #2807.
- **Por que não houve placar completo depois:** custaria ~US$ 1,0 só para confirmar o que o subconjunto já mostrou.

## Revisão

- `agentes-ia-refactor-reviewer` e `caveman:cavecrew-reviewer`: nenhum achado crítico.
- **Corrigido:**
  - o texto do segmento não muda mais no Construtor, porque só o PromptBuilder do atendimento passa a opção;
  - "definições, conceitos" ficou no conhecimento geral, para o que o material não traz;
  - os specs agora cobrem o Guia pelo `system_key`, a Lia com trechos, o Construtor e a ordem real das fontes;
  - o `ingerir.rb` resolve o segmento antes de criar a conta.
- `agentes-ia-refactor-tester`: 23 cenários, 22 passaram. O que falhou era o vazamento para o Construtor, já corrigido.

## Custo

US$ 0,46 de IA paga na frente toda (prova da causa, ANTES e DEPOIS), dentro do teto de US$ 2,00 do RAG v2.
