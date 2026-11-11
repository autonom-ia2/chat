# Ferramentas prontas: termos de uso de cada fonte e o teto global

Épico #2858 (vitrine de ferramentas prontas), F1. Leitura feita em 10/11/2026. Mudou o termo de uma fonte: atualize
esta página e `app/services/autonomia/ferramentas_prontas/teto_do_provedor.rb` no mesmo PR.

## Por que existe um teto global

O limite diário é **por conta e por fonte** (`Uso`). Ele não protege a cota das APIs públicas: elas limitam pelo **IP
de quem chama**, e todas as contas saem do mesmo IP. Sem um teto comum, uma conta movimentada esgotaria a cota de uma
fonte para todas as outras, ou faria a plataforma inteira ser bloqueada.

O teto global (`TetoDoProvedor`) é:

- **por host**: o mesmo host atende várias fontes (a BrasilAPI responde CEP, CNPJ, FIPE, feriados, DDD e bancos);
- **com fatia por conta**: cada conta usa no máximo 25% do teto do host na mesma janela (ao menos 1 pedido). Uma conta,
  ou um contato insistente, não gasta a cota de todas;
- **válido também para CEP, CNPJ e FIPE (F0)**, de propósito: a cota do IP é a mesma;
- **contado só no pedido que sai para a rede**: o que vem do cache não gasta;
- **janela fixa no Redis**: passou do teto, aquele provedor é pulado com o motivo `teto_do_provedor` e a reserva tenta;
- **sem Redis, o pedido segue**: o teto protege a cota, não o dado. Fica um aviso no log.

**Desligar um provedor sem deploy:** ponha o host na configuração `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS`, uma lista
separada por vírgula. Vale tanto como configuração da instalação (Super Admin) quanto como variável de ambiente.
Desligado, o provedor é pulado com o motivo `provedor_desligado`.

## Fontes, termos e teto

