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
