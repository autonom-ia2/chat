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
| `brasilapi.com.br` | CEP, CNPJ, FIPE, feriados, Banco Central (reserva), cidades (reserva), DDD, bancos, código de mercadoria (NCM, F4) | Volume com "natureza de uma pessoa real"; proíbe varredura automatizada (README do projeto, "Termos de Uso"). Não publica número. | 300 por minuto | por consulta |
| `viacep.com.br` | CEP (reserva) | Uso moderado; bloqueia uso abusivo. Não publica número. | 60 por minuto | 30 dias |
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
| `pncp.gov.br` | Compras do governo (F4) | Dado aberto por lei (art. 174 da Lei 14.133/2021), sem chave e sem número publicado. Modalidade obrigatória; página de 10 a 50. Lento na 1ª chamada (até 6 s). | 60 por minuto | 1 hora |
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

## Bases baixadas pela plataforma (F5)

Leitura das fontes em 11/11/2026: endereço, formato e tamanho conferidos com um download de cada arquivo real; as
licenças, no catálogo de dados abertos de cada órgão. Download de dado aberto é permitido; a plataforma baixa **uma
vez por rodada** (diária ou mensal), no job `AtualizarBasesJob`, e **só quando alguma conta tem a flag
`agente_ferramentas_prontas_bases`**. A consulta do agente é no nosso banco: nenhum pedido do cliente sai para a fonte,
então o teto global por host não se aplica aqui.

Quando roda: o job passa a cada 5 minutos (`config/schedule.yml`) e só age depois do horário da stack, em UTC, na
variável **`AUTONOMIA_PRONTAS_BASES_HORARIO_UTC`** (`"HH:MM"`). Sem ela, cada stack tira o seu do próprio endereço
(`FRONTEND_URL`), entre 10:00 e 11:55 UTC, para as duas stacks não baixarem no mesmo minuto. Valor fora de `HH:MM`
(hora 0–23, minuto 0–59): alerta uma vez por dia (log e Sentry) e vale o horário da stack. Uma base por vez em toda a
plataforma, as diárias pequenas primeiro (focos de queimada, planos de saúde, aeronaves; depois placas solares e
transportadoras): a próxima entra quando a anterior termina. A que falhou no dia espera o dia seguinte, menos os focos
de queimada, que tentam de novo 3 horas depois da última tentativa. A rodada que morreu no meio (nem atualizou nem
registrou falha) também tenta de novo 3 horas depois: as travas de quem morreu vencem antes (2h30). A mensal vence
pela data, do 28º dia em diante.

| Base | Endereço | Formato e tamanho real | Licença e termos | Frequência | O que fica (e o que não fica) |
|---|---|---|---|---|---|
| Planos de saúde (ANS) | `dadosabertos.ans.gov.br/FTP/PDA/operadoras_de_plano_de_saude_ativas/Relatorio_cadop.csv` e `.../operadoras_de_plano_de_saude_canceladas/Relatorio_cadop_canceladas.csv` | CSV `;`, UTF-8; 345.634 B (ativas) + 1.039.052 B (canceladas); 4.186 operadoras | Dados abertos da ANS (PDA), Decreto 8.777/2016. **A licença do conjunto não está escrita na página**; parte das publicações da ANS usa CC BY-NC-SA (mesma ressalva da TUSS na F4). | diária | Registro, CNPJ, razão social, fantasia, modalidade, cidade, UF, datas e motivo do cancelamento. **Não fica**: representante (pessoa física), e-mail, telefone, endereço. |
| Aeronaves (RAB da ANAC) | `sistemas.anac.gov.br/dadosabertos/Aeronaves/RAB/dados_aeronaves.csv` | CSV `;`, UTF-8 com BOM e uma linha "Atualizado em" antes do cabeçalho; 24.353.159 B; 35.150 matrículas (74 repetidas no arquivo) | Dados abertos da ANAC, Decreto 8.777/2016. A página do conjunto não traz licença escrita. | diária | Fabricante, modelo, ano, assentos, peso, situação, cancelamento, validade do certificado, gravames e **só as empresas** (CNPJ válido) donas e operadoras, com o nome sem nenhum CPF (o MEI leva o do dono no nome). **Pessoa física nunca entra**: o arquivo traz ~29 mil CPFs e nomes de donos; viram só a contagem `outros_proprietarios`, sem nome, CPF ou UF. |
| Placas solares (geração distribuída da ANEEL) | `dadosabertos.aneel.gov.br/dataset/5e0fafd2-…/resource/b1bd71e7-…/download/empreendimento-geracao-distribuida.zip` | ZIP de 113.020.800 B com um CSV `;`, UTF-8, de 1.556.562.996 B e 4.735.908 linhas | **ODbL** (Open Database License), no catálogo da ANEEL: uso livre com atribuição e compartilhamento pela mesma licença do banco derivado. | mensal (a ANEEL publica todo dia; o plano pediu mensal) | Só a **soma** por CEP, município, tipo e classe de consumo (~158 mil linhas). **Não fica**: titular (nome ou CPF/CNPJ tarjado), código do empreendimento, coordenada. O ZIP é lido do disco; o CSV, por streaming de dentro dele, com teto de 4 GB aberto. |
| Transportadoras (RNTRC da ANTT) | descoberto a cada rodada no catálogo `dados.antt.gov.br/api/3/action/package_show?id=rntrc` (o arquivo do mês muda de endereço); hoje `.../transportadores_rntrc_10_2026.csv` | CSV `;`, ISO-8859-1; 164.851.598 B; 1.201.583 registros (853 mil autônomos, 348 mil empresas, 548 cooperativas), só ATIVO e PENDENTE | **Creative Commons Atribuição**, no catálogo da ANTT. | mensal (a ANTT publica perto do dia 10) | **Todos os registros ficam** (decisão do Rodrigo, 11/11/2026). Nome e CNPJ só da empresa e da cooperativa **com CNPJ válido**, e o nome sem nenhum CPF (o MEI leva o do dono no fim da razão social, às vezes colado por um hífen). A busca pelo nome é no começo de cada palavra, sem acento e sem caixa; o autônomo não tem nome, e só se acha pelo RNTRC. **Autônomo (pessoa física)**, documento que é CPF ou categoria desconhecida: só RNTRC, categoria, situação, município, UF e datas; nome e CPF (que vem parcialmente mascarado) não ficam. |
| Focos de queimada (INPE) | `dataserver-coids.inpe.br/queimadas/queimadas/focos/csv/diario/Brasil/focos_diario_br_AAAAMMDD.csv` (link "Diários" da página de dados abertos do Programa Queimadas) | CSV `,`, UTF-8; ~1,2 MB e ~8.300 focos num dia de novembro | Dado aberto do INPE. **A página não traz licença escrita**; vale a política de dados abertos federal. | diária (janela de 8 dias baixada de novo a cada rodada, ~10 MB) | Quando, coordenada (3 casas), código IBGE do município, bioma e satélite. Nada de pessoa. |

