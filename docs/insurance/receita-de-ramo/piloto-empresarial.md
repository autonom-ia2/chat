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
