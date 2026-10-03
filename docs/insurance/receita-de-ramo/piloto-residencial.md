# Piloto de residencial: registro de campo

O que a aplicação da [RECEITA](RECEITA.md) a residencial mostrou, fase por fase. Cada rodada traz o que se
esperava e o que aconteceu. Nomes e CPFs dos cenários são fictícios, gerados com o algoritmo de dígito
verificador; as cotações rodaram na conta de **teste** do portal (5 seguradoras), nunca na de uma corretora.

## Fase 1, rodada 1 — 21/09/2026

Pelo caminho do produto: `AggerAdapter.startQuote` na versão da `main` do adapter (`3cbd864`), com a entrada
montada como `Insurance::QuoteInput#de_ramo` monta: `segurado` com CPF, nome, CEP e número, e `configuracoes` com
os quinze campos de origem `cliente` do schema de residencial.

### Conferência gratuita (`quote/validate`), antes de qualquer cotação

- **Complemento vazio é recusado como dado faltando.** O schema marca `imovelComplemento` como obrigatório, e casa
  não tem complemento. Em produção, o agente pergunta, o cliente diz que não tem, o vazio é recusado, e o agente
  pergunta de novo. Para seguir a rodada os cenários usaram "Casa", que o produto não mandaria.
- **CPF com dígito verificador errado passa pela conferência** e só é recusado no portal (cenário S7).
- **Os quatro códigos de residencial não têm lista de valores** (`imovelUso`, `imovelTipoResidencia`,
  `imovelConstrucao`, `imovelObjetoSegurado`). Nem o conhecimento colhido do portal os descreve; o adapter manda 1.

### Cotações reais

| Cenário | Esperado | Aconteceu | Com preço |
|---|---|---|---|
| S1: simples, como o produto manda hoje | recusa por endereço | as 5 recusaram: "A cidade deve ser informada corretamente". O portal gravou o endereço vazio | 0 de 5 |
| S2: simples, com o endereço da consulta de CEP do portal | cota | cotou | 2 de 5 (R$ 242,28 e R$ 312,73, total) |
| S3: complexo, inquilino, sete dispositivos de segurança, apartamento com complemento | cota | cotou; os campos de sim e não foram gravados como enviados | 2 de 5 (R$ 244,17 e R$ 410,91) |
| S4: cidade de CEP único, sem rua | recusa por logradouro | as 5 recusaram: "Logradouro deve ser informado corretamente" | 0 de 5 |
| S5: CEP inexistente | falha tratável | as 5 recusaram: "A cidade deve ser informada corretamente" (a consulta de CEP não roda nesse caminho, então o erro 502 do portal nem aparece) | 0 de 5 |
| S7: CPF inválido | recusa | o portal devolveu HTTP 400 "CPF/CNPJ inválido" no envio, e o adapter o tratou como **erro de protocolo**, que o chat2you trata como falha técnica | pedido recusado |
| S8: patrimônio histórico | recusa de risco | a Ezze cotou com o **mesmo preço** do S2; as outras, instabilidade ou verba | 1 de 5 |

### O que a rodada prova

1. **Pelo caminho do produto, residencial não cota hoje.** S1 é exatamente o que a Lia mandaria, e as cinco
   seguradoras recusaram por endereço. A tabela de 07/09 provava o corpo, não o produto.
2. **Com o endereço da consulta de CEP do portal, cota.** S2 é a mesma entrada com os quatro campos de endereço, e
   o portal os gravou. O logradouro no formato do portal ("Avenida Paulista - de 612 A 1510 - Lado Par") foi aceito.
3. **Cidade de CEP único exige perguntar a rua** (S4).
4. **Os campos de sim e não atravessam**: inquilino, alarme monitorado e patrimônio histórico foram gravados como
   enviados (leitura de volta).

### O que ela mostrou e ainda não explica

