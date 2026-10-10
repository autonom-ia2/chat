# Base de clientes — bateria de planilhas (F0)

Issue #1246, épico #1240. Rodada de 10/10/2026.

## O que é

A F0 previa recolher 5 planilhas reais de clientes. Decisão do Rodrigo (10/10): não esperar
por elas e estressar o motor que já está em produção, o da importação de contatos (#1006:
`CampaignImports::Parser` + `SpreadsheetReader` + Jev).

Para isso foram montadas **62 planilhas fictícias**, cada uma com gabarito. O gabarito diz:
- qual é a linha do cabeçalho e qual é a aba;
- qual coluna é o celular, o e-mail, o nome e a empresa (ou "não tem");
- se o certo é o motor resolver sozinho ou parar e perguntar;
- quantas linhas uma pessoa conseguiria alcançar.

| Conjunto | Planilhas | Para quê |
|---|---|---|
| Simples (`casos_simples.rb`) | 9 | CSV com `,` `;` tab e `\|`, Windows-1252, XLSX, inglês, só WhatsApp, só e-mail |
| Dia a dia (`casos_dia_a_dia.rb`) | 20 | título acima do cabeçalho, fixo + celular, dois e-mails, export do Kommo, RD, Pipedrive e HubSpot, várias abas, rodapé com total, repetidos |
| Armadilhas (`casos_armadilhas.rb`) | 17 | CPF que parece celular, DDD em coluna separada, sem cabeçalho, cabeçalho genérico, ERP com 30 colunas, injeção no cabeçalho, dois valores na célula, Excel com celular salvo como número, base antiga sem o 9, 3.000 linhas, título com telefone acima do cabeçalho |
| Controle (`casos_controle.rb`) | 16 | escritos **depois** do ajuste e nunca usados para ajustar: Facebook Lead Ads (`p:+55…`), banco em snake_case, emoji no cabeçalho, escola, clínica, cabeçalhos repetidos |

Nenhum dado é de cliente. Nomes e empresas saem do Faker com semente fixa; telefones, CPFs
e e-mails são gerados. O Jev, como em produção, só vê os cabeçalhos e o formato mascarado
dos valores.

## Como rodar

Sob demanda, nunca no CI: a bateria chama o Jev pago e para antes do teto.

```sh
BASE_CLIENTES_EVAL=1 TYPESAFE_API_KEY=... REPETICOES=3 CONJUNTO=todos \
  bundle exec rails runner script/evals/base_de_clientes/rodar.rb
```

- `CONJUNTO` pode ser `principal`, `controle` ou `todos`.
- `CASOS=c01,h05` roda só os casos listados.
- `TETO_USD` é o teto de gasto (padrão 2).
- `SEMENTE` gera outros dados para os mesmos casos.

A rodada grava em `tmp/evals/base_de_clientes/<data>/` três coisas: o `RELATORIO.md`, o
`resultados.json` (com a resposta crua do Jev, coluna e confiança) e as planilhas geradas.

Cada leitura recebe um veredicto, do pior para o melhor:
1. `critico`: importaria coluna errada sem perguntar;
2. `sugestao_errada_confiante`;
3. `sugestao_errada`: perguntou, mas sugeriu a coluna errada;
4. `parou_com_erro`;
5. `perguntou_a_toa`: perguntou sem haver dúvida honesta;
6. `perfeito`.

## Resultado

3 leituras com o Jev em cada planilha. O motor do `main` rodou nas 61 planilhas que existiam
antes da revisão; a rodada final inclui o c46, acrescentado por causa dela.

| | Motor do `main` (61 planilhas, 183 leituras) | Com as correções (62 planilhas, 186 leituras) |
|---|---|---|
| Erro silencioso (`critico`) | 0 | 0 |
| Leituras perfeitas | 158 (86%) | 177 (95%) |
| Parou com erro | 3 | 0 |
| Perguntou sem precisar | 15 | 7 |
| Sugestão errada (perguntando) | 7 | 2 |
| **Linhas alcançadas** | **5.367 de 5.480** | **5.520 de 5.520** |

O Jev varia um pouco entre rodadas (as perguntas desnecessárias oscilaram entre 4 e 7 nas
rodadas finais); o erro silencioso ficou em zero em todas.

Gasto do dia, somando todas as rodadas (mais de 1.300 leituras): **cerca de US$ 0,19**, para
um teto de US$ 2. Uma leitura custa por volta de US$ 0,0001.

A escolha de colunas do Jev já era segura antes desta entrega: nenhuma leitura importaria coluna
errada sem perguntar. O que se perdia eram **linhas** e algumas perguntas desnecessárias.

## O que estava errado e o que mudou

