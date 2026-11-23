# Fatia 6 — Escolher por qualquer informação e guardar como grupo (#3168)

Épico #3048. Leva para a lista nova de pessoas o que a tela antiga de Contatos tinha no filtro
avançado e nos Segmentos. Decisão do Rodrigo (19/11): migrar.

**Regra de ouro:** UI-UX e design premium, com uma jornada tão simples que uma pessoa de QI 70, sem
conhecimento de tecnologia, consegue usar. Valem as regras de `BLOCO-A.md` (palavras do dia a dia, uma
ação principal, 44 px, foco preso, sem `<select>` nativo, 390 px em uma coluna).

Palavras proibidas na tela: "segmento", "filtro avançado", "atributo", "operador", "query", "E/OU".
Usamos: "grupo", "informação", "condição" só se não houver outra, "tudo isso", "pelo menos uma".

## Escopo

- **Só a aba Pessoas.** A tela antiga de Empresas não tinha filtro avançado nem segmento, e o servidor
  não tem filtro de empresas. A aba Empresas segue com cidade e quando chegou.
- **Mesmo dado da tela antiga.** As condições usam as mesmas chaves e regras de `contacts/filter`
  (`lib/filters/filter_keys.yml`, `Contacts::FilterService`). O grupo guardado é um `custom_filter`
  de contato (`filter_type: contact`), por pessoa da equipe, como os Segmentos de hoje.
- **Fora:** apagar a tela antiga (fatia 8); filtro de empresas; contagem ao lado de cada grupo guardado.

## Jornada

### 1. "Mais filtros" ganha "Por outra informação"
A gaveta de hoje continua igual em cima (empresa, etiqueta, cidade, quando chegou, compras, total).
Embaixo, uma seção nova:

- Título: **Por outra informação**. Uma linha de ajuda curta: "Escolha uma informação e o que ela
  precisa ter."
- Botão **+ Escolher uma informação** (link, 44 px). Cada toque cria uma linha.
- Cada linha, empilhada em 390 e na gaveta (a gaveta tem 26 rem):
  1. **Informação** (ChoiceSelect com grupos: "Da pessoa" e "Campos da sua conta").
  2. **Como** (ChoiceSelect, opções dependem do tipo da informação). Some quando o tipo tem uma
     opção só (Bloqueada, Não tem a etiqueta, sim/não da conta): a linha vai direto ao valor.
  3. **Valor** (campo certo para o tipo; some quando o "como" não pede valor).
  4. Botão de lixeira "Tirar esta informação" (ícone, 44 px, aria-label).
- Com 2 ou mais linhas aparece, acima delas, a escolha **Das informações abaixo, mostrar quem tem:**
  `Tudo isso` |
  `Pelo menos uma` (grupo de rádio, mesmo visual da `ChaveDosGrupos`). Padrão: Tudo isso.
  Uma escolha só para todas as linhas (a tela antiga deixava misturar E e OU linha a linha; ninguém
  usa: `custom_filters` está vazia em produção).
- Linha incompleta (falta valor) não vai para a busca: "Ver resultado" mostra o erro na linha
  ("Escreva o que procurar.") e não fecha.
- "Limpar" também tira as linhas.
- A lixeira leva o foco para a "Informação" da linha seguinte (ou da anterior, se era a última) ou,
  sem linhas, para "Escolher uma informação".

### Informações e "como"
Da pessoa (mesmas chaves de `contactProvider.js`):

| Informação na tela | chave | tipo |
|---|---|---|
| Nome | name | texto |
| E-mail | email | texto |
| Telefone | phone_number | texto |
| País | country_code | lista (países) |
| Última conversa | last_activity_at | data |
| Bloqueada | blocked | sim/não |
| Não tem a etiqueta | labels | lista (etiquetas), só `não é` (not_equal_to) |
| Relação (só se a conta tiver) | relacao | lista |

Fora do catálogo (revisão do diretor de arte): Cidade, Empresa e Chegou em, que já estão em cima na
gaveta, e Código da pessoa (identifier), que o leigo não conhece. "Tem a etiqueta" também já está em
cima (Etiqueta); embaixo fica só o "não tem".

Campos da sua conta: todos os campos personalizados de contato, com o tipo deles (menos os que têm a
chave de uma informação da pessoa, inclusive city, company_name, created_at e identifier).

"Como", por tipo (rótulo na tela → operador do servidor):

- texto: `tem o texto` (contains), `não tem o texto` (does_not_contain), `é exatamente` (equal_to),
  `é diferente de` (not_equal_to).
- igual / lista / número / link: `é` (equal_to), `não é` (not_equal_to).
- sim/não (checkbox, bloqueada): `é` com valor Sim | Não.
- data (padrão): `depois de` (is_greater_than), `antes de` (is_less_than), `há mais de … dias`
  (days_before, valor em número).
- data de campo da conta: as mesmas, mais `está preenchido` (is_present) e `está vazio`
  (is_not_present).

Valor: texto → campo de texto; lista → ChoiceSelect (etiquetas e países com busca por digitação);
data → campo de data igual ao da ficha (`dataDoCampo.js`, formato do idioma, botão Calendário,
exemplo "Ex.: 25/12/2026" gerado pelo formato do idioma do painel);
número → campo numérico; sim/não → rádio Sim | Não.

