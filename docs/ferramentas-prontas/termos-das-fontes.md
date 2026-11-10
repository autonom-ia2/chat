# Ferramentas prontas: termos de uso de cada fonte e o teto global

Épico #2858 (vitrine de ferramentas prontas), F1. Leitura feita em 10/11/2026. Mudou o termo de uma fonte: atualize
esta página e `app/services/autonomia/ferramentas_prontas/teto_do_provedor.rb` no mesmo PR.

## Por que existe um teto global

O limite diário é **por conta e por fonte** (`Uso`). Ele não protege a cota das APIs públicas: elas limitam pelo **IP
de quem chama**, e todas as contas saem do mesmo IP. Sem um teto comum, uma conta movimentada esgotaria a cota de uma
fonte para todas as outras, ou faria a plataforma inteira ser bloqueada.

O teto global (`TetoDoProvedor`) é:

- **por host**: o mesmo host atende várias fontes (a BrasilAPI responde CEP, CNPJ, FIPE, feriados, DDD e bancos);
- **contado só no pedido que sai para a rede**: o que vem do cache não gasta;
- **janela fixa no Redis**: passou do teto, aquele provedor é pulado com o motivo `teto_do_provedor` e a reserva tenta;
- **sem Redis, o pedido segue**: o teto protege a cota, não o dado. Fica um aviso no log.

**Desligar um provedor sem deploy:** ponha o host na configuração `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS`, uma lista
separada por vírgula. Vale tanto como configuração da instalação (Super Admin) quanto como variável de ambiente.
Desligado, o provedor é pulado com o motivo `provedor_desligado`.

## Fontes, termos e teto

| Host | Fontes | O que o termo pede | Teto global | Cache |
|---|---|---|---|---|
| `brasilapi.com.br` | CEP, CNPJ, FIPE, feriados, Banco Central (reserva), cidades (reserva), DDD, bancos | Volume com "natureza de uma pessoa real"; proíbe varredura automatizada (README do projeto, "Termos de Uso"). Não publica número. | 120 por minuto | por consulta |
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
| `nominatim.openstreetmap.org` | Localização (reserva) | Política da OSMF, detalhada abaixo. | **1 por segundo e 40 por minuto** | 30 dias |
| (sem rede) | CPF válido; feriados (última reserva); DDD (reserva, só o estado) | Calculado na plataforma. | — | CPF: sem cache |

## Nominatim (OpenStreetMap Foundation): o que a política exige e como cumprimos

| Exigência | Como cumprimos |
|---|---|
| No máximo 1 pedido por segundo, para a aplicação inteira | Teto global de 1 por segundo e 40 por minuto, somando todas as contas. Ele é só a reserva do Photon. |
| Identificação: User-Agent ou Referer próprio | `User-Agent: Autonomia-FerramentasProntas/1.0`. |
| Cache | Cache de 30 dias por coordenada arredondada. |
| Atribuição (ODbL) | A resposta leva "© colaboradores do OpenStreetMap (ODbL)". |
| Poder desligar a pedido da OSMF sem atualizar o software | `AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS`. |
| Não fazer consulta sistemática (grade, varredura) nem autocompletar | Só a localização que um cliente mandou na conversa, uma por vez. |
| Não oferecer como serviço genérico de geocodificação em plataforma no-code | **Ponto em aberto para o Rodrigo**: ver a decisão abaixo. |

**Privacidade.** A coordenada sai arredondada a 3 casas decimais (cerca de 110 m). Isso basta para dizer a cidade e não
manda a posição exata do cliente a terceiros.

**Decisão em aberto.** A política do Nominatim proíbe embutir a API pública em plataformas no-code como serviço
genérico de geocodificação. O uso aqui é mais estreito: a localização que o cliente mandou vira cidade e estado. Mesmo
assim, o agente é montado pelo cliente da plataforma. A recomendação é manter o Nominatim **só como reserva**, com o
teto, e desligá-lo (`AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS=nominatim.openstreetmap.org`) se o Rodrigo preferir não depender
dessa leitura. Sem ele, com o Photon fora, o agente diz que não conseguiu consultar.

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
| Localização vira cidade | Photon | Nominatim |
| Bancos | BrasilAPI | CSV do STR (Banco Central) |
