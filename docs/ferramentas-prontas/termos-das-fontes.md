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
| `brasilapi.com.br` | CEP, CNPJ, FIPE, feriados, Banco Central (reserva), cidades (reserva), DDD, bancos | Volume com "natureza de uma pessoa real"; proíbe varredura automatizada (README do projeto, "Termos de Uso"). Não publica número. | 300 por minuto | por consulta |
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
| (sem rede) | CPF válido; feriados (última reserva); DDD (reserva, só o estado); localização (reserva: a sede mais próxima) | Calculado na plataforma. A tabela das sedes vem da base "municipios-brasileiros" (licença MIT, sobre os códigos e nomes do IBGE). | — | CPF, DDD só com o estado e sede aproximada: sem cache |

O teto de cada conta é 25% do global em todas as linhas: por exemplo, 112 pedidos por dia à parallelum e 75 por minuto
à BrasilAPI.

Limitações conhecidas, aceitas:

- **Limite diário: 500 por conta e por fonte em todas as fontes** (decisão do Rodrigo, 10/11). Nenhum provedor da F1
  pede valor menor. A proteção da cota de cada provedor fica no teto global e na fatia por conta, não no limite diário.
- **FIPE (motivo técnico do provedor).** A fatia de 112 pedidos por dia na parallelum fica abaixo do limite diário da
  FIPE (500 por conta). Cada preço por marca e modelo gasta de 2 a 4 pedidos lá; marcas e preço pelo código vão
  primeiro à BrasilAPI, e o cache de 1 dia evita repetir. Uma conta muito ativa pode ouvir "não consegui" antes do
  limite. A saída é a chave gratuita da parallelum (1.000 por dia), decisão em aberto.
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