| Sintoma na bateria | Causa raiz | Correção |
|---|---|---|
| Base antiga: 23 de 40 celulares aceitos | o normalizador só aceitava 11 dígitos com o 9; celular antigo de 8 dígitos era recusado | `PhoneNormalizer` põe o 9 nos celulares antigos pelo `Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer`, que já existia (regra da Anatel: só faixas 6–9, nunca fixo) |
| `011 98765-4321` recusado | o 0 de discagem à frente virava 12 dígitos | tira os zeros à esquerda (`0xx`, `00 55`) antes de validar |
| Célula com dois e-mails ou dois telefones recusada | o valor era lido inteiro | `CampaignImports::CellValues`: tenta a célula inteira e, se falhar, cada parte separada por `;` `,` `/` `\|` ou quebra de linha; fica a primeira válida |
| Planilha sem cabeçalho: `empty_file` | sem linha "limpa" (sem celular nem e-mail), não havia candidato a cabeçalho | colunas sem nome (`header_row` 0), todas as linhas como dado, e a pessoa confirma as colunas |
| Sem cabeçalho e com uma pessoa sem contato: essa linha virava "cabeçalho" e as de cima sumiam | qualquer linha sem contato podia ser cabeçalho | linha que vem depois da primeira linha de dado (contato + pelo menos 2 células preenchidas) nunca é cabeçalho. O título de uma célula só, mesmo com telefone ("Corretora Alfa — (11) 98765-4321"), não conta como dado |
| Célula com dois e-mails inválidos guardava o segundo sem máscara (`email_masked`) | a máscara só cobria o primeiro endereço | cada endereço da célula é mascarado |
| "Telefone", "Telfone" e "Coluna2" com celulares 100% válidos ainda perguntavam (confiança 0,46 a 0,78) | a pergunta ao Jev não dizia que a contagem de celulares válidos prova o que a coluna é | o Jev recebe a **proporção** de celulares e e-mails válidos (`valid_phone_share`, `valid_email_share`) e a instrução diz que proporção alta é celular, mesmo com cabeçalho genérico. **Quem decide continua sendo o Jev** |

### O que foi tentado e desfeito

- **Aceitar "não tem empresa" com confiança de 0,5 ou mais.** Isso eliminava as perguntas
  desnecessárias da empresa. Mas o conjunto de controle mostrou que o cabeçalho "Account" (uma
  empresa de verdade) passaria calado como "não tem empresa". Foi desfeito: perguntar a mais é
  melhor que errar calado.
- **Reescrever a pergunta da empresa** ("não tem quando nenhum cabeçalho nomeia uma
  organização"). Deixou o Jev menos seguro do "não tem". Foi desfeito.

## Revisão independente

Um revisor leu o diff antes do push. Os achados aceitos e corrigidos foram:
- o título com telefone acima do cabeçalho (virou o c46 e um spec);
- a máscara do segundo e-mail;
- uma busca repetida a cada linha (O(n²));
- o teto de gasto, que não pararia a bateria se o modelo não tivesse preço (agora para).

Um achado ficou como decisão:
- **Número de 10 dígitos sem o 0 nem o 55.** Agora é lido como celular brasileiro antigo, e
  ganha o 9. Um número estrangeiro escrito sem o código do país (EUA, `917 555 1234`) também
  seria lido assim. A alternativa (só pôr o 9 quando vier 0 ou 55 à frente) recusaria
  "(11) 8765-4321", o formato mais comum das bases antigas, que é o caso que motivou a
  mudança. O risco do número estrangeiro sem código já existe hoje para 11 dígitos.

## O que continua de fora

1. **Perguntas sobre empresa ausente.** Em 4 a 7 de 186 leituras o Jev diz "não tem empresa"
   com confiança entre 0,73 e 0,79, e o motor pede à pessoa para confirmar as colunas. Isso é
   custo de clique, não erro.
2. **DDD numa coluna e número em outra.** O motor não junta colunas. Hoje ele pergunta, e o
   celular fica de fora se a pessoa não tiver outra coluna. Entra na F1 como "juntar colunas".
3. **A mesma pessoa em várias linhas** (duas compras, dois contratos). A segunda linha é recusada
   como repetida. Para a base de clientes isso pode ser a mesma pessoa, e não um erro. Decisão
   de produto da F1.
4. **Célula com dois e-mails** guarda só o primeiro.
5. **Planilha sem cabeçalho cuja primeira linha é só um nome** (sem celular nem e-mail): essa
   linha ainda é lida como cabeçalho, e a pessoa some. Já era assim antes.
6. **Duas tabelas empilhadas na mesma aba:** o cabeçalho da segunda nunca é escolhido. Esse
   formato não é suportado (o motor lê uma tabela por aba).
7. **Os dados são fictícios.** A bateria mede estrutura e cabeçalho, que é o que o Jev vê. Ela
   não substitui uma planilha real: quando chegar uma, vale transformá-la num caso a mais (só a
   estrutura, nunca os dados).
