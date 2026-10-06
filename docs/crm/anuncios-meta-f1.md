# Anúncios da Meta · F1: conexão guiada (#1047)

PRD: https://claude.ai/artifact/L1bQBEwmUCNKdubNkEeMKx. Este arquivo registra as decisões técnicas da F1.

## Entregas

| PR | Conteúdo | Migration |
|---|---|---|
| F1a | Backend: credencial da plataforma, conexão por parceiro ou token, lista de contas e Pixels, verificação real, destinos, "avisar a Meta quando vender". | Sim, vai sozinho na fila |
| F1b | Tela Campanhas › Anúncios da Meta (4 passos), flag `meta_ads_hub`, Guia, i18n e correções do diagnóstico de 06/10 (CA-1.10). | Não |

## Dois modos de conexão

- **`partner`.** O cliente compartilha a conta de anúncios e o Pixel com o portfólio da Hub2You, como parceira. O Chat2You lê com o usuário do sistema da plataforma, cujo token fica em `AiProviderCredential('meta_ads')`, cifrado. É o mesmo caminho para as BMs que nós administramos (Hub2You, Placement e Autonomia). Não exige App Review.
- **`token`.** O cliente cola um token próprio com `ads_read`. É o caminho de #1037, mantido como alternativa.
- O "Entrar com Facebook" (Facebook Login for Business) entra depois do App Review e vira um terceiro modo.

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

## O que a F1 não faz

- Coleta diária de insights (F2).
- Painel (F3).
- Consultor (F4).
- Resumo no WhatsApp (F5).
- Escrita na conta de anúncios.