### 2. Na lista, o resultado e "Guardar como grupo"
- O botão segue "Mais filtros (3)" — cada linha conta 1.
- Com qualquer filtro ligado, ao lado do botão aparece **Guardar como grupo** (ícone de marcador,
  slate faded). Some quando não há filtro e em Meus grupos (lá, mudar o grupo mostra a faixa do item 3).
- **O grupo guarda o que a pessoa vê**: a visão de onde veio (conversa ou compra), a pílula escolhida
  (inclusive um grupo de compra), a busca e os filtros (com as condições e o "juntar").
- Diálogo **Guardar como grupo**: "Que nome você quer dar a este grupo?" + campo (placeholder "Ex.:
  Clientes de Campinas") + embaixo "Entra quem: …" (a frase de quem entra, ex. "Clientes · Cidade:
  Campinas") e "O grupo se atualiza sozinho: quem passar a ter isso entra." + **Guardar** (principal)
  e Cancelar. Nome vazio: erro na linha. Nome repetido pode (como hoje).
- Guardou: aviso "Grupo guardado." e a lista passa para **Meus grupos** com o novo escolhido, **sem
  mudar quem aparece**: a lista mostrada é a mesma de antes de guardar.

### 3. "Meus grupos"
- A chave acima das pílulas: **Mostrar os grupos:** **Por conversa | Por compra | Meus grupos**.
- Em Meus grupos, as pílulas são os grupos guardados da pessoa, na ordem em que foram criados, sem
  número. Escolher um reaplica tudo o que ele guardou (pílula, busca, filtros; a linha e as ordens
  seguem a visão de onde ele veio). As pílulas de conversa não aparecem: Meus grupos é uma visão
  própria.
- Sem nenhum guardado: a lista some e fica um cartão com uma frase, "Você ainda não guardou nenhum
  grupo.", e um botão, **Escolher quem entra**, que volta a Por conversa e abre "Mais filtros" (régua
  vazio = frase + botão; troca a linha de ajuda sem botão da versão anterior).
- Com um grupo guardado escolhido, embaixo das pílulas: "Entra quem: …" (a frase de quem entra) e três
  links: **Mudar quem entra** (abre a gaveta no modo do grupo: rodapé com **Guardar no grupo** como
  principal e "Ver sem guardar" secundário), **Trocar o nome** (mesmo diálogo, título "Trocar o nome
  do grupo") e **Apagar grupo** (confirmação: "Apagar o grupo "X"? As pessoas não são apagadas, só o
  grupo." — Apagar em vermelho, Cancelar).
- Com um grupo escolhido, "Mais filtros" também abre no modo do grupo. Se a lista na tela ficar
  diferente do grupo guardado (busca, pílula ou filtros), aparece uma faixa acima da lista: "Você
  mudou quem aparece neste grupo." com **Guardar no grupo** (principal) e **Voltar ao que era**.
- Apagou: aviso "Grupo apagado." e volta para a primeira pílula de Meus grupos (ou o cartão vazio).

## Telas para o mockup (prints 1440 e 390, dados fictícios)

1. `01-gaveta-sem-condicao` — gaveta aberta, seção "Por outra informação" só com o botão.
2. `02-gaveta-duas-condicoes` — duas linhas (campo da conta "Plano" é "Ouro"; "Última conversa" há
   mais de 90 dias) e "Das informações abaixo, mostrar quem tem: Tudo isso".
3. `03-gaveta-data` — uma linha de data ("Última conversa" há mais de 90 dias) e uma com erro de valor.
4. `04-lista-com-filtro` — lista filtrada, "Mais filtros (2)" e "Guardar como grupo".
5. `05-dialogo-guardar` — diálogo com o nome escrito e "Entra quem: …".
6. `06-meus-grupos` — chave em Meus grupos, três pílulas, uma escolhida, "Entra quem", os links e a lista.
7. `07-meus-grupos-vazio` — sem grupo guardado: cartão com frase e "Escolher quem entra".
8. `08-apagar-grupo` — confirmação de apagar.
9. `09-gaveta-modo-grupo` — gaveta no modo do grupo (Guardar no grupo / Ver sem guardar).
10. `10-faixa-voce-mudou` — faixa "Você mudou quem aparece neste grupo."
11. `11-trocar-nome` — diálogo de trocar o nome.
12. `12-nome-vazio-erro` — diálogo de guardar com o nome vazio e o erro.
13. `13-valor-sim-nao-e-pais` — Bloqueada (Sim | Não, sem "Como") e País é Brasil.

## Técnico (para depois do OK do mockup)

- `filtros.js`: `condicoes: []` e `juntar: 'todas' | 'qualquer'` no estado dos filtros.
- Servidor: `relacionamentos/pessoas` (e as contagens) aceitam `condicoes` no formato do payload de
  `contacts/filter`; a regra reaproveita a montagem de condição do `FilterService` sobre o escopo da
  consulta, com a mesma validação (422 em chave, operador ou valor inválido).
- Grupos: `custom_filters` com `filter_type: contact`; `query` = `{ payload: [...], relacionamentos:
  { visao, grupo, busca, filtros } }` (o `payload` continua legível pela tela antiga até a fatia 8).
- Demonstração (`?demo=`): condições avaliadas no navegador e grupos guardados em memória.