| Host | Fontes | O que o termo pede | Teto global | Cache |
|---|---|---|---|---|
| `brasilapi.com.br` | CEP (última reserva do endereço, só quando nenhuma anterior disse "não tem"), CNPJ, FIPE, feriados, Banco Central (reserva), cidades (reserva), DDD, bancos, código de mercadoria (NCM, F4) | Volume com "natureza de uma pessoa real"; proíbe varredura automatizada (README do projeto, "Termos de Uso"). Não publica número. | 300 por minuto | por consulta; CEP sem cache |
| `viacep.com.br` | CEP (principal do endereço; única do CEP pela rua, `por_endereco`, e do CEP de referência da cidade, `Cep::Referencia`, uma chamada por cidade a cada 30 dias) | Uso moderado; bloqueia uso abusivo. Não publica número. | 60 por minuto | 30 dias |
| `cep.awesomeapi.com.br` | CEP (1ª reserva do endereço; não busca o CEP pela rua) | Sem chave: **limite não publicado**. Com a chave gratuita (cabeçalho `x-api-key`): **100 mil pedidos por mês** ([docs.awesomeapi.com.br/instrucoes-api-key.md](https://docs.awesomeapi.com.br/instrucoes-api-key.md), consultado em 11/11/2026). | Sem chave: 30 por minuto e 1.000 por dia (conservador). Com chave: 120 por minuto e 3.000 por dia (~90% de 100 mil ÷ 30) | 30 dias |
| `minhareceita.org` | CNPJ (reserva) | Não achamos número publicado. | 120 por minuto (padrão) | 1 dia |
| `api.opencnpj.org` | CNPJ (2ª reserva) | Não achamos número publicado na página de documentação. | 120 por minuto (padrão) | 1 dia |
| `parallelum.com.br` | FIPE | **500 pedidos por dia por IP sem chave**; 1.000 com chave gratuita (documentação da API FIPE v2). | **450 por dia** | 1 dia (preço), 7 dias (listas) |
| `date.nager.at` | Feriados (reserva) | API aberta, sem chave. A página de termos não trouxe número. | 30 por minuto | 30 dias |
| `api.bcb.gov.br` | Banco Central (SGS) | Dados abertos do Banco Central, sem chave e sem limite publicado. | 120 por minuto (padrão) | 1 a 6 horas |
| `olinda.bcb.gov.br` | Banco Central (PTAX e Focus) | Dados abertos do Banco Central, sem chave e sem limite publicado. | 120 por minuto (padrão) | 1 a 6 horas |
| `www.bcb.gov.br` | Bancos (reserva: CSV do STR) | Arquivo de dados abertos. | 120 por minuto (padrão) | 30 dias |
| `servicodados.ibge.gov.br` | Cidades e estados | Serviço de dados do IBGE, aberto e sem chave. Sem limite publicado. | 120 por minuto (padrão) | 30 dias |
| `photon.komoot.io` | Localização | "Seja justo: uso extenso é limitado"; disponibilidade sem garantia. Sem número. | 60 por minuto | 30 dias |
| `apidadosabertos.saude.gov.br` | Hospitais e clínicas (CNES, F4) | API de dados abertos do Ministério da Saúde, sem chave; o swagger diz licença MIT. Sem limite publicado. No máximo 20 por pedido. Estabelecimento em nome de pessoa física sai da resposta. | 120 por minuto (padrão) | 7 dias |
| `pncp.gov.br` | Compras do governo (F4) | Dado aberto por lei (art. 174 da Lei 14.133/2021), sem chave e sem número publicado. Modalidade obrigatória; página de 10 a 50. Lento a frio: medido em 11/11/2026, de 2,8 s a 17,2 s no período de 7 dias; a mesma consulta pedida de novo volta em cerca de 0,1 s, mesmo quando desistimos da primeira (o portal termina e guarda). Prazo: 4 s por chamada, 7 s no total. Na mesma medição, respondeu 429 depois de cerca de 13 pedidos seguidos em 90 s. | 60 por minuto | 1 hora |
| `apitempo.inmet.gov.br` | Estações do tempo (F4) | Dado aberto do INMET, sem chave e sem número publicado. Só a lista das estações (os dados delas exigem token, que não usamos). | 30 por minuto | 1 dia (lista inteira) |
| `archive-api.open-meteo.com` | Quanto choveu (F4) | **Plano gratuito só para uso não comercial**: menos de 10.000 por dia, 5.000 por hora e 600 por minuto. Uso comercial pede plano pago (chave, `customer-api.open-meteo.com`). Dados CC BY 4.0, com atribuição. **Sobe com o plano gratuito por decisão do Rodrigo (10/11/2026), risco aceito.** | 540 por minuto, 4.500 por hora, 9.000 por dia | 6 horas |
| `data.directory.opinbrasil.com.br` e o host de cada seguradora | Produtos das seguradoras (Open Insurance, F4) | Dados abertos da fase 1 do Open Insurance Brasil, sem chave e sem número publicado. O endereço de cada seguradora sai sempre do diretório, nunca fixo no código; no máximo 2 seguradoras por consulta, com prazo curto. | 30 por minuto (diretório); 120 por minuto (padrão) em cada seguradora | 6 horas (diretório), 3 horas (produtos) |
| `www2.susep.gov.br` | Corretor na SUSEP (F4) | Consulta pública de corretores. **Endpoint sem documentação**, sem chave, sem termo nem limite publicado: o formato é conferido a cada resposta e, se mudar, a fonte responde "não consegui" e deixa `ALERTA corretor_susep` no log. Só nome, situação, registro e ramos vão ao modelo. | 30 por minuto | 12 horas |
| (sem rede) | Exames e procedimentos (TUSS, F4); nome de doenças (CID-10, F4) | Tabelas oficiais no repositório (`lib/ferramentas_prontas/`, origem e termos ao lado): a TUSS 22 da ANS (dados abertos, PDA-049; **licença do conjunto não confirmada**, parte das publicações da ANS é CC BY-NC-SA; uso autorizado pelo Rodrigo em 10/11/2026) e a CID-10 do DATASUS. Um robô diário no GitHub (`ferramentas-prontas-tabelas.yml`) baixa as duas e abre PR quando mudam; nada é baixado em produção. | — | sem cache |
| (sem rede) | CPF válido; feriados (última reserva); DDD (reserva, só o estado); localização (reserva: a sede mais próxima) | Calculado na plataforma. A tabela das sedes vem da base "municipios-brasileiros" (licença MIT, sobre os códigos e nomes do IBGE). | — | CPF, DDD só com o estado e sede aproximada: sem cache |

O teto de cada conta é 25% do global em todas as linhas: por exemplo, 112 pedidos por dia à parallelum e 75 por minuto
à BrasilAPI.

Limitações conhecidas, aceitas:

- **Limite diário: 500 por conta e por fonte em todas as fontes** (decisão do Rodrigo, 10/11). Nenhum provedor da F1
  pede valor menor. A proteção da cota de cada provedor fica no teto global e na fatia por conta, não no limite diário.
- **FIPE (motivo técnico do provedor).** A fatia de 112 pedidos por dia na parallelum fica abaixo do limite diário da
  FIPE (500 por conta). Cada preço por marca e modelo gasta de 2 a 4 pedidos lá; marcas e preço pelo código vão
  primeiro à BrasilAPI, e o cache de 1 dia evita repetir. Uma conta muito ativa pode ouvir "não consegui" antes do
  limite. A saída é a chave gratuita da parallelum (1.000 por dia): o código lê da variável de ambiente opcional
  `AUTONOMIA_PRONTAS_FIPE_TOKEN` e funciona sem ela. Com a chave, o teto global da parallelum sobe para 900 por dia
  (fatia de 225 por conta). Criar a conta no serviço é decisão do Rodrigo.
- **CEP: três fontes, e a BrasilAPI por último (#2906, decisão do Rodrigo 11/11/2026: "bom ter os dois ou mais,
  para termos margem de rate limit").** A ordem do endereço pelo CEP é ViaCEP, AwesomeAPI e BrasilAPI. Medido em
  11/11/2026: a BrasilAPI responde todo CEP pelo `open-cep`, um espelho do ViaCEP que inventa endereço para o CEP que
  não existe (99999-999 vira "Avenida das Torres, Sarandi-PR"). Por isso ela só responde quando nenhuma fonte anterior
  disse "não tem". **Quando ela responde:** sempre que o ViaCEP e a AwesomeAPI ficam sem resposta, por qualquer falha,
  e não só quando caem: prazo estourado, erro 5xx, limite da fonte (429) e o teto do provedor. A fatia de cada conta sem
  chave é ViaCEP 15 por minuto e AwesomeAPI 7 por minuto e 250 por dia, então uma conta ativa chega à BrasilAPI no uso
  normal. **Risco residual, aceito:** nesses casos, um CEP que não existe pode receber um endereço inventado da
  BrasilAPI. Por isso a resposta dela **não vai ao cache**: o endereço inventado não fica 30 dias valendo para todas as
  contas, e a próxima consulta do mesmo CEP vai de novo ao ViaCEP. A chave gratuita da AwesomeAPI é opcional: o código lê da
  variável de ambiente `AUTONOMIA_AWESOMEAPI_CHAVE` e funciona sem ela. Criar a conta no serviço é decisão do Rodrigo.
- **Localização (motivo técnico do provedor).** O Photon pede uso justo: a fatia de cada conta é 15 pedidos por minuto,
  e acima disso a reserva (a sede mais próxima, sem rede) responde. O limite diário segue 500.
- **Janela fixa.** Na virada da janela (por exemplo, à meia-noite UTC no teto diário), saem até duas janelas de
  pedidos em pouco tempo. Nenhum termo lido exige teto por segundo, então isso fica aceito.
- **Redis fora.** O teto deixa o pedido passar, e a lista de hosts desligados cai para a variável de ambiente. Para
  desligar um host de forma garantida, use as duas: a configuração da instalação e a variável de ambiente.

## Nominatim: fora

O termo 12 do épico #2858 deixa o Nominatim fora, pela política de uso da OSMF (1 pedido por segundo, proibição de
embutir a API pública em plataforma no-code como serviço genérico de geocodificação). A reserva da localização é a
sede de município mais próxima, calculada aqui, sem rede.

## Localização: privacidade e nome conferido

- A coordenada sai arredondada a 3 casas decimais (cerca de 110 m), já no registro da consulta: basta para a cidade e
  não manda a posição exata do cliente a terceiros.
- O nome do município que o Photon devolve só vale se for um município daquele estado na tabela das sedes. O nome no
  OpenStreetMap é editável por qualquer pessoa, e um nome que não confere não chega ao modelo.
- A resposta leva a atribuição "© colaboradores do OpenStreetMap (ODbL)".

## CPF

Calculado aqui: nenhum pedido sai, a resposta não traz o número, e a consulta não vai ao cache nem à linha da consulta
em segundo plano (responde na hora).

## Reserva de cada fonte da F1

| Fonte | Principal | Reserva |
|---|---|---|
| CPF válido | cálculo local | — (não depende de rede) |
| Feriados e dias úteis | BrasilAPI | Nager.Date, depois o calendário calculado aqui |
| Banco Central: Selic e IPCA | SGS | BrasilAPI (do IPCA, só o acumulado de 12 meses) |
| Banco Central: dólar | PTAX (Olinda) | SGS 1 e 10813 |
| Banco Central: Focus | Olinda | **nenhuma**: só o Banco Central publica. Com a fonte fora, o agente ouve "não consegui". |
| Cidades e estados | IBGE | BrasilAPI |
| DDD | BrasilAPI | plano de numeração local (só o estado) |
| Localização vira cidade | Photon | a sede de município mais próxima, calculada aqui (aproximada) |
| Bancos | BrasilAPI | CSV do STR (Banco Central) |

Fora da F4, à espera do advogado: **Domínio .br** (RDAP do Registro.br). O aviso da resposta proíbe "distribution,
commercialization, reproduction"; o código está guardado para um PR próprio depois do parecer (decisão do Rodrigo, 10/11/2026).

## FIPE pelo nome: quantas chamadas uma pergunta gasta (regra "QI 70", #2858)

O agente manda a marca e o modelo pelo nome; o servidor tira o código das listas (`fontes/fipe/pelo_nome.rb`). O que fica
no cache: lista de marcas e lista de modelos da marca por 7 dias, anos de um veículo por 7 dias (`Fipe::ANOS`), preço
por 1 dia. "Cache frio" é a primeira pergunta sobre aquela marca e carro; "quente", a repetição dentro da validade.

| Pergunta | Cache frio | Cache quente |
|---|---|---|
| Marca + modelo com uma versão só + ano ("Voyage 2020") | 4: marcas (BrasilAPI), modelos, anos e preço (parallelum) | 0 (preço do dia) ou 1 (preço de outro ano) |
| Marca + modelo com várias versões + ano ("Gol 2020", #2906) | até 10: marcas, modelos, anos da marca, os modelos de cada combustível do ano (até 3, `Fipe::MODELOS_DO_ANO`) e, com várias versões no ano, anos e preço de 2 delas (a faixa, sem exigir a escolha) | 0 (preço do dia); os modelos do ano ficam 7 dias |
| Marca + modelo com várias versões, sem o ano ("quanto vale um Gol?") | 2 na recusa (marcas, modelos), que pergunta o ano e não gasta o limite da conta | 0 |
| Sem o ano ("quanto vale um Voyage?") | 5: marcas, modelos, anos e o preço do ano mais antigo e do mais novo (a faixa) | 0 (a faixa do dia) |
| Pelo código FIPE, com ou sem ano | 1 (BrasilAPI); com ela fora, 2 ou 3 na parallelum | 0 |

Um ano com mais de um combustível soma uma chamada por combustível, até 3 (`MAX_ANOS_COM_PRECO`). Na parallelum sem
chave (teto de 450 por dia na plataforma, 112 por conta), o cache frio de uma pergunta gasta de 3 a 9 desses pedidos (o
de mais versões, "Gol 2020", é o de 9). A faixa de versões é de duas delas (a de nome mais curto e a de nome mais
longo), não o mínimo e o máximo garantidos: isso pediria uma chamada por versão.