- **Mapfre recusou os três cenários com endereço** com "O tipo de verba selecionado não está disponível para este
  cenário nesta seguradora". É o padrão de cobertura que o adapter manda, não o cliente. Uma seguradora perdida em
  toda cotação.
- **"Instabilidade" da seguradora e "a cidade deve ser informada" chegam como `declined`**, o mesmo status de uma
  recusa de risco. São três coisas diferentes: seguradora fora agora, dado nosso errado, e risco recusado. O
  cliente não pode ouvir as três do mesmo jeito.
- **A linha de endereço impressa repete o número**: "Avenida Anchieta, 200, 200 Apto 42". A consulta de CEP do
  portal às vezes devolve o número dentro do logradouro. Aparece na proposta.
- **Três cotações com preço levaram cerca de 7 minutos** no laço desta rodada. O laço é do script, não o do
  produto; o fechamento pelas duas leituras iguais só foi medido em auto. A medir na fase 6.

### Consequência para a fase 2 (no adapter, antes do chat2you)

1. Derivar o endereço do imóvel pela consulta de CEP do portal no caminho dos outros ramos, como auto faz.
2. CEP sem rua: pedir a rua ao cliente pela conferência gratuita, não deixar o portal recusar.
3. CEP inexistente: tratar o erro do portal como "confirme o CEP", não como falha técnica.
4. Complemento vazio aceito.
5. CPF e CNPJ com dígito verificador conferidos na conferência gratuita.
6. Descobrir e publicar os valores dos quatro códigos de residencial, com descrição que ensina a extrair da
   conversa.
7. Investigar a recusa da Mapfre pelo tipo de verba.
8. Separar instabilidade da seguradora, dado nosso errado e recusa de risco.

## Fase 1, rodada 2 — 22/09/2026

