# #1336 — Follow-up de IA com dados reais do card nos modelos

Épico #1320 (Modelos WhatsApp, item 14 do PRD). Issue de liga: #1522.

## Decisões

- **Ponto de extensão** (sessão Followup IA, 14/10): `Crm::FollowUps::TemplateCandidates` ganha `card:` opcional e é o
  único lugar da seleção, para o `AutoFollowupRunner` e o `CallbackRunner`. Sem `card:` ou com a flag desligada, nada
  muda. O prompt do compositor não muda (mexer nele pede eval pago): a IA recebe o body já escrito com o dado real e só
  as posições que sobram. O valor real (`filled`) não vai para a IA e vence o que ela devolver, nos dois runners, só em
  modelo nativo.
- **De onde vem o dado:** o perfil do modelo (`WhatsappTemplateProfile#fields`) liga a posição a uma chave do catálogo
  (`TemplateFields`); o valor sai de `TemplateFields::Resolver.for_card`. Chave nova `negocio.prazo` =
  `expected_close_at`, data no fuso da conta. Valor pelos centavos (`value_cents` + `currency`); 0 é "sem valor".
- **Card sem o dado** (Rodrigo, 14/10: "outro modelo; sem nenhum, texto"): o modelo sai da lista; a IA escolhe outro;
  sem nenhum, Híbrido quando a caixa tem, senão `no_template`, como hoje. Regra só em
  `TemplateRealValues#without_real_value`.
- **Flag:** `followup_template_real_values`, bit 21 da `feature_flags_ext_1` (reservado pela Orquestração), `enabled:
  false`. O bit 22 é da `crm_lembretes_v2`.
- **Perfil repetido entre caixas irmãs da mesma WABA:** vale o da própria caixa; entre os outros, o mais antigo.

## Fora daqui (registrado para o Rodrigo)

- A tela de Modelos ainda não oferece ligar uma variável a `negocio.*`: os rótulos da tela (`valor`, `data`) não são
  chaves do catálogo e seguem com a IA. Até a tela ligar, só modelos com perfil gravado com chave do catálogo usam o
  dado real.
- `atendente.nome` não é preenchido no follow-up (não há "quem atende" num envio automático): modelo com esse campo
  ligado sai da lista.
- `metadata.payment_promise_at` ("prometeu pagar em") entra quando o #1515 estiver na main.

## Validação (14/10/2026, banco `chat2you_test_s`)

- rspec da área (follow_ups, composer, template_fields, campaign_journey, variable_suggester, booking_v2/notices,
  ai/redacao, account, whatsapp_template_profile, crm/access, jobs/crm): 1115 exemplos, 0 falhas, 5 pendentes (já
  existentes).
- Mutações conferidas: inverter o merge (IA vence), manter o modelo sem dado, ignorar a caixa própria e trocar a
  substituição por `gsub` em sequência; cada uma reprova os specs.
- rubocop nos arquivos tocados: sem ofensas. `autonomia:guia:formatos:check`, `pnpm guia:check`, `pnpm central:check`,
  `pnpm i18n:fork:check`: em dia.
