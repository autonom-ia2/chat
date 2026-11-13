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

### IP próprio da conta (#2942)

Com a flag `agente_ferramentas_prontas_ip_proprio`, as consultas grátis de cada conta saem por um IP próprio do plano
datacenter da Webshare (o Premium e o WhatsApp não mudam). O teto muda junto:

- **o pedido conta só no teto daquele IP**, e esse teto é o **global inteiro** do host (a tabela abaixo). A cota da fonte
  é por IP e o IP é de uma conta só, então a fatia de 25% (que reparte o IP do servidor entre todas as contas) não se
  aplica;
- **não gasta a cota do IP do servidor**: o teto global e a fatia continuam valendo para quem sai por ele (flag
  desligada, ou sem IP próprio, abaixo);
- **o contador é do IP**: o IP que volta da quarentena para outra conta chega com o que já gastou na janela;
- **exceção, a cota da chave**: se alguém configurar a chave gratuita da parallelum ou da AwesomeAPI, a fonte passa a
  limitar pela chave (que vai no cabeçalho também pelo proxy), e o pedido volta a contar no teto global e na fatia,
  saia por onde sair. Hoje as duas ficam sem chave (decisão do Rodrigo, 12/11/2026);
- **os IPs da Webshare são compartilhados com outros clientes dela**: o limite real de cada IP só se conhece medindo.
  Toda resposta 429 ou 403 vai ao log (`[autonomia][pronta][saida] recusa`) e ao contador do dia no Redis
  (`autonomia:prontas:saida:recusas:<dia>`, por saída, host e status, inclusive pelo IP do servidor). Três recusas do
  mesmo host no mesmo IP, sem pausa de 10 minutos, põem o IP de molho por 6 horas (no máximo 5 IPs em 24 horas), e a
  conta ganha outro na consulta seguinte. Com a chave configurada, o 429 e o 403 daquele host não contam para isso;
- **o proxy que cai** (ligação recusada, sem resposta no prazo de abertura ou ao pedido do túnel; túnel recusado, que
  primeiro relê a credencial e tenta uma vez de novo): a chamada repete pelo IP do servidor, no teto dele, e só depois a
  queda conta. Três quedas no mesmo IP numa janela fixa de 20 minutos (aberta pela 1ª queda), zeradas a cada sucesso,
  trocam o IP da conta (no máximo uma troca por conta a cada 24 horas, com o IP antigo de molho por 24 horas, e só se
  houver IP livre). Se o IP novo também cair no mesmo dia, a conta fica pelo servidor até vencer a troca. Sem IP livre
  para a troca, a contagem zera. Mais de 30% dos IPs das contas com a flag ligada caindo na mesma janela (ao menos 2) é
  a Webshare fora: ninguém vai de molho, e todas as contas saem pelo servidor por 20 minutos (alerta `webshare_fora`).
  Túnel com 502 ou 504 e demora com o túnel já aberto são do site: não repetem nem contam contra o IP. Sem Redis, nada
  conta nem troca, e a conta sai pelo servidor;
- **a ida à Webshare cabe no prazo da consulta**: a lista dos IPs só é buscada se der tempo antes do prazo da consulta;
  sem tempo, serve a lista vencida há menos de 30 minutos ou a consulta sai pelo servidor, e a troca do IP fica para a
  próxima queda. Com tempo, a consulta espera a lista nova, e a reconciliação nunca usa a vencida;
- **sem IP próprio** (Webshare fora, fatia vazia, nenhum IP livre, sem tempo para buscar a lista): a consulta sai pelo
  IP do servidor, como antes, e o cliente recebe a resposta; fica o aviso no log, o alerta `sem_ip_proprio` e o contador
  `autonomia:prontas:saida:sem_ip:<dia>` (decisão do Rodrigo, 12/11/2026).

Configuração por stack (só os nomes): `WEBSHARE_API_KEY` (a mesma do WhatsApp Híbrido), `WEBSHARE_LOOKUP_PROXY_ADDRESSES`
(os IPs desta stack para as consultas, separados por vírgula, sem repetir os de outra stack) e os mesmos IPs também em
`WEBSHARE_RESERVED_PROXY_ADDRESSES` (o WhatsApp nunca os oferece). O código confere: IP da fatia fora da reservada fica de
fora, com alerta. `WEBSHARE_DATACENTER_PLAN_ID` é opcional (sem ela, vale o plano datacenter ativo).

