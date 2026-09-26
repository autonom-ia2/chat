# Piloto — empresarial (ramo 18)

Terceiro ramo do Agente de Cotação, decidido pelo CEO em 24/09/2026. É o primeiro a nascer da
[receita v2](RECEITA.md), e o que ele revelar volta para a receita no mesmo PR que o fechar.

## Fase 0 — O ramo entra agora?

| Critério | Estado |
|---|---|
| Decisão do Rodrigo | **sim**, 24/09/2026 ("minha sugestão era empresarial") |
| Cota pelo adapter hoje, numa cotação nova | **a medir** (a tabela de 07/09 deu R$ 424,92 com 10 seguradoras, na conta de teste) |
| Corretora real com o ramo e seguradoras prontas | **sim**: conta 16, conexão 14, 8 de 10 prontas (Allianz, Hdi, Liberty, Mapfre, Mitsui, Porto, Tokio, Zurich; Bradesco e Sancor em `auth_required`), lido em 24/09 |

Cotações de medição autorizadas pelo Rodrigo em 24/09, na conta 16, em lotes que não travam a conta (Fase 0:
abrir uma por vez).

## A jornada de auto, para empresarial

Preenchida antes do código; célula "a medir" é o que a Fase 1 responde.

| Etapa | Empresarial |
|---|---|
| Reconhecer o ramo | a Lia chama o especialista de empresarial ("seguro da minha loja/empresa/escritório") |
| Coleta mínima | **a medir**: CNPJ, CEP e número do imóvel, atividade da empresa, valor a segurar; faturamento e área só se o portal exigir |
| O que se busca sozinho | razão social pelo CNPJ; endereço pelo CEP; **a medir**: se a atividade (CNAE) sai do CNPJ |
| Documento do cliente | apólice anterior dá imóvel e coberturas; o segurado é quem o cliente indicar |
| Conferência grátis | `quote/validate` com as travas do ramo |
| Envio | uma cotação por imóvel, em paralelo com outros ramos |
| Preço | comparativo em PDF (`printType` 2); **a provar** que sai |
| Fecho | igual a auto e residencial |
| Ninguém cotou | igual (`sem_aceitacao`, nota interna) |
| Ver resultado | resumo da entrada de empresarial (**a fazer**) |
| Proposta de uma seguradora | **a provar** |
| Lapidação | igual |
| Pedido repetido | igual |
| Passagem à equipe | igual |

## Perguntas que a Fase 1 responde

1. Quais campos o portal exige no ramo 18, e quais têm padrão seguro.
2. Pessoa jurídica: o segurado é o CNPJ; o que o portal pede do responsável.
3. A atividade da empresa: lista do portal, se muda por seguradora (como a profissão em vida), e se dá para
   deduzir do CNPJ.
4. O pacote de coberturas que cota na maioria das oito seguradoras, e os tetos de cada uma, por recusa nomeada.
5. Se o comparativo em PDF e a proposta de uma seguradora saem para o ramo.

## Estado em 25/09/2026: em produção na conta 16

**Provado em conversa real** (conversa 7057, conta 16):

| Prova | Resultado |
|---|---|
| Coleta mínima | CNPJ, CEP com número, atividade e valor; a Lia pergunta só o que falta e consulta o CEP |
| Atividade por seguradora | busca de 1 a 3 termos; escolha por seguradora, com térreo ou andar; 10 seguradoras com a atividade certa |
| Localização | "fica no 5º andar" vira localização 2 e pavimento 2 no portal; o padrão é térreo |
| Preço | 6 de 9 cotadas: Mapfre, Zurich, Allianz, Porto, Hdi, Liberty |
| Comparativo em PDF | sai em cerca de 2,5 min |
| Proposta de uma seguradora | Porto em PDF, 22 s depois do pedido |
| Nota da equipe | motivo de cada seguradora sem proposta; a fala ao cliente não cita recusa |
| Lapidação | "refaça com 350 mil e 5º andar" recota com os dois |

**PRs:**
- chat: #654, #665, #692, #702;
- adapters: #98, #99, #100, #101, #102, #103.

**Fica de fora, fora do nosso código:**
- **Bradesco:** "Dias de Paralisação" com despesas fixas; "sem aceitação" nas 12 variações medidas. Fica como está, por decisão do Rodrigo em 25/09.
- **Tokio:** a corretora precisa da adesão ao multicálculo empresarial no portal da Tokio.
- **Mitsui:** credencial ou "código 23", intermitente.

**Ainda não provado em conversa real:** empresarial combinado com auto ou residencial na mesma mensagem. A suíte cobre o paralelo por item, mas a prova real não foi feita.

**O que o teste real ensinou:** os modos F9 e F10 em [modos-de-falha](modos-de-falha.md).

