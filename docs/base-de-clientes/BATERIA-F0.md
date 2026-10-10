# Base de clientes — bateria de planilhas (F0)

Issue #1246, épico #1240. Rodadas de 10/10/2026.

## O que é

A F0 previa recolher 5 planilhas reais de clientes. Decisão do Rodrigo (10/10): não esperar por
elas e estressar o motor que já está em produção, o da importação de contatos (#1006:
`CampaignImports::Parser` + `SpreadsheetReader` + Jev).

Para isso foram montadas **63 planilhas fictícias**, cada uma com gabarito. O gabarito diz:
- qual é a linha do cabeçalho e qual é a aba;
- qual coluna é o celular, o e-mail, o nome e a empresa (ou "não tem");
- se o certo é o motor resolver sozinho ou parar e perguntar;
- linha a linha, se uma pessoa alcançaria quem está ali.

| Conjunto | Planilhas | Para quê |
|---|---|---|
| Simples (`casos_simples.rb`) | 9 | CSV com `,` `;` tab e `\|`, Windows-1252, XLSX, inglês, só WhatsApp, só e-mail |
| Dia a dia (`casos_dia_a_dia.rb`) | 20 | título acima do cabeçalho, fixo + celular, dois e-mails, export do Kommo, RD, Pipedrive e HubSpot, várias abas, rodapé com total, repetidos |
| Armadilhas (`casos_armadilhas.rb`) | 18 | CPF que parece celular, DDD em coluna separada, sem cabeçalho, cabeçalho genérico, ERP com 30 colunas, injeção no cabeçalho, dois valores na célula, Excel com celular salvo como número, base antiga sem o 9, 3.000 linhas, título com telefone, **celulares dos EUA no meio** |
| Controle (`casos_controle.rb`) | 16 | escritos **depois** do ajuste e nunca usados para ajustar: Facebook Lead Ads (`p:+55…`), banco em snake_case, emoji no cabeçalho, escola, clínica, cabeçalhos repetidos |

Nenhum dado é de cliente. Nomes e empresas saem do Faker com semente fixa; telefones, CPFs e
e-mails são gerados. O Jev, como em produção, só vê os cabeçalhos e o formato mascarado dos
valores.

## Liberação: flag `customer_base`, piloto na conta 16

Tudo o que muda fica atrás da flag de conta `customer_base`, que vem **desligada** para todas as
contas (`config/features.yml`, fim da coluna `feature_flags_ext_1`). A decisão sai da conta
(`CampaignImports::ContactReading.for(account)`) e é passada de forma explícita ao leitor, ao
localizador do cabeçalho, ao resolvedor do Jev e ao validador. Não há estado global.

- **Desligada (`CLASSIC`):** a leitura de hoje, sem nenhuma diferença (prova abaixo).
- **Ligada (`CUSTOMER_BASE`):** a leitura nova. Piloto na conta 16 do Hub2You; quem liga é a
  Orquestração, depois do deploy, com o OK do Rodrigo. Registro em
  [liberacoes-por-conta.md](../liberacoes-por-conta.md).

### Prova: desligada = `main`, linha a linha

`script/evals/base_de_clientes/comparar_com_main.rb` roda a importação de contatos de verdade
(`ContactImports::Validator`, com banco de teste, anexo e linhas gravadas) sobre as 63 planilhas. Por
planilha, ele grava:
- o status e as contagens;
- as colunas escolhidas;
- o resumo da validação;
- cada linha: status, motivos, nome, máscaras, hash do telefone e do e-mail;
- o CSV normalizado e o CSV de erros.

Quando a importação para pedindo as colunas, ele aceita a sugestão, como faria uma pessoa, e
valida de novo. Assim as linhas também entram na comparação.

O Jev varia de uma chamada para outra, então as respostas dele são gravadas na rodada do `main` e
**reproduzidas** nas outras. Qualquer diferença só pode vir do código. Uma pergunta ao Jev que não
está na gravação para a rodada.

| Rodada | Linhas válidas | Inválidas | Planilhas que falham | Resultado |
|---|---|---|---|---|
| `main` (`c3d9eb7613`) | 5.429 | 95 | 1 (sem cabeçalho) | referência |
| Branch, flag **desligada** | 5.429 | 95 | 1 | **idêntica ao `main` byte a byte**; nenhuma pergunta nova ao Jev |
| Branch, flag **ligada** | 5.543 | 28 | 0 | 7 planilhas mudam (abaixo) |