**Desligar um provedor sem deploy:** ponha o host na configuração `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS`, uma lista
separada por vírgula. Vale tanto como configuração da instalação (Super Admin) quanto como variável de ambiente.
Desligado, o provedor é pulado com o motivo `provedor_desligado`.

## Fontes, termos e teto

| Host | Fontes | O que o termo pede | Teto global | Cache |
|---|---|---|---|---|
| `brasilapi.com.br` | CEP (última reserva do endereço, só quando nenhuma anterior disse "não tem"), CNPJ, FIPE, feriados, Banco Central (reserva), cidades (reserva), DDD, bancos, código de mercadoria (NCM, F4) | Volume com "natureza de uma pessoa real"; proíbe varredura automatizada (README do projeto, "Termos de Uso"). Não publica número. | 300 por minuto | por consulta; CEP sem cache |
| `viacep.com.br` | CEP (principal do endereço; única do CEP pela rua, `por_endereco`, e do CEP de referência da cidade e do CEP pela rua do Premium, `Cep::Referencia`, uma chamada por cidade, e uma por rua, a cada 30 dias) | Uso moderado; bloqueia uso abusivo. Não publica número. | 60 por minuto | 30 dias |
| `cep.awesomeapi.com.br` | CEP (1ª reserva do endereço; não busca o CEP pela rua) | Sem chave: **limite não publicado**. Com a chave gratuita (cabeçalho `x-api-key`): **100 mil pedidos por mês** ([docs.awesomeapi.com.br/instrucoes-api-key.md](https://docs.awesomeapi.com.br/instrucoes-api-key.md), consultado em 11/11/2026). | Sem chave: 30 por minuto e 1.000 por dia (conservador). Com chave: 120 por minuto e 3.000 por dia (~90% de 100 mil ÷ 30) | 30 dias |
| `minhareceita.org` | CNPJ (reserva) | Não achamos número publicado. | 120 por minuto (padrão) | 1 dia |
| `api.opencnpj.org` | CNPJ (2ª reserva) | Não achamos número publicado na página de documentação. | 120 por minuto (padrão) | 1 dia |
| `parallelum.com.br` | FIPE | **500 pedidos por dia por IP sem chave**; 1.000 com chave gratuita (documentação da API FIPE v2). | **450 por dia** | 1 dia (preço), 7 dias (listas) |
| Fonte parceira (endereços só no ambiente, `PRONTAS_VEICULO_FONTE`) | FIPE: o veículo pela placa ou pelo chassi (#2993) | **Acesso com o cadastro da plataforma**, um só para todas as contas, autorizado pelo Rodrigo em 13/11/2026. Sem número publicado. Sai sempre pelo IP do servidor, nunca pelo IP próprio da conta. Sem a variável, a consulta não é oferecida. | 120 por minuto (padrão) | 1 dia; faltando o valor do mês de uma das 2 primeiras versões, sem cache |
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
| `data.directory.opinbrasil.com.br` e o host de cada seguradora | Produtos das seguradoras (Open Insurance, F4; fora da vitrine desde 11/11/2026, só para os agentes de garantia e de transporte, #2881) | Dados abertos da fase 1 do Open Insurance Brasil, sem chave e sem número publicado. Só seguro garantia (público e privado) e transporte. O endereço de cada seguradora sai sempre do diretório, nunca fixo no código, e o de servidor de teste é descartado; no máximo 2 seguradoras por consulta, com prazo curto. | 30 por minuto (diretório); 120 por minuto (padrão) em cada seguradora | 6 horas (diretório), 3 horas (produtos) |
| `www2.susep.gov.br` | Corretor na SUSEP (F4) | Consulta pública de corretores. **Endpoint sem documentação**, sem chave, sem termo nem limite publicado: o formato é conferido a cada resposta e, se mudar, a fonte responde "não consegui" e deixa `ALERTA corretor_susep` no log. Só nome, situação, registro e ramos vão ao modelo. | 30 por minuto | 12 horas |
| `plataforma.bigdatacorp.com.br` | Os 7 cards Premium (F7): certidões da empresa, raio-X da empresa, conferir a pessoa, histórico da placa, risco do endereço, imóvel rural, contato e mercado de empresas | **Paga, por contrato** (o mesmo da Cotação e da Prospecção, credencial `BIGDATACORP_USER`/`BIGDATACORP_PASSWORD`, só no ambiente). O repasse ao cliente foi liberado pelo advogado (plano aprovado). Cobra por dataset, inclusive a consulta sem registro (a vistoria da Rede Vistorias vazia não é cobrada). Preços da 1ª faixa da documentação pública (até 10 mil consultas por mês), lidos em 11/11/2026. Ficam fora, por desenho: score e restrição de crédito, contato e endereço de pessoa física, parentes, antecedentes, política, apostas, SUS e TSE. | Sem teto por host e sem limite diário por conta e card; sem alerta de orçamento (decisões do Rodrigo, 11/11). O freio é o cache do dia e a telemetria (`Premium::Registro`). 20 grátis por card e por conta a cada mês. Uma tentativa por consulta e uma de token, com teto da chamada inteira no prazo do dataset (nada de repetir consulta paga). | Por conta, até o fim do dia |
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

## Premium (BigDataCorp): o que fica guardado e o que conta

Decisões do Rodrigo de 11/11/2026, registradas aqui porque o comportamento é aceito, não um defeito:

- **O documento consultado fica na linha da consulta em segundo plano.** Quando a consulta Premium sai do turno
  (`agente_ferramenta_em_segundo_plano`), os argumentos já normalizados ficam em `autonomia_agent_tool_runs.arguments`,
  como em qualquer ferramenta em segundo plano: o CPF de "Conferir a pessoa", o CNPJ, a placa. A telemetria
  (`autonomia_ferramentas_premium_consultas`) nunca guarda o valor consultado. A linha da consulta segue a retenção e a
  exclusão da conta.
- **A vistoria sem registro conta para o cliente, com custo zero.** A Rede Vistorias não cobra a consulta vazia, mas a
  regra do cliente é uma só: a consulta respondida conta, mesmo sem registro. Da 21ª do mês em diante, ela entra na
  fatura pelo preço da vistoria, e a telemetria registra custo 0 para nós.
- **Conferir a pessoa devolve nome e data de nascimento**, e o resultado fica no cache da conta até o fim do dia.
- **Telefone de MEI e de empresário individual sai sempre.** O CNPJ é de empresa, mesmo quando o telefone é o da pessoa
  dona. O telefone na lista "não perturbe" continua de fora.
- **A resposta que se perde depois de a chamada sair** (o worker morreu) não conta para o cliente, e a execução fica com
  uma linha só na telemetria (`tool_run_id` único). Se a execução já tinha gravado a linha dela, a linha vira
  `sem_cobranca` com motivo `entrega_incerta`: a grátis volta ao saldo do mês e o preço zera; o custo nosso fica. Se não
  tinha, entra uma linha de falha `entrega_incerta` com o custo do dataset, porque a BigDataCorp pode ter cobrado.
- **Documento inválido: depende de quem recusa** (Rodrigo, 11/11, "A, não conta"). O CPF ou o CNPJ com dígito errado é
  recusado por nós antes de chamar a BigDataCorp e não conta como consulta. O documento que a BigDataCorp recusa depois
  de receber o pedido (-114 "INVALID DOC PARAMETER", -155 "INVALID CAR NUMBER PARAMETER") conta e é cobrado como o sem
  registro (grátis até 20, cobrado da 21ª em diante), e o mesmo documento no mesmo dia vem do cache. A telemetria
  registra o custo cheio do dataset.
- **A falha com o pedido já no ar leva o custo na telemetria, sem contar para o cliente**: a resposta 200 que não lemos,
  o tempo esgotado esperando a resposta e a entrega incerta. A BigDataCorp pode ter cobrado, e a telemetria precisa bater
  com o painel dela. DATASET IS TOO SLOW, o 504, a conexão que nem abriu (o nome que não resolveu, a conexão recusada,
  a rede ou o host fora de alcance, o SSL que não fechou o aperto de mão), o teto da chamada que estoura ainda no token
  e o erro de token seguem sem custo. A resposta que levanta ao ser montada (defeito nosso) também vira falha com o
  nosso custo, sem contar para o cliente.
- **De onde vêm essas regras de custo:** a página "Regras de contabilização de consulta" da BigDataCorp
  (<https://docs.bigdatacorp.com.br/plataforma/docs/regras-de-contabilização-de-consulta-plataforma-de-dados>,
  atualizada em 07/07/2026, consultada em 09/11/2026 e de novo em 11/11/2026), ligada de "Como funciona a cobrança".
  Ela diz "1 consulta = 1 cobrança" e traz a tabela: documento inválido **cobra** ("o retorno é acompanhado do código
  `-114 — INVALID DOC PARAMETER`, que representa uma resposta válida da plataforma"); timeout inferior a 5 minutos
  **cobra** (a consulta segue em processamento); a consulta sem retorno de dados **cobra**, exceto nos datasets de
  contato com documento válido; DATASET IS TOO SLOW **não cobra**; o 504 **não cobra** (a requisição não chega à
  plataforma); o -130 TOO MANY RESULTS sem `Limit` **não cobra**. A página cita só o -114; o -155 (o número do CAR
  recusado) segue a mesma regra por ser o documento inválido do imóvel rural, e isso fica para conferir no painel da
  BigDataCorp (BDC Center) na primeira consulta real.
- **A grátis devolvida acima de 20 não se perde**: quando a entrega incerta desfaz uma grátis num mês que já passou das
  20, a cobrada mais antiga do mês no mesmo card vira grátis. Por isso a fatura lê a coluna `cobranca` (`cobrada`, com o
  `preco`), nunca o `numero`: depois da conversão o número se repete e a grátis convertida fica com número acima de 20.
- **A telemetria que falha no banco deixa marca** no contador do dia: o motivo `premium.telemetria_falhou` em
  `autonomia_ferramentas_prontas_usos.motivos` (por conta, card e dia). A conferência do dia lê ali (consulta no
  comentário de `Premium::Execucao#cobrar`), porque o log some e o rastreador está desligado em produção.
- **Duas consultas iguais da mesma conta no mesmo instante** chamam a BigDataCorp duas vezes e contam as duas. Não há
  trava: ver o comentário de `Premium::Cache`.
- **O 401 da BigDataCorp** apaga o token guardado e permite um reenvio com token novo (o 401 não é cobrado). A
  Prospecção não ganha o reenvio extra; só passa a apagar o token recusado.
- **Preço em centavos inteiros:** custo × 1,5, arredondado para cima ao centavo (o embargo do IBAMA, R$ 0,225, é
  R$ 0,23).

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

## FIPE pela placa ou pelo chassi (#2993)

Quando configurada, a consulta devolve os dados do veículo para o registro da equipe. O agente não deve dizer ao
cliente o chassi nem a placa achada pelo chassi. A identidade da fonte, os endereços e o cadastro ficam fora do repositório.

- **Configuração:** `PRONTAS_VEICULO_FONTE` contém os endereços e o corpo do cadastro. Sem configuração válida, a
  consulta `veiculo` não é oferecida; o card segue com marcas, modelos e preço. Um aviso indica só o campo inválido,
  uma vez por processo.
- **Valor do mês:** vem da consulta de preço da FIPE, para até duas versões. Sem ele, o veículo ainda é entregue,
  mas a resposta não fica no cache para permitir nova tentativa.
- **Falhas:** veículo ausente orienta a conferir o dado e seguir pedindo marca, modelo e ano. Falhas de autenticação
  têm motivo próprio. O aviso da fonte traz só o nome interno do provedor e o status, sem o dado consultado.
- **Placa e chassi vão os dois na resposta**, venha o pedido por um ou pelo outro (decisão do Rodrigo, 13/11/2026).
  Dado de pessoa não vem: esta consulta é só do veículo.
- **Tipo do veículo:** sai do primeiro dígito do código FIPE (0 carro, 5 caminhão, 8 moto), conferido na tabela
  pública em 13/11/2026. Código com outro começo vai sem o tipo.
- **Desligar sem deploy:** o host da consulta em `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS` impede também a autenticação.
  Tirar a variável do ambiente deixa a consulta indisponível no deploy seguinte.

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
