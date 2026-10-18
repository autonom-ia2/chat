# Modelos de mensagem do WhatsApp — PRD do épico

Estado: proposta para aprovação do Rodrigo (11/10/2026). Protótipo em tela real na branch
`feat/modelos-whatsapp-prototipo` (front com adaptador falso, atrás da flag `whatsapp_templates_journey`).

## 1. Problema

A tela "Modelos WhatsApp" só lista o que a Meta devolve: nome técnico (`customer_satisfaction_survey_6`),
número cru no lugar da caixa, jargão ("Chamada para ação") e nenhuma situação de aprovação. Para criar ou corrigir
um modelo o cliente precisa ir ao WhatsApp Manager da Meta. Além disso, a auditoria achou falhas que já existem
hoje em produção:

- a campanha não confere o modelo no disparo: modelo pausado, alterado, apagado ou com tipo trocado faz a lista
  inteira falhar ("falhou" com erro da Meta em inglês) e a campanha termina "concluída";
- campanha, conversa, follow-up do CRM e avisos do agendamento aceitam formatos que não sabem enviar
  (copiar código, carrossel, oferta por tempo limitado) e falham no envio;
- o follow-up de IA inventa os valores das variáveis (valor, data e responsável do negócio nunca entram);
- os modelos usados pelo próprio sistema (agendamento, Anúncios, satisfação) podem ser apagados sem aviso.

## 2. Objetivo

Ciclo completo de modelos dentro do Chat2You, para leigo ("QI 70"), sem perder dinheiro nem campanha:

1. criar, enviar para análise, acompanhar, corrigir, alterar, duplicar e apagar;
2. todos os formatos que a API da Meta permite (exceto o construtor de Flows, que é épico próprio);
3. tipo e custo sempre visíveis, com ajuda para manter no tipo barato quando a mensagem é de serviço de verdade;
4. todo modelo só é oferecido onde dá para preencher todos os campos (catálogo único de campos);
5. nenhuma campanha queima a lista por causa do modelo.

## 3. Fatos que sustentam o desenho

