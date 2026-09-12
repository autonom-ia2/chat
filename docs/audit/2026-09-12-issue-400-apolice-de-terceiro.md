# Issue #400 — apólice em nome de terceiro: aproveitar o veículo, nunca o bônus (Part of #291)

Data: 2026-09-12
Branch: `feat/issue-400-apolice-de-terceiro` (de `origin/main` `22d5c9c333`)
Commit da entrega: `55fffdf17f`
Escopo: **texto e prova**. Uma regra nova na §6.2 do manual do especialista de auto, três âncoras
novas na spec de instrução, a assinatura md5 revisada, e um caso novo no harness de conversa
(`~/ops/agente-cotacao/teste-especialista/`, fora do repositório). **Nenhuma linha de código de
produção foi tocada** — o caso não precisa de código, e a §5 explica por quê.

## 1. A decisão do Rodrigo (12/09/2026)

Quando o cliente manda uma apólice que está em nome e CPF de outra pessoa, o especialista deve:

1. **aproveitar o que não depende do dono** — placa, CEP, modelo, ano;
2. **cotar como seguro novo** — sem marcar renovação, sem bônus, sem histórico de sinistros;
3. **avisar o cliente uma vez**, junto do primeiro preço, de que a cotação saiu sem bônus porque a
   apólice está em outro nome.

O motivo de não usar o bônus alheio: **bônus é pessoal e intransferível**. Cotar com o de terceiro
produz um preço que não se sustenta na emissão, e o cliente descobre no pior momento.

## 2. O achado: a recusa nunca foi regra escrita

Nas rodadas reais de 11/09 (conversa 5045) a Lia recusou duas vezes a apólice de outra pessoa —
inclusive quando o cliente informou só o número por texto. **Não havia regra mandando isso.** O
estado medido em `origin/main` `22d5c9c333`:

| Onde | O que dizia sobre titularidade da apólice anterior |
| --- | --- |
| `instrucoes/especialista_auto.md` §6.2 | exigia **companhia, número e fim de vigência**; titularidade, nada |
| `instrucoes/especialista_auto.md` §8 e §11 | "renovação exige a apólice anterior"; titularidade, nada |
| `instrucoes/principal.md` (arquivo inteiro) | menciona apólice em §2, §9 e §10 — sempre sobre **apólice ativa e suporte**, nunca sobre de quem é a apólice mandada para cotar |

A recusa era **conduta do modelo**, razoável e não especificada. O custo dela é jogar fora o
documento inteiro, inclusive placa, CEP, modelo e ano, que não dependem de quem é o dono. O que esta
entrega faz é **escrever a regra que faltava**, não afrouxar uma existente.

