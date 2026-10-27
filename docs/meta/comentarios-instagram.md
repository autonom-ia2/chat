# Comentários do anúncio no Instagram (#2196)

Runbook da aba Instagram dos comentários no detalhe do anúncio (Anúncios da Meta › Resultado). O código está em
`Crm::MetaAds::InstagramComments`, `Crm::MetaAds::InstagramPrivateReply`, `Instagram::CommentsClient` e
`Webhooks::InstagramCommentJob`.

## Flag e acesso padrão até a aprovação da Meta

- A aba aparece com as flags `meta_ads_gestao` e `meta_ads_comentarios_instagram` ligadas na conta.
- A permissão `instagram_business_manage_comments` está em **acesso padrão** até a Meta aprovar o pedido enviado em
  14/11/2026. Enquanto isso, ela só funciona para um Instagram cujo dono tem função no app Autonom.ia (administrador,
  desenvolvedor ou testador).
- **Regra:** só ligar `meta_ads_comentarios_instagram` em conta cujo Instagram pertence a alguém com função no app. Hoje
  isso vale para as contas piloto (lista interna) e para uma caixa de testador da equipe.
- Numa conta fora dessa regra, "Entrar de novo" no cartão leva a um erro da própria Meta. A tela não avisa isso, porque o
  aviso ficaria errado depois da aprovação.
- Depois da aprovação, a regra cai e a flag pode seguir o caminho normal de liberação.
- `REQUIRED_SCOPES` não muda. O escopo de comentários só é pedido na reautorização que sai do cartão dos comentários
  (`REAUTH_PURPOSES['meta_ads_comentarios_instagram']`).

## Quem faz o quê

| Ação | Permissão |
|---|---|
| Ver comentários | `meta_ads_view` (ou administrador) |
| Responder, ocultar, mostrar, apagar | `meta_ads_manage` |
| Responder no privado | `meta_ads_manage` e ser da caixa do Instagram (`InboxPolicy#show?`) |
| "Não foi enviado" | `meta_ads_manage` |
| Entrar de novo | `integration_manage` (fluxo de reautorização da caixa) |

Toda ação vai para a Auditoria da conta (`meta_ads_comment`), sem o texto.

## Estados da resposta no privado

A Meta aceita uma resposta no privado por comentário, até 7 dias depois dele, e só em comentário de primeiro nível. A
linha em `crm_meta_ads_comment_actions` (`action = 'private_reply'`) diz em que pé está:

| Estado | Colunas | O que a tela mostra | Como sai |
|---|---|---|---|
| Reservado | `attempted_at` nulo | Nada muda até a resposta | A chamada sai (`attempted_at`, uma vez só, por UPDATE condicional). Se o processo morrer antes, nada foi enviado: depois de `RESERVED_TTL` (2 min) a reserva não vale mais, e quem a perdeu no meio não chama a Meta |
| Em andamento | `attempted_at` recente, sem `failed_at` nem `confirmed_at` | "Enviado no privado, sem confirmação do Instagram. Confira no Direct.", sem o botão | Resposta da Meta |
| Sem confirmação | `failed_at` preenchido (rede, tempo esgotado, 5xx), ou `attempted_at` mais velho que `IN_FLIGHT` (1 min sem resposta: processo morreu durante a chamada, ou a confirmação não foi gravada), e `confirmed_at` nulo | O mesmo texto, com "Se a mensagem estiver lá, não clique", e o botão "Não foi enviado" | O botão aparece na hora com falha de rede, ou depois de 1 min sem resposta. O envio só é liberado pela ação manual de quem gere, depois de conferir o Direct |
| Confirmado | `confirmed_at` preenchido | "Respondido no privado" e o link da conversa | Não sai |

Recusa explícita da Meta (4xx) apaga a linha, e o botão volta na hora.

"Sem confirmação" acontece quando a chamada saiu mas a resposta se perdeu (rede caiu, tempo esgotado, 5xx). A Meta pode
ter entregado, então um segundo envio seria uma DM duplicada. Por isso o botão fica travado até uma pessoa conferir.

**O que fazer quando aparecer "sem confirmação":**

1. Abrir o Direct do Instagram da caixa e procurar a conversa com quem comentou.
2. Se a mensagem está lá, não fazer nada: ela foi entregue.
3. Se não está, clicar em "Não foi enviado" no comentário. O botão "Responder no privado" volta.

## Webhook

O roteador (`Webhooks::InstagramEventsJob#enqueue_comment`, #2200) chama
`Webhooks::InstagramCommentJob.perform_later(instagram_id, 'comments', value_ids, time)`, só com os ids (`id`,
`parent_id`, `from.id`, `media.id`, `media.ad_id`). O job:

- lê o texto e o autor na Graph;
- publica `meta_ads.comment_received`, um evento em memória que nada grava;
- descarta o mesmo comentário por 10 minutos. A chave do dedupe é gravada antes da leitura na Graph e só fica se o
  evento saiu; em qualquer outro desfecho (sem resultado, eco, erro, desligamento do Sidekiq) ela é solta.

O `value` completo antigo ainda é aceito até o fim da transição (#2291, prazo 15/11/2026).