| Fato | Fonte |
|---|---|
| Criar/editar/apagar/upload de mídia/status pela Graph API v26 | docs Meta (relatorio-meta-api.md) |
| Recurso de recusa e contestação de categoria só no WhatsApp Manager | docs Meta |
| Aprovado: até 10 edições/30 dias, 1 a cada 24 h; volta para análise | docs Meta |
| Nome apagado fica preso 30 dias | docs Meta |
| Só caixas `whatsapp_cloud` com WABA criam modelo | código (`channel/whatsapp.rb`) |
| Permissão `whatsapp_business_management` ativa (Advanced) | painel Meta + sync que funciona |
| Prod hub2you: 14 caixas Cloud, 1 WABA por conta, nenhuma WABA dividida; token da Autonom.ia compartilhado por 5 caixas de 4 contas (WABAs diferentes) | consulta read-only 11/10/2026 |
| Prod autonomia: nenhuma caixa Cloud | consulta read-only 11/10/2026 |
| Status hoje só pelo sync (~5 min); webhook `message_template_status_update` é descartado | código (`whatsapp_events_job.rb`) |
| Criador de modelo já existe (avisos do agendamento, #1280) | código (`Crm::BookingV2::NoticeTemplates::Creator`; retirado no #1612, os avisos usam `Whatsapp::Templates::Garantir`) |

### Preço por mensagem entregue no Brasil (tabela oficial em vigor desde 01/10/2026)

| Tipo | R$ | US$ |
|---|---|---|
| Divulgação (marketing) | 0,3217 | 0,0625 |
| Serviço (utility) | 0,0350 | 0,0068 |
| Código de verificação | 0,0350 | 0,0068 |
| Resposta ao cliente (service) | grátis até 1.000/mês por número; depois 0,0350 | 0,0068 |

Divulgação = 9,19 × serviço. Desde 01/10/2026 utility dentro da janela de 24 h voltou a ser cobrada. Punição da
Meta para quem manda divulgação como serviço: advertência → reclassificação instantânea → limite de volume
(≥ 7 dias) → todos os utility da conta viram marketing (7/30 dias) → portfólio inteiro (30 dias).
Preços ficam em configuração (nunca no código); próxima janela de reajuste possível: 01/01/2027.

## 4. Regras de produto

- Linguagem leiga, uma ação principal por tela, sem `<select>` nativo, sem "Jev"/"IA" na tela. Exceção pedida pelo Rodrigo (12/10/2026, #1333): os rótulos "Criar com IA" e "Melhorar com IA" e o título da gaveta; a conferência segue sem citar tecnologia.
- Tipo traduzido: "Aviso sobre algo que o cliente já fez ou combinou" (serviço), "Divulgar oferta ou novidade"
  (divulgação), "Código de acesso" (verificação). Custo por envio sempre ao lado.
- "Agressivo" = maximizar serviço legítimo. Nunca disfarçar divulgação.
- Quem cria/altera/apaga: administrador e função personalizada com `campaign_manage`; ver: `campaign_view`.
- A WABA usada é sempre a gravada na caixa, nunca uma vinda da tela ou do request (isolamento entre clientes).
- Modelos da plataforma (`agendamento_*`, `chat2you_resumo_anuncios`, `chat2you_alerta_anuncio`, satisfação):
  selo "Usado pelo sistema"; não apaga nem altera; duplicar pode.
- Sem promessa que o sistema não cumpre: fora "Responda SAIR" (opt-out por resposta não é gravado) e
  "Avisamos quando…" (sem webhook ainda).
- "Nome da empresa" = nome da conta no Chat2You (texto fixo, editável).
- Construção aditiva: arquivos do fork, `prepend_mod_with`, tabelas próprias; nenhuma coluna em tabela do Chatwoot;
  flag para voltar à tela antiga.

## 5. Conferência inteligente (Jev + gerador), reaproveitando o que existe

Nada novo de infraestrutura: o Jev entra como mais um uso, no padrão já existente.

| Peça existente | Reuso |
|---|---|
| `CampaignImports::JevConfig` (`CAMPAIGN_JOURNEY_JEV_ENABLED`) | liga/desliga dos modelos |
| `Autonomia::Decisores::LIMITE_MENSAL` + `Crm::AiUsageEvent` | cota mensal compartilhada, feature própria `jev_modelos` |
| `Crm::Subjects::Identifier` / `Decisores::Duvida` | reserva: Jev → gerador quando a certeza é baixa |
| `CampaignImports::VariableSuggester` | ligar campos do modelo a colunas/dados |
| `Crm::Ai::ResponsesClient` (`gpt-6-luna`) | reescrever como serviço ("Escrever para mim") |

Usos:

1. **Prever o tipo** enquanto a pessoa escreve (serviço / divulgação / verificação / incerto).
2. **Marcar o trecho que encarece**, frase a frase (frases separadas com método de string, sem regex).
3. **Risco de recusa**: regra estrutural no código bloqueia (campo no começo/fim, numeração, limites, duplicidade);
   julgamento de linguagem só avisa, com "Enviar mesmo assim". A resposta do modelo nunca libera o que a regra bloqueou.
4. **Motivo da recusa**: dicionário fixo para o motivo da Meta; o Jev aponta a frase.
5. **Ligar campos** a colunas do público e a dados de CRM/agendamento.
6. **Reescrever como serviço** com `gpt-6-luna`, com saída "não dá para ser serviço"; o resultado volta ao Jev.

Cadeia de reserva: Jev desligado/sem cota/timeout/incerto → gerador com saída estruturada → só regras estruturais →
"Não conseguimos conferir agora" e envio liberado com aviso. Nunca falha em silêncio. Dentro da requisição web:
prazo curto, sem nova tentativa; reescrita e revalidação em duas requisições (teto de 15 s do rack-timeout).

Papéis: Jev classifica (~US$ 0,00004/chamada, ~170 ms, certeza medida); `gpt-6-luna` escreve, explica o trecho
caro e traduz a recusa (~US$ 0,0004, certeza só declarada — sozinho nunca dá selo verde); `gpt-6.1-sol` só na 2ª
tentativa de reescrita, em job (~US$ 0,011). Custo por modelo criado: ~US$ 0,001 (comum) a ~US$ 0,016 (pior caso).

Assimetria (como ser "agressivo"): errar para serviço pode encarecer a conta inteira por até 30 dias; errar para
divulgação custa uma reescrita. Logo: agressivo para **reescrever** como serviço, conservador para **rotular** como
serviço. Selo verde só com Jev ≥ 0,90 e sinal de promoção < 0,2, ou Jev ≥ 0,80 com o luna concordando. Divulgação
com certeza não pode ser pedida como serviço (reescrever ou enviar como divulgação). Contador de reincidência por
conta: cada reclassificação da Meta endurece a regra; com 2 ou mais, só modelos prontos vão como serviço.

Calibração: bateria com modelos reais já julgados pela Meta antes de mostrar selo verde. Orçamento aprovado pelo
Rodrigo: até US$ 2 (11/10/2026).

## 6. Catálogo único de campos

Base: `CampaignJourney::VariableBindings` (já liga variável → campo do contato, coluna da planilha ou texto fixo).
Chaves por dono do dado, com tipo e formatação pt-BR única:

`cliente.*`, `empresa_cliente.*`, `negocio.*`, `retorno.*`, `horario.*`, `minha_empresa.*`, `atendente.*`,
`publico.<coluna>`, `fixo`. Tipos: texto, data, hora, moeda, link.

- Na criação, cada campo declara de onde vem. Criando a partir de um contexto (agendamento, CRM), só aparecem os
  campos que ele tem.
- No uso, o sistema confere se o contexto preenche tudo; se faltar, avisa antes do envio e oferece ligar a uma
  coluna ou usar valor fixo.
- Resolvedores somam-se: Contato, Conta e Atendente na base; Público, Negócio, Retorno, Horário e Conversa por cima.

Conflitos a resolver no épico: "company" é a empresa do contato; primeiro nome calculado de 3 jeitos; datas em 3
fusos; valor do negócio em centavos sem formatação; datas XLSX cruas; três sintaxes `{{ }}` (e o bug #1021).

## 7. Ligação com Campanhas (jornada integrada)

A. Campanha sem modelo → "Criar modelo" → rascunho salvo → criar → "Voltar para a campanha" com o modelo em
   análise escolhido; "Agendar" liberado, "Enviar agora" só após aprovar.
B. Modelo pronto → "Usar em uma campanha" → campanha aberta com caixa, modelo e campos já ligados.
C. Campos ligados automaticamente pelo catálogo; mídia do modelo pré-preenchida; cupom/oferta/carrossel pedem o
   que a Meta exige no envio.
D. Revisão com tipo e custo total ("Esta campanha custa cerca de R$ X; como aviso de serviço, R$ Y").
E. Proteções: alterar mostra o que é afetado; apagar bloqueado com uso agendado; no disparo, modelo divergente →
   campanha pausada pelo modelo com o motivo, sem queimar a lista.

### Acesso por funil (alinhado com o Multifunil, #1140/#1311, 11/10/2026)

- "Onde está em uso" lista só o que a pessoa vê (`policy_scope(::Crm::Card)` / `CardScope`); sem contagem de itens em
  funis escondidos (decisão do Rodrigo no #1311). O administrador vê tudo.
- Apagar/alterar modelo com uso em funil que a pessoa não acessa: bloqueado com "Este modelo está em uso onde você não
  tem acesso. Peça a um administrador." (sem número, sem nome).
- Catálogo de campos só lê o card; dono/responsável segue `CardGuard#owner_allowed?`.
- PRs que tocam o CRM entram depois dos PRs D, (b) e (a) do Multifunil; branch nasce da main depois deles (sem rebase).
  Validação local inclui `spec/services/crm/access/`.

### Agendamento (alinhado com a sessão "Página de agendamento CRM", 11/10/2026, main 6779968b1c)

- Cliente Graph novo em arquivo próprio; `Crm::BookingV2::NoticeTemplates::{Creator,Requests,Suggester}` e
  `NoticeTemplatesJob` intocados (migrar o Creator é PR deles, depois). Atualização: o #1612 retirou o Creator e o
  Requests; o `NoticeTemplatesJob` ficou como casca.
- Sync com `fields=`: a Graph devolve só o pedido. Pedir no mínimo `id,name,language,status,category,components,
  rejected_reason` (+ quality/categoria corrigida). Spec de regressão com item sem `category`/`components`.
- Nomes protegidos: `Catalog.kinds.map { |kind| Catalog.name_for(kind) }`, idioma `Catalog::LANGUAGE` (pode acrescentar
  `Catalog.names`, uma linha, revisado por eles).
- Regra de formato: no mesmo PR da regra genérica, `Crm::BookingV2::Notices::Route.fillable_template?` passa a chamá-la
  além da checagem própria de {{1}}..{{3}} (lista de arquivos vai para eles revisarem).
- Ordem dos campos dos avisos: {{1}} `cliente.primeiro_nome` (`InviteText.first_name`), {{2}} `horario.data_hora`
  (`Notices::Text.when_text`), {{3}} `horario.link_gestao` (`invite.url`).
- "Onde está em uso": página `enabled = true`, `page_version = 2`, `notice_inbox_id` = caixa; tipo ativo se está em
  `notice_kinds` (de `notice_preset`); modelo do tipo em `notice_templates[tipo]` = `{name, language}`.

## 8. Diferenciais

- Custo antes de enviar e economia possível.
- Conferência antes da Meta (menos recusa e menos troca de tipo).
- Saúde do modelo: lidas, respostas, custo por resposta.
- Proteção da conta: aviso de advertência/limite da Meta.
- Contador da franquia de 1.000 respostas grátis do mês por número.

## 9. Fora do escopo

- Construtor de Flows (épico próprio); aqui só o botão que aponta para um Flow existente.
- Recurso de recusa e contestação de categoria (só no WhatsApp Manager; a tela leva até lá).
- 360dialog e Twilio (só leitura).

## 10. Issues propostas (ordem)

1. Conferir o modelo no disparo e pausar a campanha com o motivo (corrige bug atual).
2. Regra única de "formato que dá para enviar" (Ruby + JS) aplicada a campanha, conversa, CRM e agendamento.
3. Cliente Meta de modelos (criar, editar, apagar, upload de mídia, `rejected_reason`), extraído do Creator do #1280,
   com teste de isolamento por WABA.
4. Tabela de perfil do modelo (nome amigável, campos do catálogo, mídia, selo "do sistema").
5. Catálogo único de campos + resolvedores.
6. Tela de Modelos (o protótipo) ligada ao backend real.
7. Conferência inteligente (Jev + gerador) + calibração (≤ US$ 2).
8. "Onde está em uso" real.
9. Ida e volta Campanha ↔ Modelo.
10. Envio dos formatos novos na campanha (cupom, oferta, carrossel, Flow com token, catálogo, verificação).
11. Custo e franquia na tela (tabela de preço configurável).
12. Webhook de status/categoria/qualidade por WABA (fase 2).
13. Saúde do modelo (fase 2).
14. Follow-up de IA usando dados reais do catálogo, atrás de chave (decisão do Rodrigo).

## 11. Decisões pendentes do Rodrigo

1. Telefone e endereço da empresa: campo novo na conta ou reaproveitar página de agendamento/caixa.
2. Tipo das colunas da planilha (data, valor, texto): quem diz é a pessoa ou a leitura inteligente.
3. Follow-up de IA com dados reais: entra no épico atrás de chave?
4. Divulgação para quem falou nas últimas 24 h: modelo (cobrado) ou texto livre (cobrado como resposta ao cliente
   após a franquia, e pesa na qualidade do número).
5. Quem paga o gerador (`gpt-6-luna`/`gpt-6.1-sol`) nos modelos: sempre a nossa chave, ou a chave da conta quando
   ela tem uma (padrão atual do CRM). Recomendação: a nossa, com teto de 500 chamadas/conta/mês.