O caso novo é irmão do que já estava no fim da §6.2 ("se ele não tiver ou não quiser mandar a
apólice… cotar como seguro novo… diga a ele, uma vez, junto do primeiro preço"): **mesma saída,
gatilho diferente**. Por isso entrou no mesmo lugar, no mesmo tom, em cinco linhas.

## 3. O que mudou no manual (`especialista_auto.md` §6.2)

Parágrafo novo, inserido entre "…com a apólice em mãos você refaz." e "**Nunca marque renovação sem
a apólice.**" — **linhas 149 a 153** do arquivo, +6 linhas com a linha em branco:

> **Se a apólice que ele mandou estiver em nome e CPF de outra pessoa**, não a jogue fora: dela vem
> tudo o que não depende do dono — placa, CEP, modelo, ano. O resto, não: **cote como seguro novo**,
> sem marcar renovação, sem bônus e sem histórico de sinistros. Bônus é pessoal e intransferível, e
> cotar com o de terceiro dá um preço que não se sustenta na emissão. Diga a ele, uma vez, junto do
> primeiro preço, que a cotação saiu sem bônus porque a apólice está em outro nome.

Nada mais do arquivo mudou. `principal.md` **não foi tocado** (ver §7).

## 4. A guarda (`builder_instrucao_do_especialista_spec.rb`)

A guarda é textual porque **não existe validação por código**: quem lê o PDF e compara nome e CPF é
o modelo. Três âncoras novas na tabela `PROMESSAS`, uma por metade da decisão, e cada uma amarrada
ao que a sustenta no formulário:

| Âncora no texto | O que a sustenta |
| --- | --- |
| `placa, CEP, modelo, ano` | `vehicle.plate`, `vehicle.overnightZipCode`, `vehicle.fipeCode`, `vehicle.modelYear` expostos no formulário |
| `sem marcar renovação, sem bônus e sem histórico de sinistros` | `quotation.isRenewal`, `quotation.bonusClass`, `quotation.previousClaimsCount` existem e são **opcionais** (`obrigatorio == false`) — dá mesmo para não mandar |
| `a cotação saiu sem bônus porque a apólice está em outro nome` | Dois níveis, e vale distinguir (Codex, 12/09): no lado Rails a ausência É ausência — `AutoRenewal.new({})` devolve `renovacao?` falso, `bonus` nil, `sem_bonus?` falso, e `QuoteInput` não acrescenta bloco que o cliente não informou. No adapter, `quote-input.ts` NORMALIZA para seguro novo com `isRenewal false`, `bonusClass 0` e `previousClaimsCount 0` antes de enviar ao portal. Os defaults existem; o que eles não fazem é reintroduzir bônus de terceiro, que é o que a decisão exige |

Assinatura do texto: `3eba319bca1e6159e950def73a2f91ab` → **`8c5d2facc72b7d93721af0d178506045`**.

**Por que a terceira âncora precisa existir:** o aviso automático da ferramenta
(`Native::InsuranceQuote::AVISO_SEM_BONUS`) dispara em `quote_input.renewal.sem_bonus?`, que exige
`isRenewal == true` com `bonusClass` nil. Neste caso a renovação **não** é marcada — logo o aviso
automático **não** dispara, e quem avisa é o texto do especialista. Sem a âncora, apagar o aviso do
manual não reprovaria nada além do md5.

## 5. O harness de conversa (fora do repositório)

`~/ops/agente-cotacao/teste-especialista/harness.py` ganhou a **metade D**: o manual **do
repositório** (não a cópia `instrucao_hoje.md`, de 10/09) + o formulário de 84 campos + a consulta
de placa, com um caso só — o cliente manda o CPF dele e o texto de uma apólice da HDI em nome de
"MARIA APARECIDA DE SOUZA", CPF diferente, com placa BAS2768, CEP 12605620, bônus 7 e 0 sinistros.
A checagem lê o **argumento da ferramenta**, não a prosa.

    MANUAL=<worktree>/app/services/autonomia/insurance/quote_agent/instrucoes/especialista_auto.md \
      uv run python3 harness.py D

Rodado em 12/09 contra `gpt-5.6-sol` (chave do cofre `claudete-ops`; a consulta de placa roda de
verdade e é gratuita). Argumento que chegou na ferramenta, no primeiro turno:

    insured.document = 05288896805        (o CPF de quem cota)
    address.zipCode  = 12605620           (do documento)
    vehicle.plate    = BAS2768            (do documento)
    vehicle.modelYear = 2022              (do documento)
    vehicle.isZeroKm = false
    quotation.isRenewal = false

Veredito: **passou** nas sete checagens — renovação não marcada, sem `bonusClass`, sem
`previousClaimsCount`, sem companhia/número/vigência da apólice alheia, placa e CEP do documento,
CPF de quem cota e não o do titular.

**Uma checagem foi afrouxada, com motivo.** A primeira rodada reprovou por exigir o CEP em
`vehicle.overnightZipCode`, e o modelo o escreveu em `address.zipCode`. A descrição do próprio campo
diz *"CEP onde o veículo DORME, **se for diferente do endereço do segurado**"* — com um CEP só, o
lugar certo é o endereço. A checagem passou a aceitar os dois e a **imprimir onde caiu**; o que a
#400 exige é que o CEP tenha vindo do documento, não em qual campo ele foi parar.

**O que o harness não prova:** o aviso ao cliente. Ele para no argumento da ferramenta, antes de
qualquer preço — o aviso sai junto do primeiro preço. Isso é o que a prova real da §8 cobre.

## 6. Validação

| Comando | Resultado |
| --- | --- |
| `rspec spec/services/autonomia/insurance/quote_agent/builder_instrucao_do_especialista_spec.rb` | **37 examples, 0 failures, 0 pending**, `errors_outside_of_examples = 0` |
| `rspec spec/services/autonomia/insurance/quote_agent` | **107 examples, 0 failures, 0 pending**, `errors_outside_of_examples = 0` |
| `rspec spec/services/autonomia/agents` | **622 examples, 0 failures, 0 pending**, `errors_outside_of_examples = 0` |
| `rubocop spec/.../builder_instrucao_do_especialista_spec.rb` | **1 file inspected, no offenses detected** |

Banco: `POSTGRES_DATABASE=chatwoot_test_e400` (criado com `db:create db:schema:load`).

### Prova por mutação

Árvore commitada (`55fffdf17f`); cada mutação edita o manual, roda a spec de instrução e restaura
com `git checkout --` (o script confere que o arquivo voltou byte a byte). Script:
`/private/tmp/.../scratchpad/mutacoes_e400.py`.

| Mutação | Falhas | Quem reprovou |
| --- | --- | --- |
| **M1** apaga o parágrafo do caso novo | 4 | as **três âncoras** novas + o md5 |
| **M2** inverte a regra ("o bônus viaja com o veículo, aproveite a classe e os sinistros"), âncoras intactas | 1 | o **md5** — que é exatamente o que ele existe para pegar: prosa que muda de sentido sem mexer nas âncoras |
| **M3** remove a promessa de avisar o cliente | 2 | a âncora **«a cotação saiu sem bônus porque a apólice está em outro nome»** + o md5 |

## 7. Pendência: `principal.md` não foi tocado

A issue pede para conferir se a Lia antecipa a recusa **antes** de acionar o especialista. Não
editei o arquivo — outra entrega está mexendo nele agora, e dois patches no mesmo texto dariam
conflito. O que a leitura encontrou:

- **Não há regra de titularidade** em `principal.md`. As três menções a apólice (§2, §9, §10) são
  sobre **quem já tem apólice ativa e quer suporte** — sinistro, guincho, boleto, segunda via. Um
  cliente que manda a apólice de outra pessoa para cotar não cai em nenhuma delas.
- **O trecho que pode antecipar a recusa** é o raciocínio da §3, linha 34:

  > `- **Validar:** os dados estão completos e coerentes? Falta alguma coisa?`

  "Coerentes" é onde cabe a conclusão de que uma apólice de outro CPF é incoerente — e aí a Lia
  pergunta ao cliente em vez de acionar o especialista, que é quem passou a saber o que fazer. A
  §5 manda "parafraseie, não reinterprete" e "você não sabe cotar nada sozinho", o que empurra para
  o lado certo, mas nada nomeia o caso.

**Recomendação (não executada):** se a medição mostrar a Lia recusando antes de acionar, a correção
mínima é uma frase na §5, junto de "Você não sabe cotar nada sozinho": *documento do cliente vai
para o especialista como veio, mesmo quando parece não bater com ele — quem decide o que aproveitar
é o especialista do ramo.* Uma linha, sem tocar na §3.

Outras pendências:

- **Metades B e C do harness não rodam**: as duas leem `instrucao_v3.md`, que não existe na pasta.
  Achado de passagem, registrado no `LEIAME.md`; hoje só A e D rodam sem preparar arquivo.
- **O aviso ao cliente não tem prova automática** — nem código (o `AVISO_SEM_BONUS` não cobre este
  caso, §4) nem harness (§5). A prova é a conversa da §8.

## 8. Roteiro da prova real

Repetir o caso de 11/09 em conversa, com o agente de cotação ligado:

1. O cliente manda o **PDF de uma apólice de terceiro** (nome e CPF diferentes dos dele) e pede
   renovação informando **o próprio CPF**.
2. Esperado: a Lia **não recusa** e aciona o especialista; a cotação sai **como seguro novo** —
   `isRenewal` não marcado, `bonusClass` e `previousClaimsCount` ausentes, sem seguradora, número
   nem vigência anterior —, com **a placa e o CEP vindos do PDF**.
3. Junto do **primeiro preço**, uma frase dizendo que a cotação saiu **sem bônus porque a apólice
   está em outro nome** — uma vez só, não repetida a cada lote de preços.
4. Variante a medir: o cliente informa **só o número da apólice por texto**, sem PDF — o caso em que
   a Lia recusou em 11/09 sem sequer ter o que conferir.

O que olhar no banco: o argumento gravado da chamada de `cotar_seguro` (bloco `quotation` vazio de
bônus e renovação) e o texto entregue ao cliente no primeiro lote de preços.

## 9. Risco

Baixo e contido ao texto. A regra **amplia** o que o especialista aceita (deixa de descartar o
documento) e **restringe** o que ele escreve no formulário (bônus e sinistros de terceiro nunca
entram) — as duas direções erram para o lado seguro: o preço sai como o de quem faz o primeiro
seguro, que é o que a emissão vai sustentar. O único jeito de a regra causar dano é o modelo
aproveitar o bônus assim mesmo.

**O que as guardas garantem, e o que não garantem** (Codex, 12/09). Âncora e md5 protegem a
INSTRUÇÃO: ninguém muda ou apaga a regra sem que a spec reprove e sem revisar a tabela `PROMESSAS`.
Elas não executam o modelo e, portanto, não garantem obediência. A obediência foi medida onde dava
para medir sem custo: o harness (§7) rodou a conversa real contra o modelo e o pedido saiu com
`isRenewal=false`, sem `bonusClass` e sem `previousClaimsCount`, com placa e CEP vindos do documento
— 7 de 7. O que continua sem medição é o AVISO ao cliente, que só aparece junto do primeiro preço:
fica para a prova real da §8.