Ressalvas:

- **Tetos do download** (`MAX_BYTES` de cada importador): 20 MB (ANS), 100 MB (RAB), 400 MB (ZIP da ANEEL; 4 GB
  aberto), 400 MB (ANTT), 30 MB por dia (INPE). Prazo total de 2 a 30 minutos. Só HTTPS na 443, só o host do
  importador, redirecionamento só para a mesma origem (`Bases::Download`, sobre o `SafeFetch`).
- **Arquivo quebrado não troca a base**: coluna esperada que sumiu ou campo acima de 64 KB (`formato_mudou`), menos
  linhas que o mínimo da base ou menos da metade da rodada anterior (`base_encolheu`; os focos de queimada não têm essa
  fração, porque variam de verdade). Nesses casos e em qualquer falha do download, a cópia anterior continua valendo.
- **Alerta = log e Sentry** (decisão do Rodrigo, 11/11/2026: "Deixa no log"). Toda falha grava o log
  `[autonomia][pronta] ALERTA base=… motivo=… vale_a_copia_de=…` e, quando a instalação tem `SENTRY_DSN`, vai ao
  Sentry. Nada vai para o Guia, para o sino ou por e-mail, e nada para conta de cliente. Falha depois da troca (ao
  apagar a geração antiga) registra `limpeza_pendente`: a nova já vale, e a rodada, 3 horas depois, só apaga a sobra
  (sem baixar de novo). Os DELETEs rodam com o mesmo prazo longo do COPY (2 h).
- **Licença não escrita em ANS, ANAC e INPE: sobem assim** (decisão do Rodrigo, 11/11/2026: "Sobe tudo"). A página de
  cada conjunto não traz licença escrita; o uso se apoia na política de dados abertos federal (Decreto 8.777/2016).
- **Focos de queimada com mais de 1 dia** (a rodada diária falhou; 26 h de folga): a ferramenta responde "não consegui
  consultar", nunca "nenhum foco". Sem nenhum foco no lugar, a resposta é `focos_no_periodo` zero, com o dia da base.
- **Espaço no banco**: a maior tabela é a das transportadoras (~1,2 milhão de linhas). Durante a troca, a geração nova
  e a antiga convivem até a antiga ser apagada. Medido em 11/11/2026, no banco de teste, com o arquivo oficial do dia
  (tabela e índices, uma geração):

  | Base | Linhas | Espaço | Tempo da importação |
  |---|---|---|---|
  | Planos de saúde (ANS) | 4.186 | 3,3 MB | |
  | Focos de queimada (INPE) | 136.711 | 45 a 58 MB | |
  | Aeronaves (ANAC) | 35.150 | 27 a 29 MB | |
  | Placas solares (ANEEL) | 158.110 | 124 MB | ~10,9 min |
  | Transportadoras (ANTT) | 1.201.583 | 689 MB; passa de ~1,4 GB durante a troca, com as duas gerações | ~2,5 min |

  Os dois tempos medidos ficam dentro da trava de 2h30 da rodada. O espaço não é guardado pela importação: o `Estado`
  guarda as linhas, e guardar o tamanho pediria coluna nova sem servir ao alerta, que só olha a falha.