Pelo caminho do produto, com os itens 1 a 5 acima feitos (autonom-ia2/autonomia-adapters#77, com a par
autonom-ia2/chat#589): o adapter completa o endereço do imóvel pela consulta de CEP do portal, e o que é pergunta ao
cliente volta em `details.perguntas` no 422 do `quote/start`. Entrada como o chat2you monta: CPF, nome, CEP e número.
Dados fictícios novos, conta de **teste** do portal, que agora oferece 11 seguradoras em residencial.

| Cenário | Esperado | Aconteceu | Com preço |
|---|---|---|---|
| R1: simples, como o produto manda | cota, com o endereço da consulta | cotou; o portal gravou rua, bairro, cidade e UF da consulta de CEP | 5 de 11 (R$ 166,03 a R$ 407,22, total) |
| R2: cidade de CEP único | pergunta a rua | 422 com `perguntas` para rua e bairro em 13 s; nenhum cálculo no portal | pergunta |
| R3: CEP inexistente | confirme o CEP | 422 com `perguntas` para o CEP em 21 s (dois 502 na consulta) | pergunta |
| R4: inquilino, apartamento, alarme monitorado | cota, e os campos atravessam | cotou; inquilino, alarme, complemento gravados; o número não saiu repetido na linha | 5 de 11 (R$ 170,69 a R$ 394,78) |

**A fase 1 passou**: cotação pelo caminho do produto, lida de volta, com preço.

### O que as recusas de R1 e R4 mostram (fase 2 e cadastro)

- **Mapfre**, de novo, "O tipo de verba selecionado não está disponível": é o pacote que o adapter manda (item 7).
- **Unimed**: "Desmoronamento, para contratação desta cobertura é necessário enviar para Análise Técnica". Outra
  cobertura do pacote padrão que custa uma seguradora.
- **Porto Seguro**: "Endereço não encontrado para o CEP informado", nos dois CEPs, mesmo com o endereço gravado. A
  Porto parece consultar outra base; a investigar.
- **Liberty**: "Login ou senha incorreta" na conta de teste. Cadastro, não código.
- **Bradesco**: nome não corresponde ao CPF, e CPF não cadastrado. Esperado com dado fictício; em produção é dado real.
- **Mitsui**: instabilidade. Entra no item 8 (separar instabilidade de recusa).
- Cada cotação levou cerca de 7 minutos no laço do script; o fechamento do produto ainda é o de auto (fase 6).

## Fase 2, pacote de coberturas — 22/09/2026

Objetivo do Rodrigo: as coberturas-padrão precisam funcionar em todas as seguradoras. O mecanismo de ajuste por
seguradora do portal (`valoresAjusteSeguradora`) só serve para profissão e atividade, então o caminho é um pacote
único por objeto segurado. Conta de teste, 11 seguradoras, mesmo imóvel em BH; a rodada final com CPF real (não
guardado).

| Objeto | Pacote | Com preço | Quem ainda recusa, e por quê |
|---|---|---|---|
| 3, prédio + conteúdo (padrão) | atual | 7 de 11 | Unimed: desmoronamento exige análise técnica |
| 3, prédio + conteúdo (padrão) | **sem desmoronamento** | **10 de 11** | Mitsui: "instabilidade" nas 12 rodadas do dia (adapters#81) |
| 1, só prédio (seguro para o aluguel) | sem roubo, desmoronamento e equipamentos | 7 de 11 | Mapfre não oferece só prédio (verba); Allianz erro interno uma vez |
| 2, só conteúdo (pedido explícito) | sem vendaval, impacto de veículo, vazamento, aluguel e desmoronamento | 6 de 11 | Mapfre e Tokio não oferecem só conteúdo (verba) |

Também: a Porto recusava só prédio por "subtração de bens" (roubo no pacote) e passou a cotar sem ele; a Liberty
cotou com CPF real (o "senha incorreta" vinha do CPF fictício); a Bradesco só cota com o nome exatamente como na
Receita (adapters#82) e devolveu o prêmio com forma de pagamento desconhecida (adapters#83).

**Decisões do Rodrigo:** padrão 3 para todos; 1 quando o seguro é para o aluguel; 2 só quando pedido. O valor a
segurar vira pergunta obrigatória e simples, conduzida pelo especialista; o custo de reconstruir (sem o terreno) só
é explicado se o cliente pedir ajuda. Construção pela régua em `autonomia-adapters/docs/agger/tipos-de-construcao.md`.

## Fases 3 a 6 e o fecho — 22 a 24/09/2026

- **Fase 3, travas:** tetos pelo incêndio numa tabela só (`TETO_PELO_INCENDIO['2']`, adapters#86), com a bisseção que
  achou o limite da Tokio (Registros e Documentos, 5%); valor abaixo do mínimo cota com o mínimo e a Lia explica.
- **Fases 4 e 5:** especialista `cotacao_residencial` com manual próprio (chat#604), inserido nos agentes existentes por
  migration, disponível pela conexão e liberado só na conta 16. Em produção desde 22/09, ~20h.
- **Fase 6, prova real:** 22/09 (9 de 10, PDF, perguntas sobre o que cotou respondidas certo) e a rodada de 24/09, em
  paralelo com auto em dois números: apartamento 9 de 10 em 238 s, casa 9 de 10 em 223 s, os dois com PDF.
- **O que a rodada de 24/09 ainda achou:** a frase de prazo e recusa ao cliente (D13) e o CPF perguntado com a apólice
  na mão (C12), corrigidos na chat#639; o histórico da véspera escolhendo o CPF (C13).

**Veredito:** o piloto passou pelas oito fases. A receita sai de rascunho (versão 2, 24/09), e o próximo ramo,
empresarial, nasce dela ([piloto-empresarial.md](piloto-empresarial.md)).

## Checklist

Os 26 itens da [receita v3](RECEITA.md#checklist-do-ramo), preenchidos em 25/09/2026 contra a `main` dos dois
repositórios, os PRs mergeados e este piloto. Item sem prova é `aberto`.

| # | Item | Estado | Evidência |
|---|---|---|---|
| R1 | Decisão do Rodrigo, orçamento de cotações do ramo aprovado e descoberta de 04/09 lida | aberto | O orçamento por ramo não existia antes da v3 (25/09) e nenhum teto foi aprovado; a decisão de 22/09 e a leitura da descoberta não estão registradas neste piloto. Falta registrar a decisão e aprovar o teto. |
| R2 | Jornada de auto preenchida, todas as linhas, sem "depois" | aberto | Este piloto não tem a tabela da jornada de auto para residencial; o levantamento de 22/09 ficou fora do repositório. Falta a tabela, todas as linhas, mostrada ao Rodrigo. |
| R3 | Mínimo medido um campo por vez, em três faixas e dois perfis: sem o campo, menos de 70% das prontas cotam, ou recusa nomeada, ou validador; tabela campo, classe e prova | aberto | Critério novo de 26/09: falta a medição campo a campo e a tabela com o id de cada execução. Antes: adapters#92 (CPF, CEP com número, tipo e valor; nome pelo documento), `test/unit/residencial-dados-minimos.test.ts`; tabelas das rodadas 1 e 2 e da Fase 2 neste piloto (padrão em 10 de 11). |
| R4 | Completude: formulário do portal em `formularios-<ramo>.json`, toda variável com classe (mínimo, condicional, buscado, sob pedido, fora) e guarda formulário contra schema nos dois sentidos | aberto | Falta o arquivo do formulário do ramo e a guarda de completude. Antes: `test/unit/ramos-prontos.test.ts` (adapters#79) confere descrição e valores só dos campos declarados, não que o schema cobre todos os parâmetros do portal. Falta cruzar o schema com o catálogo da descoberta. |
| R5 | Limites pagos por seguradora, por bisseção, priorizados, com data | aberto | Parcial: só a bisseção da Tokio em Registros e Documentos (adapters#86) e os tetos de adapters#84. Falta a tabela por seguradora e cobertura, priorizada e datada. |
| R6 | Cota pelo caminho do produto, lida de volta, em três faixas de valor, com dado real | aberto | Caminho do produto lido de volta na rodada 2 (adapters#77, conta de teste, dado fictício); não há três faixas registradas com ids de execução nem leitura de volta com dado real. |
| R7 | Formulário gerado; todo campo atravessa; descrições sem crase nem travessão | ok | chat#592; `spec/services/autonomia/insurance/quote_input_travessia_do_ramo_spec.rb`; `test/unit/ramos-prontos.test.ts` ("sem crase e sem travessão"). |
| R8 | Ferramenta nova testada com a resposta do `Connector::Http` e o tempo medido | aberto | `http_cep_lookup_spec.rb` (chat#597) testa pelo Http, mas a consulta de CEP usa o teto de 10 s da conferência, sem a latência medida escrita junto; a revisão da chat#597 apontou o teto apertado. |
| R9 | Travas com saída "não se aplica"; PF e PJ separados; abaixo do mínimo cota com o mínimo | ok | adapters#86; `test/unit/travas-residencial.test.ts` (saída de quem não quer a cobertura, "pessoa física e jurídica conferidas separadamente", "abaixo do mínimo manda cotar com o mínimo"), com mutação no PR. |
| R10 | Pacote, tetos pela base e ruído do ramo | ok | `PACOTE_POR_OBJETO` (adapters#80), `TETO_PELO_INCENDIO['2']` (adapters#84, #86), medição da Fase 2 neste piloto; ruído: nenhum medido no ramo 2 (`test/unit/paridade-dos-ramos.test.ts`). |
| R11 | Nenhum fato do cliente fixo no código; o pedido vence o padrão | aberto | O pedido vence o padrão (`residencial-dados-minimos.test.ts`, `numero-do-imovel.test.ts`), mas `CAMPOS_DA_IMPRESSAO['2']` fixa atividade profissional no local = 0, fato do cliente. Falta tratá-lo como campo do cliente ou justificar como escolha. |
| R12 | Comparativo **e** proposta exclusiva de uma seguradora, abertos e lidos | aberto | Comparativo provado (adapters#90; prova real de 22/09). A proposta de uma seguradora em residencial não foi provada em conversa real. |
| R13 | Coberturas nos três níveis, provadas com apólice real | aberto | Não houve apólice real de residencial com coberturas; a regra existe (adapters#86, chat#708), sem prova. |
| R14 | Renovação, se o ramo tem, provada com e sem apólice; ou o motivo de não ter | aberto | Sem apólice provada (execução 100, adapters#105, chat#711); com apólice PENDENTE: não havia apólice de renovação (chat#641). |
| R15 | Manual no padrão do especialista | aberto | Guarda em PR (`padrao_do_especialista_spec.rb`, branch `feat/guardas-da-receita`, ainda não aberto). |
| R16 | Manual sem contradição (arquivo, comum, descrições e conferências), sem posição de anexo, promessas ligadas, md5 | aberto | Promessas e md5 em `builder_instrucao_do_especialista_residencial_spec.rb`; o texto sem posição do anexo está na chat#716, sem merge, e a procura de contradição nas descrições do adapter não está registrada. |
| R17 | Seis rodadas usadas na conferência; recote pago uma vez por valor (quando existir) | aberto | Guarda em PR (`feat/guardas-da-receita`); o recote pago uma vez (opção a) não está implementado. |
| R18 | Nada de regex para entender o cliente | aberto | Guarda em PR (`sem_regex_spec.rb`, `feat/guardas-da-receita`); no adapter já existe `test/unit/sem-regex-no-codigo.test.ts`. |
| R19 | Nenhum texto fixo ao cliente; conversa real lida por gente | aberto | Guarda em PR (`sem_texto_fixo_ao_cliente_spec.rb`, `feat/guardas-da-receita`). |
| R20 | Toda falha do ramo vira nota privada à equipe | aberto | Guarda em PR (`falha_vira_nota_privada_spec.rb`, `feat/guardas-da-receita`). |
| R21 | Peças em paridade no adapter e no chat, exceções com motivo | aberto | Adapter: `test/unit/paridade-dos-ramos.test.ts` (adapters#104). Chat: guarda em PR (`paridade_das_pecas_spec.rb`, `feat/guardas-da-receita`); itens D, G e H da auditoria em chat#716 e adapters#106, sem merge. |
| R22 | Especialista nos agentes existentes, só onde a corretora cota | ok | chat#604; `db/migrate/20260922200000_add_residencial_specialist_to_quote_agents.rb`; `builder_especialista_residencial_disponivel_spec.rb`; `builder_ferramentas_por_ramo_spec.rb`. |
| R23 | Roteiro real: sozinho; depois de outro ramo; dois bens; com auto e residencial; dado mudado entre rodadas; o cliente pedindo três parâmetros sob pedido sem ser perguntado, conferidos na leitura de volta | aberto | Falta a rodada dos três parâmetros sob pedido. Antes: Provados: sozinho e depois do empresarial (conversa 7057), junto do empresarial na mesma mensagem (conversa 87, execuções 101 e 102). Faltam dois bens do ramo de uma vez e auto na mesma mensagem. |
| R24 | Bateria de roteamento, também contra os ramos no ar, com veredito do banco | aberto | Nunca rodada, nem os ambíguos nem a conta sem o ramo. |
| R25 | Recusas conhecidas registradas, com o dono de cada uma | aberto | As recusas estão espalhadas nas rodadas (Mapfre e Tokio nas variantes, Mitsui, Porto, Bradesco), sem a lista com o dono de cada uma. |
| R26 | Revisão adversarial sem `test/contract`, suíte local lida, mutação; ordem do deploy e vez combinada | aberto | Revisão Opus, suíte (2251 exemplos, 0 falhas) e mutação na chat#604; mutação em adapters#86 e #92. Falta a ordem do deploy e a vez combinada escritas no PR, e o registro de que o revisor não rodou `test/contract`. |