## Atualização de 25/09/2026, à tarde

- **Provado em conversa real (conversa 87, conta 16):** empresarial e residencial pedidos na mesma mensagem e
  cotados em paralelo, cada um com o seu comparativo em PDF e a sua nota interna (execuções 101 e 102).
- **Renovação em residencial e empresarial no ar** (adapters#105, chat#711): sem apólice, a cotação sai como
  seguro novo com aviso uma vez (provado, execução 100). A prova **com** apólice está pendente: não havia apólice
  de renovação disponível (registrado na chat#641).
- **Pedido repetido em 24 h** responde do histórico sem reenviar o PDF: o Rodrigo decidiu manter assim.
- **Em PR para o próximo grande deploy:** "no PDF acima" (o PDF chega depois no WhatsApp), o travessão em
  `recusas.rb` e os itens D, G e H da auditoria de paridade com auto.

## Checklist

Os 26 itens da [receita v3](RECEITA.md#checklist-do-ramo), preenchidos em 25/09/2026 contra a `main` dos dois
repositórios, os PRs mergeados e este piloto. Item sem prova é `aberto`.

| # | Item | Estado | Evidência |
|---|---|---|---|
| R1 | Decisão do Rodrigo, orçamento de cotações do ramo aprovado e descoberta de 04/09 lida | aberto | Decisão registrada na Fase 0 (24/09), mas o orçamento por ramo não existia antes da v3 e nenhum teto foi aprovado; a descoberta de 04/09 só foi lida depois de treze cotações (modo F8). Falta aprovar o teto. |
| R2 | Jornada de auto preenchida, todas as linhas, sem "depois" | aberto | A tabela da Fase 0 ainda tem células "a medir", "a provar" e "a fazer", e não tem as linhas de renovação, coberturas, quem é o segurado, vários bens, mínimos e recusa conhecida, que entraram depois do ar. |
| R3 | Mínimo medido um campo por vez, em três faixas e dois perfis: sem o campo, menos de 70% das prontas cotam, ou recusa nomeada, ou validador; tabela campo, classe e prova | aberto | Critério novo de 26/09: falta a medição campo a campo e a tabela com o id de cada execução. Antes: Coleta mínima (CNPJ, CEP com número, atividade e valor) provada na conversa 7057, com preço em 6 de 9 cotadas; adapters#98, `test/unit/atividade-empresarial.test.ts`. |
| R4 | Completude: formulário do portal em `formularios-<ramo>.json`, toda variável com classe (mínimo, condicional, buscado, sob pedido, fora) e guarda formulário contra schema nos dois sentidos | aberto | Falta o arquivo do formulário do ramo e a guarda de completude. Antes: `test/unit/ramos-prontos.test.ts` (adapters#98) confere só os campos declarados; campos que a tela manda e o corpo não (modo F10, adapters#101) mostram que o catálogo não estava completo. Falta cruzar o schema com a descoberta. |
| R5 | Limites pagos por seguradora, por bisseção, priorizados, com data | aberto | Parcial: RC Operações até 50% e despesas fixas (adapters#100, #104), sem tabela por seguradora e cobertura, priorizada e datada; Bradesco, Tokio e Mitsui sem limite medido. |
| R6 | Cota pelo caminho do produto, lida de volta, em três faixas de valor, com dado real | aberto | Cotou pelo produto na conversa 7057 (250 mil e depois 350 mil; localização lida no portal), mas as três faixas de valor não estão registradas com ids de execução. |
| R7 | Formulário gerado; todo campo atravessa; descrições sem crase nem travessão | aberto | Formulário gerado do schema e descrições sem crase nem travessão (`test/unit/ramos-prontos.test.ts`); a travessia campo a campo (`quote_input_travessia_do_ramo_spec.rb`) cobre só residencial, e `insurance_quote_formulario_empresarial_spec.rb` só a atividade. Falta a travessia do 18. |
| R8 | Ferramenta nova testada com a resposta do `Connector::Http` e o tempo medido | ok | chat#665; `spec/services/autonomia/insurance/connector/http_atividade_lookup_spec.rb` (snake_case do conector); `BUSCA_DE_ATIVIDADE_TIMEOUT = 30` com a medição de 8 a 10 s escrita em `connector/http.rb`. |
| R9 | Travas com saída "não se aplica"; PF e PJ separados; abaixo do mínimo cota com o mínimo | aberto | Mínimo de 20 mil (`test/unit/renovacao-dos-ramos.test.ts`, adapters#105) e travas das coberturas (`test/unit/coberturas-empresarial.test.ts`); a atividade na conferência grátis está em adapters#106, sem merge, e não há teste de PF e PJ separados no ramo 18. |
| R10 | Pacote, tetos pela base e ruído do ramo | ok | Pacote e `RUIDO_POR_RAMO` (adapters#98, #101), `TETO_PELO_INCENDIO['18']` (adapters#100), exceções com motivo em `test/unit/paridade-dos-ramos.test.ts` (adapters#104). |
| R11 | Nenhum fato do cliente fixo no código; o pedido vence o padrão | aberto | Localização do cliente e pedido que vence o pacote provados (adapters#103, #104; `atividade-empresarial.test.ts`, `coberturas-empresarial.test.ts`), mas `CAMPOS_DA_IMPRESSAO['18']` fixa imóvel em construção ou reforma = não, fato do cliente. |
| R12 | Comparativo **e** proposta exclusiva de uma seguradora, abertos e lidos | ok | Conversa 7057: comparativo em PDF e proposta da Porto em PDF; adapters#101, chat#692. |
| R13 | Coberturas nos três níveis, provadas com apólice real | aberto | Coberturas do cliente no ar (adapters#104, chat#708), sem prova com apólice real de empresarial. |
| R14 | Renovação, se o ramo tem, provada com e sem apólice; ou o motivo de não ter | aberto | Sem apólice provada (execução 100, adapters#105, chat#711); com apólice PENDENTE: não havia apólice de renovação (chat#641). |
| R15 | Manual no padrão do especialista | aberto | Guarda em PR (`padrao_do_especialista_spec.rb`, branch `feat/guardas-da-receita`, ainda não aberto). |
| R16 | Manual sem contradição (arquivo, comum, descrições e conferências), sem posição de anexo, promessas ligadas, md5 | aberto | Promessas e md5 em `builder_instrucao_do_especialista_empresarial_spec.rb`; o texto sem posição do anexo ("no PDF acima") está na chat#716, sem merge. |
| R17 | Seis rodadas usadas na conferência; recote pago uma vez por valor (quando existir) | aberto | Guarda em PR (`feat/guardas-da-receita`); o recote pago uma vez (opção a) não está implementado. |
| R18 | Nada de regex para entender o cliente | aberto | Guarda em PR (`sem_regex_spec.rb`, `feat/guardas-da-receita`); no adapter já existe `test/unit/sem-regex-no-codigo.test.ts`. |
| R19 | Nenhum texto fixo ao cliente; conversa real lida por gente | aberto | Guarda em PR (`sem_texto_fixo_ao_cliente_spec.rb`, `feat/guardas-da-receita`). |
| R20 | Toda falha do ramo vira nota privada à equipe | aberto | Guarda em PR (`falha_vira_nota_privada_spec.rb`, `feat/guardas-da-receita`). |
| R21 | Peças em paridade no adapter e no chat, exceções com motivo | aberto | Adapter: `test/unit/paridade-dos-ramos.test.ts` (adapters#104). Chat: guarda em PR (`paridade_das_pecas_spec.rb`, `feat/guardas-da-receita`); o fecho sem novidade e os itens D, G e H em chat#716 e adapters#106, sem merge. |
| R22 | Especialista nos agentes existentes, só onde a corretora cota | ok | chat#654; `db/migrate/20260924150000_add_empresarial_specialist_to_quote_agents.rb`; `add_empresarial_specialist_to_quote_agents_spec.rb`; `builder_ferramentas_por_ramo_spec.rb` (só onde a corretora cota e liberou). |
| R23 | Roteiro real: sozinho; depois de outro ramo; dois bens; com auto e residencial; dado mudado entre rodadas; o cliente pedindo três parâmetros sob pedido sem ser perguntado, conferidos na leitura de volta | aberto | Falta a rodada dos três parâmetros sob pedido. Antes: Provados: sozinho (conversa 7057), lapidação com dado mudado (7057), junto do residencial na mesma mensagem (conversa 87, execuções 101 e 102). Faltam dois bens do ramo de uma vez e auto na mesma mensagem. |
| R24 | Bateria de roteamento, também contra os ramos no ar, com veredito do banco | aberto | Nunca rodada, nem os ambíguos ("seguro da minha loja", "o carro da empresa") nem a conta sem o ramo. |
| R25 | Recusas conhecidas registradas, com o dono de cada uma | aberto | Lista neste piloto: Bradesco (decisão do Rodrigo, 25/09) e Tokio (adesão da corretora); a Mitsui ("credencial ou código 23") está sem dono definido. |
| R26 | Revisão adversarial sem `test/contract`, suíte local lida, mutação; ordem do deploy e vez combinada | aberto | Revisão Opus aprovada na 2ª rodada, 4 mutações e plano de deploy com o chat antes do adapter na chat#654. Falta o registro de que o revisor não rodou `test/contract` e da vez combinada, e a revisão final de chat#716 e adapters#106. |
