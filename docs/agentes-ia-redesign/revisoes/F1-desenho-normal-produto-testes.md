# Revisão normal F1 — produto/UX e testes

**Alvo:** `docs/agentes-ia-redesign/design/F1.md` (DRAFT), SHA-256
`edbda1a48d316a1b7895854c506ee5601e1f02baeeec9a0cbb4ebda219770aad`.

**Fontes confrontadas:** `PRD.md` (CA-LISTA e §6.1),
`mockup/src/screens-list.js`, `mockup/src/data.js`, `mockup/src/kit.js`, o contrato
B2 da lista e o relatório técnico independente `revisoes/F1-desenho-normal-tecnica-seguranca.md`.

**Escopo e limite:** revisão normal independente pela lente de produto, UX e
testes. Não alterei F1, o mockup ou código de produto. Não executei RSpec,
build, navegador, banco, serviço ou produção; não tratei captura do mockup como
tela real.

## Resultado

**PARADA — F1 não está pronta para implementação ou aceite nesta forma.** Há
três contratos de produto que divergem da fonte visual ou ficaram abertos no
desenho, além de uma lacuna de fixtures para os cenários obrigatórios. O
relatório técnico independente registra separadamente os bloqueios de E2m e da
mutação PATCH; este parecer não os duplica.

## Achados

### F1-UX-01 — alta — quem só vê perde “Abrir” nos rascunhos

**Prova:** F1 determina que quem só vê deve ter “Abrir” em E1–E4 e chegar ao
painel de leitura (`design/F1.md:88,114-115`). O mesmo contrato é obrigatório
em `PRD.md:901-903` (CA-LISTA-15). No protótipo, porém, `agentCard` deixa a ação
principal vazia quando `status === 'todo'` ou `status === 'ready'` e `can()` é
falso (`mockup/src/screens-list.js:17-21`); `can()` considera qualquer perfil
`view` sem permissão de edição (`mockup/src/kit.js:15`). O botão “Abrir” só é
renderizado no ramo de agente ligado/pausado. Portanto, ao usar “Ver como: só
ver”, justamente os cartões E1–E4 não oferecem a leitura prevista.

**Causa:** a condição visual foi modelada como “ação de rascunho = editar”,
sem o fallback de leitura que a regra de permissão exige.

**Efeito:** uma pessoa com acesso de leitura vê o agente, mas não consegue abrir
o painel/Como está indo/Testar. A captura pode parecer protegida por não mostrar
controles de escrita, mas a jornada obrigatória de CA-LISTA-15 fica quebrada.

**Correção mínima:** ajustar a fonte do protótipo para renderizar “Abrir” em
E1–E4 para quem só vê, mantendo Continuar, Ligar, interruptor e menu ocultos;
depois alinhar F1 e o caso de aceite com essa variante. A implementação real
deve provar a ausência de escrita e o GET do painel, sem liberar o editor.

### F1-UX-02 — alta — os números da lista não têm contrato de campo fechado

**Prova:** F1 só nomeia `stats.week` e `stats.month` e diz que ambos são
respostas/passagens (`design/F1.md:30-41`), sem fixar os campos que o cartão
consome. O B2 já define `week.replies`, `week.handoffs`, `month.replies` e
`month.handoffs` (`design/B2.md:94-124`), enquanto o protótipo lê séries
indexadas por `7`/`30` e o campo `handed` (`mockup/src/screens-list.js:9-12`;
`mockup/src/data.js:43-45,56-58`). O aceite exige que “passou N” venha de
`stats` e bata com ListStats/Analytics no mesmo período
(`PRD.md:878-881`, CA-LISTA-05).

**Causa:** F1 remete ao B2 sem transportar para o contrato da tela a forma
final do payload nem a tradução do contador de handoff para o texto “passou”.

**Efeito:** uma implementação que copie a leitura do protótipo procura
`stats[7].handed`, mas o envelope real entrega `stats.week.handoffs`; o número
fica ausente ou zero. Uma implementação que preserve o envelope real precisa
de uma decisão explícita de mapeamento para não introduzir outra forma de
payload. Em ambos os casos, a pessoa pode receber números que não batem com a
aba Como está indo.

**Correção mínima:** fechar em F1 a estrutura `week/month.replies/handoffs`, o
texto correspondente (“passou” = `handoffs`), as janelas inclusivas e o
comportamento interno sem números. O teste deve comparar os valores com
Analytics para 7/30 dias e provar uma única consulta para N agentes; o mockup
deve ser lido como referência visual, não como contrato de índice.

### F1-UX-03 — média — o motivo de teste invalidado ficou genérico

