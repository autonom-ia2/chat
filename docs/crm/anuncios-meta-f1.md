# Anúncios da Meta · F1: conexão guiada (#1047)

PRD: https://claude.ai/artifact/L1bQBEwmUCNKdubNkEeMKx. Este arquivo registra as decisões técnicas da F1.

## Entregas

| PR | Conteúdo | Migration |
|---|---|---|
| F1a | Backend: credencial da plataforma, conexão por parceiro ou token, lista de contas e Pixels, verificação real, destinos, "avisar a Meta quando vender". | Sim, vai sozinho na fila |
| F1b | Tela Campanhas › Anúncios da Meta (4 passos), flag `meta_ads_hub`, passo 4 por funil com sugestão da IA (troca o `sales_signal` da F1a), teste do site e confirmação por campanha, Guia, i18n e correções do diagnóstico de 06/10 (CA-1.10). | Não |

## Modos de conexão

- **`partner`.** O cliente compartilha a conta de anúncios e o Pixel com o portfólio da Hub2You, como parceira. O Chat2You lê com o usuário do sistema da plataforma, cujo token fica em `AiProviderCredential('meta_ads')`, cifrado. É o mesmo caminho para as BMs que nós administramos (Hub2You, Placement e Autonomia). Não exige App Review.
- **`token`.** O cliente cola um token próprio com `ads_read`. É o caminho de #1037, mantido como alternativa.
- **`facebook_login`** (#1069). O cliente clica em "Entrar com o Facebook" e passa pelo Login do Facebook para Empresas, com a configuração `META_ADS_LOGIN_CONFIGURATION_ID`. Essa configuração fica no mesmo app da Meta do cadastro do WhatsApp; o app e o segredo vêm de `WHATSAPP_APP_ID`/`WHATSAPP_APP_SECRET`.
  - O código volta para `POST crm/meta_ads_connection/facebook_login`. `Crm::MetaAds::FacebookLogin` troca o código por token, e `Crm::MetaAds::TokenCheck` testa o token como no modo `token` (ads_read e ao menos uma conta). Só então a conexão é gravada, com o token cifrado.
  - Daí em diante o modo se comporta como o `token`: lê com o token do próprio cliente (`own_token?`) e pode mandar eventos a qualquer Pixel que ele enxergue.
  - O token só vale para o modo com que foi salvo: uma chave colada não serve de "login" no passo 2.
  - Sem a configuração, o botão não aparece (`facebook_login.available` no GET).
  - Depende do App Review de `ads_read` no app da Meta. Enquanto ele não sai, só usuários com função no app conseguem entrar.

## Trava entre clientes (modo `partner`)

O token da plataforma enxerga as contas de todos os clientes que compartilharam com a Hub2You. Uma conta do Chat2You só pode escolher uma conta de anúncios quando duas condições valem:

1. O portfólio dono da conta de anúncios (`act_X?fields=business`) é um dos portfólios do WhatsApp dessa mesma conta do Chat2You, em `channel_whatsapp.phone_number_health['business_portfolio_id']`.
2. Nenhuma outra conta do Chat2You já está usando essa conta de anúncios no modo `partner` (índice único parcial).

Quando o dono é outro portfólio, por exemplo um número de WhatsApp registrado no portfólio de quem revende, o modo `partner` recusa com uma frase e oferece o modo `token`.

Travas que valem depois da escolha (revisão de segurança de 06/10):

- **Leitura de nomes.** No modo `partner`, o `NameResolver` pede o `account_id` de cada anúncio, conjunto e campanha. Só grava o que for da conta de anúncios conectada. Um ID de anúncio de outro cliente que chegue num toque vira cache negativo.
- **Envio ao Pixel.** O token da plataforma só envia para o Pixel escolhido na conexão. Qualquer outro Pixel cai no token do WhatsApp do próprio cliente.
- **Dono da conta.** A cada leitura, o dono da conta de anúncios precisa continuar sendo um portfólio do WhatsApp da conta (`MetaAdsConnection#readable?`). Se o número sai, a leitura para.
- **Portfólio compartilhado.** Portfólio que aparece no WhatsApp de mais de uma conta (revendedor) não vale como prova de dono. O portfólio da própria plataforma também não. Essas contas usam o modo `token`.
- **Listar não muda nada na Meta.** O usuário do sistema da plataforma só é atribuído (Ver desempenho) à conta escolhida, e só se ela foi compartilhada por um portfólio da conta.
- **Guia.** Escolher a conta, mudar destinos e avisar a Meta pedem confirmação da pessoa (`SEM_DESFAZER`).
- **Mensagens de erro.** Erro do token da plataforma aparece ao cliente só como código (`platform_token_rejected`).

## "Conectada" só depois de ler de verdade (CA-1.2)

Ao escolher a conta, o servidor lê o nome, o gasto dos últimos 30 dias e o Pixel. Só então grava `verified_at`. Se qualquer leitura falhar, a conexão não muda e a resposta diz o que falta.

## Passo 4: avisar a Meta sobre o funil (CA-1.8)

O passo grava no funil o mesmo que Editar funil grava. Não existe configuração paralela.

- `GET crm/meta_ads_connection/funnels`: funis ativos ligados (`crm_pipeline_inboxes`) a um `Channel::Whatsapp` da conta, com `missing` (`sending_off`, `sales_off`, `moves_off`, `stages`). Também os números oficiais fora de qualquer funil e se a IA está disponível.
- `PATCH crm/meta_ads_connection/funnel`: grava `metadata.funnel_stage_type` de cada etapa (`none` limpa) e liga `meta_sync` com venda e mudança de etapa. A perda e o `dataset_id` ficam como estavam; o Pixel da conexão só entra no funil sem Pixel. Com `enabled: false`, desliga só aquele funil e guarda as escolhas.
- `POST crm/meta_ads_connection/suggest_stages`: a IA (`Crm::MetaAds::StageTypeSuggester`, `gpt-6-luna`) lê nome e critério de cada etapa e sugere o tipo, ou `none`. Roda como as outras ações de IA do CRM (`InteractiveRequest`, 202 + `poll_url`). Quem decide o tipo é o modelo, não uma lista de palavras; a pessoa revisa antes de gravar. Etapas de ganho e perda ficam de fora, porque viram `Purchase`/`OrderCanceled` pelo fechamento do card.
- Funil sem WhatsApp oficial, etapa de outro funil ou tipo fora da lista são recusados (`funnel_not_found`, `invalid_stage`, `invalid_stage_type`).

## Passo 3: site (CA-1.6 e CA-1.7)

- **Testar agora** abre a página autorizada do link e consulta `ctwa_tracked_links` a cada 5 s, por até 3 min, até `last_signal_at` mudar. Compara com o aviso anterior, não com o relógio do navegador.
- **Campanhas chegando com nome** vem de `campaigns` do mesmo endpoint: cada campanha com `utm_campaign` aparece confirmada; cliques sem nome aparecem somados, com o pedido de colar o texto no anúncio.
- A página pública com instruções para quem cuida do site fica para depois: hoje elas estão em Links e QR codes › Para o desenvolvedor.

## F1c: correções do teste real (#1068)

Teste com a Placement em 06/10, depois do deploy de #1053 e #1064:

- **Conta que nunca ficava pronta (modo parceiro).** `Setup#assigned_ids` perguntava `/{usuário do sistema}?fields=assigned_ad_accounts` e, se a Meta recusasse, devolvia lista vazia em silêncio. Agora usa `me/adaccounts` com o próprio token da plataforma (que é o do usuário do sistema) e qualquer recusa vira erro na tela.
- **Log das recusas da Meta.** `Meta::AdsGraphClient` registra `[MetaAdsGraph] VERBO caminho http= code= message=` em toda falha. O token nunca entra no caminho e a mensagem passa pela limpeza de segredos.
- **Abrir a Meta** leva `business_id` (`client_portfolio_id` no payload); sem ele a Meta abria "conteúdo não disponível".
- **Modo de conexão visível e fixo.** O passo 2 diz por onde lê; o modo escolhido fica em `?modo=` e não volta em silêncio para a chave antiga.
- **Kit do desenvolvedor (CA-1.6).** `GET /l/:code/kit` (público, `noindex`, só para link de site): código pronto do botão, com os valores como JSON escapado (`json_escape`), gerado a partir da ponte do site da Placement.
- **Último clique sem nome.** `Ctwa::TrackedLinkCampaigns` devolve `last_clicked_at` por campanha.
- Menu: "Anúncios da Meta" entra na jornada nova de Campanhas (`journeySidebar.js`).

## O que a F1 não faz

- Coleta diária de insights (F2).
- Painel (F3).
- Consultor (F4).
- Resumo no WhatsApp (F5).
- Escrita na conta de anúncios.
