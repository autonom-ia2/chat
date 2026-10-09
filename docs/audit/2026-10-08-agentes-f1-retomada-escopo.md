# F1 — retomada: escopo da evidência e correção do H1

## Escopo

Esta nota registra somente a conferência do H1 do estado vazio e do plano visual
atual de F1. Não altera produto, harness, fixtures ou critérios de aceite. A
retomada não aprova F1, F2–F7, merge, fila, deploy ou produção.

## H1 do estado vazio

O arquivo chamado de `rule_base.scss` no planejamento é
`app/javascript/dashboard/assets/scss/_base.scss`. Nas linhas 5–12 ele aplica
`text-n-slate-12` diretamente a `h1`–`h6`; a cor não é herdada do ancestral.
O estado vazio usa `bg-n-navy text-white` no `section` de
`AgentsEmptyHero.vue:48-50`. O H1 atual contém `text-white` diretamente em
`AgentsEmptyHero.vue:59-61`, portanto a correção mínima vence a regra direta sem
alterar o stylesheet global. O mesmo padrão já aparece no hero de Automação em
`AutomacaoHeroi.vue:105-130`.

Isso corrige a causa estática do `F1-FINAL-01`; ainda é necessário confirmar a
cor computada no navegador. O STOP32 registrou o H1 em `#1c2024` sobre
`#0d2344`, contraste `1,04:1`, no job
`m2-9fa254c66a264561be46c7861b3835d3`. A próxima execução deve ser tratada como
validação nova, não como aprovação retroativa.

## Matriz visual atual

`agents.config.ts:50-86` define quatro projetos: 1440/400 px, claro/escuro.
`visual.spec.ts` define sete grupos (`:45`, `:92`, `:122`, `:191`, `:229`,
`:260` e `:294`), ou 28 combinações planejadas. O grupo de mutação é
intencionalmente executado só em 1440 claro (`:298-301`), portanto há três
skips de repetição documentados; isso deve aparecer separado de falha e de
cenário não executado.

| Grupo F1 | Evidência atual | Afirmação permitida |
| --- | --- | --- |
| Lista normal, resumo, cartões, overflow e alvo de toque | Navegador real passou somente em 1440 claro; a suíte unitária/API teve 224 testes aprovados | A implementação respondeu nesse cenário; não há aprovação dos outros projetos |
| Vazio e herói | Captura real chegou ao vazio e falhou no contraste do H1; `text-white` está aplicado agora | Estado vazio ainda precisa passar Axe e ser recapturado |
| Menu, foco e confirmações sem escrita antecipada | Há asserções no grupo visual e provas unitárias; não executado na final32 | Contrato preparado; sem prova visual final |
| Loading e erro de transporte | Há cenários nomeados no spec; não executados na final32 | Planejado, ainda sem captura real aceita |
| Só ver | Há fixture/asserções do perfil viewer; não executado na final32 | Permissão preparada, sem prova de tela real/painel |
| Pausar, religar e excluir | Fluxo real e persistência estão escritos no grupo de mutação, mas a final32 parou antes dele | Sem afirmação de persistência visual final até a execução prevista |

O resultado final32 foi: um cenário de lista 1440 claro aprovado, o vazio
reprovado e 26 combinações sem execução após a falha. A suíte de 224 testes
passou, mas não substitui capturas reais nem a conferência Axe em cada projeto.

## Grupos F1 cobertos e faltantes

O planejamento mínimo de F1 (`design/F1.md:169-191`) tem quatro grupos:

- **Editor com agentes:** fixture local e lista normal existem; a prova de
  navegador aceita apenas o caso 1440 claro já executado. Lia, interno, E4,
  sem canal e E6 ainda precisam ser vistos nos quatro projetos aplicáveis.
- **Rascunhos e retomada:** contratos e specs de API/rota existem, mas a
  matriz visual atual não clica `Continuar` nem comprova a hidratação da thread
  na tela real. Continua pendente.
- **Só ver:** a lista viewer é planejada e tem asserções, porém abrir o painel,
  chegar a “Como está indo”/“Testar” e provar ausência de escrita ainda não têm
  captura real aceita.
- **Vazio, carregamento e erro:** o vazio tem a causa do contraste identificada;
  loading, erro, retry e vazio de só ver aguardam execução nos projetos
  restantes.

Pausar/religar e excluir são mutações associadas aos dois primeiros grupos,
não uma aprovação independente. As famílias de criação, Conte, Teste, Lia e
ajudante interno, Ligue, resultado de ligar, painéis completos e conversa
(`aceite-telas-reais.md:73-153`) continuam fora da entrega visual de F1 e não
devem ser anunciadas como concluídas; elas pertencem às etapas F2–F7.

Afirmação honesta para a entrega neste ponto: há contratos unitários/API
aprovados e uma correção mínima identificada para o H1, mas a primeira tela
real ainda não tem aceite global. O aceite depende da nova execução dos quatro
projetos e do registro separado de PASS, FAIL, SKIP e não executado.