Com a flag ligada, das 5.429 linhas que o `main` já aceitava, nenhuma trocou nem perdeu telefone ou
e-mail. 22 ganharam o dado que faltava: 15 o celular, 7 o e-mail.

| Planilha | `main` | Ligada | 9 acrescentado |
|---|---|---|---|
| c15 celular em todos os formatos | 44 | 60 | 12 |
| c33 sem cabeçalho | falha (`empty_file`) | 40 | 0 |
| c38 vários e-mails na célula | 25 | 40 | 0 |
| c39 dois telefones na célula | 33 | 40 | 0 |
| c42 base antiga sem o 9 | 23 | 40 | 23 |
| c45 sem cabeçalho, com pessoa sem contato | 28 | 34 | 0 |
| h10 só uma coluna de números | 27 | 40 | 9 |
| c47 celulares dos EUA no meio | 36 | 36 (os 4 dos EUA recusados nas duas) | 0 |

Para refazer, com o mesmo `JEV_GRAVACAO` nas três rodadas:
1. Rode no `main` uma vez para gravar as respostas.
2. Rode na branch com `JEV_SO_REPRODUZIR=1`, com e sem `CUSTOMER_BASE=1`.
3. Compare os arquivos com `cmp`.

## A bateria com o Jev

`script/evals/base_de_clientes/rodar.rb` lê cada planilha nas duas leituras (`MOTORES=classica,nova`)
e dá um veredicto a cada leitura, do pior para o melhor:
1. `critico`: importaria coluna errada sem perguntar;
2. `sugestao_errada_confiante`;
3. `sugestao_errada`: perguntou, mas sugeriu a coluna errada;
4. `parou_com_erro`;
5. `perguntou_a_toa`: perguntou sem haver dúvida honesta;
6. `perfeito`.

Ele também conta, linha a linha:
- **perdidas:** uma pessoa alcançaria quem está na linha, e o motor não;
- **inventadas:** o motor aceitou um número que não alcança a pessoa da linha, como um número dos
  EUA lido como +55.

Sob demanda, nunca no CI: chama o Jev pago e para antes do teto.

```sh
BASE_CLIENTES_EVAL=1 TYPESAFE_API_KEY=... REPETICOES=3 CONJUNTO=todos \
  bundle exec rails runner script/evals/base_de_clientes/rodar.rb
```

Variáveis:
- `CONJUNTO`: `principal`, `controle` ou `todos`;
- `CASOS=c01,h05`: roda só esses casos;
- `TETO_USD`: teto de gasto, padrão 2;
- `SEMENTE`: outros dados para os mesmos casos.

Ele grava em `tmp/evals/base_de_clientes/<data>/` o `RELATORIO.md`, o `resultados.json` (com a
resposta crua do Jev) e as planilhas.

### Resultado (63 planilhas, 3 leituras com o Jev em cada, nas duas leituras)

| | Clássica (sem a flag = `main`) | Nova (`customer_base`) |
|---|---|---|
| Erro silencioso (`critico`) | 0 | 0 |
| Leituras perfeitas | 166 de 189 (88%) | 180 de 189 (95%) |
| Parou com erro | 3 | 0 |
| Perguntou sem precisar | 14 | 5 |
| Sugestão errada (perguntando) | 6 | 4 |
| **Linhas alcançadas** | **5.442 de 5.556** | **5.556 de 5.556** |
| **Linhas inventadas** | 0 | **0** |

Gasto com o Jev em todas as rodadas do dia: cerca de US$ 0,25, para um teto de US$ 2. Uma leitura
custa por volta de US$ 0,0001.

A escolha de colunas já era segura antes: nenhuma leitura importaria coluna errada sem perguntar. O
que se perdia eram **linhas** e algumas perguntas desnecessárias.

## O que a leitura nova muda, e por quê

