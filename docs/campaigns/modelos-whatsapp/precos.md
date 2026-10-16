# Preço por envio do WhatsApp oficial (#1332)

Contrato do #1322: **custo por envio do WhatsApp = a chave `WHATSAPP_MESSAGE_PRICES`**, lida só por
`Whatsapp::Pricing`. Modelos, Campanhas, Anúncios e Gestão IA usam o mesmo leitor; ninguém escreve preço no código.

## Onde mora

- Valor de fábrica: `config/installation_config.yml` (entra no banco pelo `ConfigLoader` no deploy).
- Valor em uso: `InstallationConfig` `WHATSAPP_MESSAGE_PRICES` (Super Admin > Configurações), em JSON. Se estiver
  vazio, vale o de fábrica; JSON quebrado vira "sem preço" (com log de erro), nunca um número inventado.

```json
{
  "BR": {
    "currency": "BRL",
    "effective_from": "2026-10-01",
    "prices": { "marketing": "0.3217", "utility": "0.0350", "authentication": "0.0350", "service": "0.0350" },
    "free_tier": { "service": { "messages": 1000, "period": "month", "per": "phone_number" } }
  }
}
```

Valores oficiais da Meta para o Brasil em vigor desde 01/10/2026 (PRD §3). Próxima janela de reajuste possível da
Meta: 01/01/2027. Ao mudar, troque os valores **e** `effective_from`.

## Leitor

```ruby
Whatsapp::Pricing.per_message('MARKETING')           # => Price(category: 'marketing', amount: 0.3217, currency: 'BRL', country: 'BR', effective_from: '2026-10-01')
Whatsapp::Pricing.per_message('utility', country: 'BR')
Whatsapp::Pricing.free_tier('service')                # => { messages: 1000, period: 'month', per: 'phone_number' }
```

Categoria (`marketing`, `utility`, `authentication`, `service`, em qualquer caixa) ou país sem preço devolvem `nil`:
quem chama não mostra o custo.

## Na tela

`GET /api/v1/accounts/:account_id/whatsapp_message_prices` (quem vê modelos ou campanhas): a tabela do Brasil e, por
número, quantas respostas livres (sem modelo) saíram no mês (`Whatsapp::ServiceMessageCount`), para a franquia. A
revisão da campanha mostra o custo por envio e o total; a lista de Modelos mostra a franquia do mês.

## Franquia de respostas: regra oficial (#1592)

Fonte: [Pricing on the WhatsApp Business Platform](https://developers.facebook.com/docs/whatsapp/pricing/), página
atualizada em 30/09/2026 (lida em 15/10/2026), e o [changelog da plataforma](https://developers.facebook.com/docs/whatsapp/business-platform/changelog/):

- **11/09/2026** (Pricing): tabelas de chamadas e recomendações de preço máximo de marketing a partir de 01/10. Não
  muda a franquia.
- **29/09/2026** (Pricing): reação é a única mensagem de serviço que segue sem cobrança para todos, e reação **não
  conta** nas 1.000 grátis do mês por número. Também: serviço segue grátis além da franquia só para governo e ONG
  elegíveis, até 31/12/2027.
- **30/09/2026** (Pricing): a página foi reorganizada em torno das regras e preços de 01/10/2026; a versão anterior
  ficou como "Pricing (deprecated)".

Regras que o produto segue:

| Regra oficial | No Chat2You |
| --- | --- |
| 1.000 mensagens de serviço **entregues** grátis por mês, **por número comercial**; da 1.001ª em diante, preço de `service` | `free_tier.service` acima; contagem por caixa em `Whatsapp::ServiceMessageCount` |
| O mês vira à meia-noite no **fuso da conta de mensagens (WABA)** ("This reset happens at 12am by Messaging account timezone") | Fuso lido na Graph (`timezone_id` da WABA) por `Whatsapp::WabaTimezone`, guardado 30 dias no cache; sem ele, fuso da conta do Chat2You, com log |
| Reação não conta na franquia | Fica fora: o Chat2You não manda reação e o eco de reação do app (coexistência) é descartado na entrada |
| Utility dentro da janela de 24 h voltou a ser cobrada (era grátis desde 01/07/2025) | Modelo utility custa o preço de `utility`; nenhuma tela trata utility na janela como grátis |
| Conta de mensagens **sem forma de pagamento**: a Meta entrega as de serviço dentro da franquia e **não entrega** depois das 1.000 | Ainda não avisado na tela: Issue #1615 |

O número na tela é **estimativa**: só vê o que saiu pelo Chat2You (n8n direto na Meta ou o app no mesmo número não
entram) e conta "não falhou", não "entregue". O número exato virá do `pricing.type` do webhook de status (#1614).

`timezone_id` é um número da Meta. A tabela número → nome é a oficial
([Timezone IDs](https://developers.facebook.com/documentation/business-messaging/whatsapp/timezone-ids/), atualizada em
17/06/2026), copiada sem edição em `config/whatsapp_meta_timezone_ids.yml`. O nome (`TZ_AMERICA_SAO_PAULO`) vira o fuso
IANA (`America/Sao_Paulo`) pela base IANA do próprio TZInfo, sem tabela escrita à mão; com o `tzinfo-data` atual, só
`TZ_AMERICA_COYHAIQUE` (fuso criado em 2025) fica sem par e cai no fuso da conta.