**Prova:** F1 diz apenas que E3 mostra um “motivo localizado” quando
`test_invalidated_by` é `person` ou `material` (`design/F1.md:47-55`). O PRD
fecha duas frases distintas: material novo deve dizer
“{A} {nome} aprendeu um material novo. Teste de novo antes de ligar.” e mudança
da pessoa deve dizer “Parou em Teste · Algo mudou depois do teste.”
(`PRD.md:874-877`, CA-LISTA-04). O `agentLine` atual do protótipo trata todo
rascunho pelo passo e não diferencia `test_invalidated_by`
(`mockup/src/screens-list.js:2-4`), portanto não oferece uma referência visual
para esses dois estados novos.

**Causa:** o desenho preservou o nome do campo do backend, mas não fechou as
chaves de i18n, parâmetros e gênero que transformam a causa em uma mensagem
compreensível.

**Efeito:** material novo pode aparecer apenas como “Parou em Teste”, e uma
alteração da pessoa pode parecer uma falha genérica. A pessoa não sabe o que
precisa testar de novo antes de ligar, contrariando a jornada simples e o
aceite textual.

**Correção mínima:** especificar as duas chaves/cópias de i18n e o mapeamento
fechado de `person`/`material`, com `{nome}` e gênero derivados de `voice`.
Adicionar ao protótipo e ao cenário real um E3 de cada causa, incluindo
feminino, masculino e ajudante quando aplicável, sem deduzir gênero pelo nome.

### F1-TEST-01 — média — os cenários citam estados que o protótipo não instancia

**Prova:** o cenário 1 pede “Clara externa com canal e estatísticas, Lia
`insurance_quote` e interno” e precisa conferir E5/E6/E4
(`design/F1.md:137-145`). A fonte de dados do mockup instancia apenas Clara e
Lia, ambas externas e `status: 'on'` (`mockup/src/data.js:33-62`); não há
agente interno, estado pausado, E4, E1, E2, E2m ou E3 nessa lista. O modelo
interno aparece somente como opção de criação (`data.js:72-73`), e o cenário
de vazio não resolve essa lacuna.

**Causa:** o desenho lista os estados esperados, mas não nomeia fixtures reais
por estado e deixou o protótipo de lista com apenas a amostra de dois agentes
ativos.

**Efeito:** antes de implementar, não há como conferir lado a lado o cartão
interno, o pausado, o pronto para ligar e os rascunhos contra a referência
visual. Um teste pode declarar cobertura usando Clara/Lia ativas, sem jamais
renderizar as variantes que determinam texto, ação, números e permissões.

**Correção mínima:** fechar no plano de cenário as fixtures locais e os nomes
dos casos para cada estado (incluindo interno, E4, E5, E6, E1, E2/E2m e E3),
com a mesma fonte visual ou divergência registrada. As fixtures devem vir da
API/banco local de teste; não copiar os IDs e números da conta que aparecem no
mockup.

## Pontos conferidos sem achado novo

- D7 está coerente com a decisão nova: F1 mantém a conexão na área central e
  usa `settings_inbox_new` apenas como orientação/atalho, sem rota `from`, QR,
  número, token ou criação de caixa em Agentes (`design/F1.md:20-21,99-100`,
  `PRD.md:94,329,376`).
- O gate de edição da lista, o perfil só ver e a ausência de controles para
  SuperAdmin nesta tela estão descritos em termos compatíveis com CA-LISTA-07,
  CA-LISTA-08 e CA-LISTA-15 (`design/F1.md:85-92,102-119`).
- Loading, vazio, erro, retry explícito, 400 px, claro/escuro, foco e o uso de
  componentes sem `<select>` nativo estão cobertos no desenho
  (`design/F1.md:102-135`) e não substituem a captura real posterior.
- O envelope seguro não expõe `instruction`, `scaffold`, mensagens ou tokens;
  o campo `voice` está nomeado, mas o próprio F1 registra que o GREEN do B2
  ainda está pendente (`design/F1.md:41,43-45`). Isso é uma dependência de
  entrada e deve continuar como gate, não como aprovação desta revisão.

## Conclusão

F1 permanece **DRAFT — não aprovado**. Os achados acima precisam de uma causa
registrada e de uma única correção antes da checagem final prevista no handoff.
Ainda não há telas reais, capturas locais, aprovação visual, backend GREEN,
merge, fila, deploy ou produção.

## Validação desta revisão

- leitura estática do PRD, CA-LISTA, mockup, B2, F0, rotas e relatório técnico;
- hashes registrados no cabeçalho para tornar o alvo reproduzível;
- nenhum teste, build, navegador, banco, serviço, produção, commit, push ou PR.