| Sintoma na bateria | Causa raiz | O que muda com `customer_base` |
|---|---|---|
| Base antiga: 23 de 40 celulares aceitos | só eram aceitos 11 dígitos com o 9 | o celular antigo de 8 dígitos ganha o 9 pelo `BrazilPhoneNormalizer`, que já existia (só faixas 6–9; fixo, de 2 a 5, nunca) |
| `011 98765-4321` recusado | o 0 de discagem virava 12 dígitos | tira os zeros à esquerda (`0xx`, `00 55`) |
| Célula com dois e-mails ou telefones recusada | o valor era lido inteiro | `CampaignImports::CellValues`: tenta a célula inteira, depois cada parte (`;` `,` `/` `\|` quebra de linha); fica a primeira válida, e cada e-mail da célula é mascarado |
| Planilha sem cabeçalho: `empty_file` | sem linha "limpa", não havia candidato | colunas sem nome (`header_row` 0), todas as linhas como dado, e a pessoa confirma as colunas |
| Sem cabeçalho, com pessoa sem contato: essa linha virava "cabeçalho" e as de cima sumiam | qualquer linha sem contato podia ser cabeçalho | linha depois da primeira linha de dado (contato + 2 ou mais células) nunca é cabeçalho; título de uma célula só, mesmo com telefone, não conta |
| "Telefone", "Telfone", "Coluna2" com celulares 100% válidos perguntavam (confiança 0,46 a 0,78) | a pergunta ao Jev não dizia que a contagem de celulares válidos prova o que a coluna é | o Jev recebe a **proporção** de celulares e e-mails válidos, e a instrução diz que proporção alta é celular mesmo com cabeçalho genérico. **Quem decide continua sendo o Jev** |

### Efeito colateral resolvido: número do exterior

Pôr o 9 num número de 10 dígitos poderia transformar um celular dos EUA (`917 555 1234`) em um
número brasileiro de outra pessoa. A leitura nova só aceita o número com três checagens, todas
baseadas em fato:
1. Com `+` na frente, o código tem de ser 55. `+1 917…` e `+91 7555-1234` são de outro país.
2. O 9 só entra quando o número está escrito do jeito brasileiro: o DDD, de 2 dígitos, separado
   do resto (`(11) 8765-4321`, `11 8765-4321`, `+55 11 8765-4321`, `011 8765-4321`) ou tudo junto
   (`1187654321`, o formato de exportação de sistema). Agrupamentos de outro país, como
   `917 555 1234`, `(917) 755-1234` e `917-755-1234`, são recusados.
3. O DDD tem de estar na lista da Anatel (67 DDDs), e não "quaisquer dois dígitos de 1 a 9".

O c47 mistura 30% de celulares dos EUA escritos nos jeitos de lá. Nenhum foi aceito (0 inventadas).
Sobra um caso que dígito nenhum resolve: um número dos EUA escrito tudo junto e sem o +1
(`9175551234`). Para auditar, a importação conta quantos celulares ganharam o 9
(`validation_summary.ninth_digit_added`). Mostrar esse número na tela fica para a F1, que terá
tela própria.

### O que foi tentado e desfeito

- **Aceitar "não tem empresa" com confiança de 0,5 ou mais.** O conjunto de controle mostrou que o
  cabeçalho "Account", uma empresa de verdade, passaria calado. Foi desfeito: perguntar a mais é
  melhor que errar calado.
- **Reescrever a pergunta da empresa.** Deixou o Jev menos seguro do "não tem". Foi desfeito.

## O que continua de fora

1. **Perguntas sobre empresa ausente:** de 4 a 7 em 189 leituras. É clique a mais, não erro.
2. **DDD numa coluna e número em outra:** o motor não junta colunas. Hoje ele pergunta. Entra na F1.
3. **A mesma pessoa em várias linhas** (duas compras): a segunda linha é recusada como repetida.
   Decisão de produto da F1.
4. **Célula com dois e-mails** guarda só o primeiro.
5. **Planilha sem cabeçalho cuja primeira linha é só um nome:** essa linha ainda é lida como
   cabeçalho. Já era assim.
6. **Duas tabelas empilhadas na mesma aba:** não é suportado.
7. **Sem a flag, a máscara da célula com dois e-mails** mostra o segundo endereço no CSV de erros
   da própria conta. Era assim no `main`, e continua igual para manter a leitura idêntica.
8. **Os dados são fictícios.** A bateria mede estrutura e cabeçalho, que é o que o Jev vê. Quando
   chegar uma planilha real, ela vira um caso a mais (só a estrutura, nunca os dados).
