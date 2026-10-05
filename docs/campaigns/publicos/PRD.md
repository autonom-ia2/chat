# PRD — Campanhas: jornada única (E-mail, WhatsApp, SMS, Chat ao vivo) e Público

Data: 05/10/2026 · Dono: Rodrigo · Status: proposta para aprovação · Versão 3 (05/10)

Evidência de origem: [auditoria de 05/10/2026](../../audit/2026-10-05-auditoria-base-de-campanha.md). Épica: [#990](https://github.com/autonom-ia2/chat/issues/990) · Protótipo navegável das jornadas (v2: público primeiro, selos de canal, marca no CRM): https://claude.ai/artifact/Ji9iE3AaH6MG3h6bDP15KW (telas avulsas: https://claude.ai/artifact/DEgd2WS2gp4XuvqTbh6vwP)

## 1. Problema

Hoje cada canal de campanha é um produto à parte:

- **WhatsApp Oficial**: formulário flutuante antigo; o público é uma etiqueta que o usuário procura numa lista com todas as etiquetas da conta.
- **WhatsApp API**: outro formulário flutuante, outras regras, mesma escolha por etiqueta.
- **E-mail**: tela nova (#800), mas a criação ainda é um formulário lateral pobre; a lista de destinatários fica presa à campanha e não vira contato.
- **Base de campanha** (planilha de nome + celular) mora no menu ⋮ de **Contatos**, longe da campanha.

O único uso real da base em produção (conta 6, 13 importações, 11 disparos, 771 contatos, jul–set/2026) mostra:

1. **Base e campanha são 1:1.** Cada disparo teve sua própria importação. O usuário importa em Contatos, decora o nome da etiqueta e depois a procura.
2. **Lotes nunca foram usados** (`batch_count = 1` nas 13).
3. **Não há prova de entrega.** As 11 campanhas aparecem "concluídas", mas nada registra se cada mensagem saiu, chegou ou falhou.
4. **Uma linha ruim derruba o arquivo** (1 celular inválido em 100).
5. **Cabeçalho rígido.** Só nomes de coluna de uma lista fixa.
6. **Respostas em contato duplicado** quando o WhatsApp devolve o número sem o 9 (6 de 771; correção de código já em produção).
7. **Erro no cálculo de lotes** (lote vazio ou falha genérica).
8. **Empresa se perde.** A planilha costuma trazer a corretora, clínica ou construtora do contato; hoje essa coluna é ignorada.

## 2. Objetivo

Uma lista e uma jornada para os três canais. Quem cria campanha escolhe o canal, monta a mensagem, sobe a planilha **dentro da campanha** (contatos e empresas entram na base), revisa e agenda. Depois acompanha o resultado por pessoa. Sem conhecer etiqueta, sem formulário flutuante, sem lote.

### Métricas de sucesso

| Métrica | Hoje | Meta |
|---|---|---|
| Lugares para criar campanha | 3 telas, 3 formulários diferentes | 1 jornada de 3 passos |
| Telas da planilha ao agendamento (WhatsApp) | 2 áreas + etiqueta procurada | 1 fluxo |
| Arquivos recusados por cabeçalho | 7 de 14 no e-mail antes do Jev; sem medição na base | 0 com coluna reconhecível por pessoa |
| Arquivos recusados por poucas linhas ruins | 1 de 13 | 0 (importa as válidas) |
| Destinatários com situação conhecida após o envio | 0% no WhatsApp | 100% nos três canais |
| Contatos importados com empresa ligada, quando a planilha tem a coluna | 0% | ≥ 95% das linhas preenchidas |
| Respostas de campanha em contato duplicado | 6 de 771 | 0 |

## 3. Fora do escopo

- Segmentação dinâmica por atributo. Público é lista estática (planilha ou etiqueta).
- **Envio em etapas / lotes** (decisão de 05/10). O backend de lotes continua, invisível, sempre com 1 lote.
- Custo por conversa da Meta.
- Juntar os 6 contatos duplicados existentes (escrita em produção, decisão separada).
- Mudar o editor de e-mail (`EmailBuilderPage`) por dentro. A jornada só abre o editor que já existe.

## 4. Usuários e permissões

- **Cria e envia:** administrador ou função com `campaign_manage`.
- **Só consulta:** `campaign_view` vê campanhas, Públicos e resultados; não importa, não remove, não agenda.
- Empresas: criar empresa pela importação segue a mesma permissão de importar; a flag de conta `companies` precisa estar ligada (sem ela, a linha "Empresa" não aparece e nenhuma empresa é criada).
- Nenhuma chave de permissão nova.

## 5. Decisões de produto

| # | Decisão | Por quê |
|---|---|---|
| D1 | **Públicos** é subpágina de Campanhas, compartilhada pelos três canais. Sai do menu ⋮ de Contatos ("Base Campanha" e "Histórico de bases"). | Base gera contatos, empresas e etiquetas que servem a qualquer canal. Padrão de Mailchimp (Audience), Klaviyo (Lists & segments), HubSpot (Lists). |
| D2 | **O público vem primeiro** na campanha (Passo 1), e a campanha só escolhe **públicos salvos**. A planilha entra sempre por Públicos; quem não tem público é levado até lá com texto simples e volta para a campanha com ele escolhido. | "Para quem" antes de "por onde": o público define os canais possíveis. Uma única tela de importação (menos código e menos caminhos). Decisão do Rodrigo em 05/10. |
| D3 | **Sem lotes nem etapas na interface.** A campanha envia tudo no horário escolhido. | Lote nunca usado; simplicidade. |
| D4 | **Importa as linhas válidas**; inválidas listadas com motivo e baixáveis. | Recusar 100 por 1 é atrito. |
| D5 | **O sistema acha as colunas sozinho** (nome, celular ou e-mail, empresa, variáveis da mensagem) usando o Jev por baixo. **A interface nunca cita o Jev nem IA.** O modelo recebe cabeçalhos, formato mascarado e a lista do que a campanha precisa; nunca nome, número ou e-mail. | Contrato de privacidade do #764; o usuário quer o resultado. |
| D6 | Nome técnico da etiqueta some da interface; o usuário vê o **nome do público**. | Ninguém decora `campanha_7_envio_100_annt_nova_11`. |
| D7 | Criação em **página com passos**, no layout do #800. Nenhum formulário flutuante ou lateral (inclusive no e-mail). | Padrão visual atual; o formulário lateral do e-mail é pobre. |
| D8 | **A planilha guarda todas as colunas extras** no público. Na mensagem, cada variável é ligada a um dado do contato ou a uma coluna do público, com sugestão automática pelo nome. | Substitui a versão anterior (modelo antes da planilha): a ajuda para achar a coluna continua, só muda de lugar. |
| D9 | **Jornada única:** "Todas as campanhas" (lista com filtro por canal) + "Nova campanha" em 3 passos: **Público → Mensagem → Revisar**. Só o conteúdo do passo Mensagem muda por canal. | Um jeito de fazer, três canais. |
| D10 | **Empresas:** se a planilha tiver coluna de empresa (corretora, clínica, construtora…), o sistema cria a empresa que não existe, reaproveita a que existe e liga ao contato. Contato que já tem **outra** empresa mantém a dele (contado como "mantida"). Pode ser desligado na criação do público. | Pedido do Rodrigo; a empresa é o cliente real no B2B de seguros. Não sobrescrever evita estragar cadastro bom. |
| D11 | **E-mail também cria contatos** ao subir a planilha (hoje a lista fica só na campanha). Descadastro e e-mail que voltou continuam valendo e o contato não recebe. | Uma base só: o contato do e-mail é o mesmo do WhatsApp, com empresa e histórico. **Confirmado pelo Rodrigo em 05/10.** |
| D12 | **Construção aditiva** (seção 8.0): mínimo de mudança em arquivos do Chatwoot oficial. | Atualizar o Chatwoot sem conflito. Pedido do Rodrigo em 05/10. |
| D13 | **Selos de canal automáticos** no público (E-mail, WhatsApp, ou os dois), pela presença de e-mail ou celular válido, com a contagem; dá para desligar um canal. Na campanha, só os canais do público ficam disponíveis. | Ninguém precisa decidir o que a planilha já diz. Decisão do Rodrigo em 05/10. |
| D14 | **Marca da campanha no CRM na resposta**, pelo mesmo mecanismo de Links e QR codes (`Ctwa::CampaignBuilder`): quem responde ganha "Campanha: <nome>" na conversa; o card mostra todas as marcas (+N). Nunca no envio. | Card com várias campanhas, sem poluir o CRM com quem não engajou nem esconder a origem real. Decisão do Rodrigo em 05/10. |
| D15 | **Público sem etiqueta.** O público é uma lista de contatos; a campanha manda para essa lista. Novas importações não criam etiquetas `campanha_*`/`_lote_N`; as antigas ficam como estão. A identificação de quem veio da campanha é a marca de campanha (D14). | Etiqueta oculta só existia para o envio achar os contatos; poluía a conta. Decisão do Rodrigo em 05/10. |
| D16 | **Só aparecem canais conectados**, na escolha do canal, no filtro da lista e no menu: E-mail, WhatsApp Oficial, WhatsApp API, **SMS** e **Chat ao vivo**. SMS entra na jornada (com registro por destinatário, conversa e marca no CRM). Chat ao vivo não é envio para lista: tem fluxo próprio (Quando aparece → Mensagem → Ativar), atalho no passo Público e selo "Sempre ativa" na lista. | Menos opções mortas na tela. Chat ao vivo é regra no site, não lista. Decisão do Rodrigo em 05/10. |
| D17 | **Menu:** grupo **Campanhas** com os itens **Público** (primeiro), **Campanha**, Modelos, Links e QR codes, Gestão de campanhas. Saem E-mails, WhatsApp Oficial, WhatsApp API, Chat ao vivo e SMS (rotas antigas abrem "Campanha" filtrada). | Pedido do Rodrigo em 05/10. |
| D18 | **Resultado × Gestão.** O detalhe de uma campanha fica no **Resultado** dentro dela, com todos os motores de hoje (Gestão de e-mail e página de resultado do WhatsApp). **Gestão de campanhas** vira a visão geral multicanal: período, canais, comparativo entre campanhas, respostas e negócios no CRM. | Cada tela responde uma pergunta; nada da Gestão de hoje se perde. Recomendação aceita pelo Rodrigo em 05/10. |
| D19 | **E-mail: nada se perde** (lista em §6.9). Além de manter tudo, dois defeitos de hoje entram no escopo: **"Respostas vão para a caixa X"** passa a funcionar (hoje o campo é gravado e ignorado) e **"Enviar teste"** passa a funcionar no envio direto pela caixa (hoje só com domínio). | Pedido do Rodrigo em 05/10. |
| D20 | **Marcas de campanha na conversa.** O painel do contato na conversa mostra todas as marcas de origem e de campanha (hoje mostra só a primeira), igual ao card do CRM; o topo da conversa mostra a marca da campanha que a abriu. | Pedido do Rodrigo em 05/10. |
| D21 | **Jev em todas as importações** de planilha: Públicos e a importação geral de Contatos (tela do fork no lugar da do Chatwoot), ambas criando e ligando empresas. Reaproveita `TypesafeAi::Client`, modelo fixo `jev-1.13.0`, só cabeçalhos e formato mascarado. Flag própria, sem reutilizar `TYPESAFE_JEV_ENABLED` (que desliga a importação de e-mail inteira) sem decisão do Rodrigo. | Mesmo motor e mesma regra de privacidade em todo lugar. Pedido do Rodrigo em 05/10. |

## 6. Jornada

### 6.1 Campanha (lista)

`Campanhas › Campanha` (nova entrada principal; antes "Todas as campanhas").

- Faixa de resumo: próximo envio (canal, data, pessoas, "Revisar envio"), em preparação, enviadas em 30 dias, responderam ou clicaram.
- Filtro por canal: Todos, E-mail, WhatsApp Oficial, WhatsApp API. Filtro por situação e busca.
- Linha: ícone do canal, nome, canal + remetente/modelo, público e pessoas, quando, barra de resultado, situação.
- Ações: "Públicos" e **"+ Nova campanha"** (uma ação principal).
- Menu: grupo **Campanhas** com **Público**, **Campanha**, Modelos, Links e QR codes, Gestão de campanhas (D17). As rotas antigas de E-mails, WhatsApp Oficial, WhatsApp API, SMS e Chat ao vivo abrem "Campanha" filtrada pelo canal.
- Filtro por canal mostra só os canais conectados (D16). Chat ao vivo aparece com o selo "Sempre ativa".

### 6.2 Nova campanha — Passo 1, Público

A primeira pergunta é "quem vai receber". **Só públicos salvos** aparecem aqui; a planilha é sempre subida em Públicos (6.6).

- Lista de públicos com busca. Cada um mostra nome, **selos de canal** com a contagem de quem pode receber por eles (`E-mail · 1.240`, `WhatsApp · 980`), empresas e data.
- **Sem nenhum público:** tela simples, uma frase e um botão — "Você ainda não tem uma lista de pessoas. Vamos criar a primeira? É só subir a planilha. Quando terminar, a gente volta para esta campanha." → **Criar público**. O rascunho da campanha fica salvo.
- **Tem públicos, mas não o que quer:** abaixo da lista, "Não achou quem procura? **Criar um novo**".
- Criar público a partir daqui abre Públicos com o aviso "Você está criando um público para a campanha X. Ao salvar, voltamos para ela." Ao salvar, volta para a campanha **com o público novo já escolhido**.
- Texto escrito para qualquer pessoa entender na primeira leitura (meta: leitor com QI a partir de 70): frases curtas, uma ação principal por tela, sem termo técnico.

### 6.3 Passo 2, Mensagem

No topo, o público escolhido ("Para: Corretoras parceiras · E-mail 1.240 · WhatsApp 980 · Trocar público").

**"Por onde a mensagem vai"** — cartões dos canais **conectados**: E-mail, WhatsApp Oficial, WhatsApp API, SMS (D16). **Só ficam disponíveis os canais que o público tem**; o indisponível mostra o motivo ("Este público não tem e-mail").

Campo comum: **nome da campanha**, com o aviso "Quem responder ganha a marca *Campanha: <nome>* no card do CRM" (6.7). Ao lado, prévia "Como o cliente vê" com o primeiro contato do público.

- **WhatsApp Oficial:** caixa (só Cloud), modelo aprovado, e **"De onde vem cada parte da mensagem"**: cada variável do modelo ligada a um dado do contato, a uma **coluna do público** (as colunas extras da planilha ficam guardadas) ou a texto fixo. O sistema sugere a coluna pelo nome (selo "Sugerido"), sem citar IA.
- **SMS:** caixa de SMS, texto curto com fichas do público e contador de caracteres/partes, prévia como SMS.
- **WhatsApp API:** caixa marcada para campanha, mensagem livre com fichas do contato e do público (nome, primeiro nome, empresa e colunas extras), "Usar modelo salvo", anexo opcional, aviso do ritmo automático.
- **E-mail** — o passo tem cinco telas, na ordem:
  1. **Canal e nome** da campanha.
  2. **Como você quer começar?** (`WelcomeChooser` existente): Criar com IA (recomendado), Escolher um modelo, Começar do zero.
  3. **Criar com IA** (`AiComposerDialog` existente, em página): briefing, objetivo, tom, personalização com os campos do público (nome, primeiro nome, empresa, colunas extras) e recursos (logo, imagem, PDF, vídeo); tela de progresso. **Ou Biblioteca de modelos** (`EmailTemplatesPage` existente): Biblioteca e Meus modelos, filtro por objetivo, busca, prévia, "Usar este" e "Adaptar com IA".
  4. **Editor** (`EmailBuilderPage` existente, sem mudança interna): blocos, propriedades, computador/celular, personalização, envio de teste e ações de IA por bloco. O botão principal do e-mail pode levar ao WhatsApp com o código da campanha (6.7).
  5. **Detalhes do envio**: remetente (domínio verificado), caixa das respostas, assunto com sugestões, texto de prévia e prévia na caixa de entrada.

### 6.4 Passo 3, Revisar e agendar

- Blocos com "Alterar": público, canal e mensagem, conteúdo.
- Linha do CRM: "Quem responder ganha a marca *Campanha: <nome>* no card, junto com outras campanhas que já tiver."
- Quando: agora ou data e hora (fuso da conta).
- Lateral: vão receber (número grande) = no público com o canal − quem não recebe (recusou, descadastrou, e-mail que voltou). E-mail tem "Enviar teste para mim".
- Confirmação final com o número de pessoas.

### 6.5 Resultado (dentro de cada campanha)

Responde "como foi esta campanha". Reaproveita as peças que existem hoje (Gestão de campanhas de e-mail e página de resultado do WhatsApp); nenhum indicador ou ação some (D18).

- **E-mail:** Enviados, Entregues (confirmados pelo provedor ou só aceitos), Abertos (aproximado), Clicaram, **Responderam** (novo, marcados no CRM), Descadastros, Bounce permanente, Temporários, Reclamações, Desconhecidos; gráfico ao longo do tempo (hora/dia); cliques por link; tabela por pessoa com motivo, verificação prévia, tentativas, último evento e "Abrir conversa"; exportar CSV filtrado; Saúde (reavaliar, retomar, problemas) e status/problemas da importação; ações Pausar, Retomar, Cancelar, Duplicar, Salvar como modelo.
- **WhatsApp Oficial / API e SMS:** Público, Enviadas, Entregues, Lidas (Oficial), **Responderam**, Falharam (com código e motivo), Puladas; mensagem gerada por contato; faixa "processando"; tabela por pessoa com "Abrir conversa"; **exportar** (novo).
- Faixa "Quem respondeu já aparece no CRM com a marca *Campanha: <nome>*" + "Ver no CRM" (Kanban filtrado).

### 6.6 Públicos (onde a planilha entra)

- Resumo: públicos salvos, contatos em públicos, empresas ligadas, importados em 30 dias.
- Lista: nome, **selos de canal**, pessoas e empresas, campanhas que usaram, data.
- Painel lateral: selos, pessoas, empresas, **outras colunas guardadas**, campanhas que usaram, "Usar em nova campanha" (abre o Passo 1 com ele escolhido), "Ver contatos e empresas", "Excluir público" (apaga só a lista; contatos, empresas e resultados ficam — D15).
- **Novo público:** nome + planilha. Depois:
  1. **Colunas encontradas** (nome, celular, e-mail, empresa) com exemplo, contagem e "Trocar"; **Outras colunas** guardadas para a mensagem.
  2. **"Por onde dá para falar com essas pessoas"** — selos **marcados sozinhos** pelo que a planilha tem (tem e-mail válido → E-mail; tem celular válido → WhatsApp), cada um com a contagem; dá para **desligar** um canal. Canal sem dado aparece desligado com "sem dados".
  3. Pessoas no público, linhas com problema (ver e baixar), quem não recebe.
  4. **Empresas:** "Criar e ligar" (ligado por padrão) com novas, já existiam, contatos ligados, mantidas.
  5. **Salvar público** → contatos, empresas e ligações entram na base. Vindo de uma campanha, volta para ela.
- Contato existente reconhecido por celular (com ou sem o 9) ou e-mail; nunca duplicado.
- Importações antigas aparecem com o nome da campanha original.

### 6.7 Marca da campanha no CRM

Mesmo mecanismo de **Links e QR codes**: a campanha vira uma marca de origem na conversa, e o card do CRM mostra todas as marcas das conversas ligadas a ele ("Campanha: <nome>" + selo **+N**). Um card pode ter várias campanhas e links ao mesmo tempo.

- **Marca na resposta, nunca no envio** (decisão do Rodrigo, 05/10):
  - WhatsApp (Oficial e API): primeira mensagem recebida do destinatário na mesma caixa até 72h depois do envio.
  - E-mail: resposta que vira conversa na caixa das respostas; ou clique no botão do e-mail que leva ao WhatsApp com o código da campanha e a pessoa manda a mensagem (igual ao link rastreado).
  - Quem só abriu ou clicou, sem mandar mensagem, não ganha marca (aparece só no resultado da campanha).
- A gaveta do card lista a sequência: "Link: Feira 2026 → Campanha e-mail: Novidades de outubro → Campanha WhatsApp: Renovação auto — outubro".
- Os filtros de campanha do Kanban e das Conversas passam a incluir as campanhas.

### 6.8 Chat ao vivo (mensagem no site)

Não usa público (D16). Entra por um atalho discreto no passo Público ("Quer uma mensagem automática no seu site, sem lista?") e pela lista.

1. **Quando aparece:** site (caixa do chat do site), página (URL completa), tempo na página, só em horário de atendimento.
2. **Mensagem:** nome (vira a marca de campanha de quem conversar), quem fala (agente ou robô), texto, prévia no widget.
3. **Ativar:** fica na lista "Campanha" com o selo "Sempre ativa"; pausar/editar a qualquer momento. Mesmos campos e motor de hoje.

### 6.9 E-mail: o que não pode se perder

Tudo abaixo existe hoje e continua, com o mesmo motor (D19). Cada item tem termo de aceite no grupo L.

- **Travas de envio:** lista de prontidão (assunto, conteúdo, remetente pronto, destinatários, importação concluída, higiene, reputação do provedor); aviso de variável vazia/desconhecida; confirmação com número de destinatários; recarrega antes de confirmar; data futura no agendamento.
- **Reputação:** bloqueio por bounce ≥ 5% ou reclamação ≥ 0,1% no provedor (dado desconhecido bloqueia); política local de aviso/pausa; reavaliação ao retomar.
- **Higiene:** verificação de domínio/MX/endereço antes do envio (modos shadow/warning/enforce), correção de domínios conhecidos, quarentena.
- **Supressão e descadastro:** rodapé de descadastro travado no editor, `List-Unsubscribe` one-click, página de descadastro, classificação de bounce e reclamação, suprimidos e opt-out pulados na hora do envio.
- **Remetente:** domínio verificado (DKIM/SPF/DMARC, "Verificar agora", polling) **ou** envio direto pela caixa de e-mail (1 por vez a cada 1–2 min, horário comercial, teto diário por provedor, pausa automática após falhas); "De" do domínio verificado.
- **Respostas vão para a caixa X:** **passa a funcionar** — o envio usa a caixa escolhida como reply-to e a resposta vira conversa nela (hoje `reply_to_inbox_id` é gravado e ignorado).
- **Conteúdo:** "Como você quer começar?" (IA, modelo, do zero); Criar com IA com briefing, recursos (imagem com papel, PDF, vídeo por link) e "adaptar o design atual", geração assíncrona com aviso global; ações de IA por bloco; blocos e propriedades; prévia computador/celular; tela cheia; personalização; salvar como modelo; biblioteca e Meus modelos.
- **Enviar teste:** usa o primeiro destinatário como amostra e deixa o descadastro inerte; **passa a funcionar também no envio direto pela caixa**.
- **Operação:** agendar, pausar, retomar, cancelar (pendentes viram suprimidos), duplicar (sem destinatários), excluir só rascunho sem histórico, reenvio de throttling, rastreamento de abertura e clique.
- **Fora daqui:** `starterTemplates.js` não é usado por nada (remover em PR separado).

### 6.10 Gestão de campanhas (visão geral)

Responde "como vão as campanhas no geral" (D18). Período, filtro por canal (só conectados), totais (campanhas enviadas, pessoas alcançadas, responderam, viraram negócio no CRM, saúde do e-mail) e tabela comparativa por campanha com canal, data, enviadas, entregues, engajamento (abriram/leram), responderam e taxa. Clicar abre o Resultado. O detalhe de uma campanha não fica aqui.

### 6.11 Marcas na conversa

O painel do contato na conversa mostra **"Origem e campanhas"** com todas as marcas, na ordem (Link, Campanha WhatsApp, Campanha e-mail…), e os públicos do contato. O topo da conversa mostra a marca da campanha que a abriu. A mensagem de campanha aparece na conversa com o rótulo da campanha e do modelo (D20).

## 7. Layout

Padrão do workspace #800 (`EmailCampaignsPage.vue`), regras de `docs/audit/800-email-campaigns-uiux.md` e `docs/relationships/visual-contract.md`:

- Moldura larga, caminho no topo, título + subtítulo, **uma** ação principal.
- Faixa de resumo contínua; primeiro bloco em azul-marinho `#0D2344`.
- Lista em cartão, filtros por canal e situação, busca.
- Passos numerados (`aria-current="step"`); prévia fixa ao lado no desktop, abaixo no celular.
- Painel lateral de 37rem para detalhes de público.
- Escolhas com `ChoiceSelect`; nenhum `<select>` nativo, `ComboBox` ou `TagMultiSelectComboBox` antigo nas telas novas.
- Tailwind e tokens `n-*`, sem CSS próprio. Ícones Lucide do produto (o do canal: envelope, balão com marca, balão simples).
- 1440, 1280, 1024, 768 e 390px; claro e escuro.

## 8. Requisitos técnicos

### 8.0 Construção aditiva (regra para todos os PRs)

Objetivo: atualizar o Chatwoot oficial sem conflito.

1. **Arquivos novos, nomes do fork.** Telas, componentes, stores, controllers, serviços e jobs da jornada vivem em arquivos novos (ex.: `components-next/CampaignJourney/`, `routes/dashboard/campaigns/journey/`, `app/services/campaign_journey/`, `app/controllers/api/v1/accounts/campaign_journey/`). Nada de reescrever `WhatsAppCampaignsPage.vue`, `CampaignLayout.vue`, `WhatsAppCampaignDialog.vue` ou `EmailCampaignDialog.vue`: as rotas antigas passam a redirecionar para a nova lista filtrada e os arquivos antigos ficam intactos.
2. **Toque em arquivo do Chatwoot só para registrar.** Permitido: uma linha de rota/menu (`campaigns.routes.js`, `Sidebar.vue`), um `include`/`prepend_mod_with` num model ou serviço. Cada toque fica listado no PR com o motivo e o número de linhas.
3. **Mudança de comportamento por módulo prepended do fork**, carregado por initializer próprio — por exemplo, registrar destinatários `queued` antes do envio no WhatsApp Oficial fica num módulo `CampaignJourney::WhatsappOneoffRecipients` prepended em `Whatsapp::OneoffCampaignService`, não editando o serviço nem o overlay `enterprise/`.
4. **Banco só aditivo, e sem coluna nova em tabela do Chatwoot.** Vínculo campanha ↔ público numa tabela própria `campaign_audience_links (account_id, campaign_type, campaign_id, campaign_import_id)` em vez de `campaigns.campaign_import_id`. Colunas novas só em tabelas do fork (`campaign_imports`, `campaign_import_rows`).
5. **Textos** em chaves novas do fork (`config/fork_i18n.json`), sem editar chaves do Chatwoot.
6. **Flag de desligamento**: `CAMPAIGN_IMPORT_ENABLED` (já existe) desliga Públicos; `CAMPAIGN_JOURNEY_ENABLED` (nova) volta o menu e as rotas para as telas antigas sem deploy.

### 8.1 Dados

- `campaign_audience_links` (nova, índice único por `campaign_type, campaign_id`).
- `campaign_imports`: `name`, `channels` (jsonb: `{email: {enabled, count}, whatsapp: {enabled, count}}`, calculado na validação, `enabled` editável), `extra_columns` (lista dos cabeçalhos extras), `schema_resolution` (jsonb, sem dado de linha), contadores `companies_created_count`, `companies_reused_count`, `companies_kept_count`.
- `campaign_import_rows`: `company_id`, `company_result` (`created` | `reused` | `kept_other` | `none`), `email_masked`, `normalized_email_hash`, `extra_values` (jsonb com os valores das colunas extras daquela linha, usado nas variáveis da mensagem; apagado junto com o público; nunca enviado à IA).
- Novas importações gravam `batch_count = 1`.

### 8.2 Importação (planilha → contatos e empresas)

- `CampaignImports::SchemaResolver` acha nome, celular, e-mail e empresa (todos opcionais, mas a linha precisa de celular **ou** e-mail válido); o resto vira coluna extra. Jev decide a coluna de cada necessidade ou "não há"; fallback determinístico com os aliases atuais; sem resposta confiável → escolha manual na tela, não erro.
- Validação linha a linha; recusa o arquivo só se nenhuma linha for válida ou por erro global.
- Contato existente: celular pelas variantes brasileiras (`BrazilPhoneNormalizer#contact_candidates`); e-mail normalizado e comparado sem diferença de caixa.
- **Empresa:** procura por domínio do e-mail corporativo quando houver empresa com aquele `domain`; senão por nome normalizado (espaços colapsados, sem diferença de caixa e acento, comparação exata). Não existe → cria `Company` com o nome como está na planilha (aparado). Contato sem empresa → liga. Contato com a mesma → nada. Contato com outra → mantém e marca `kept_other`. Uma empresa por nome por importação (sem duplicar dentro do arquivo).
- **Selos de canal:** `channels.email.count` = linhas com e-mail válido (descadastrados e e-mails que voltaram são descontados só na revisão da campanha); `channels.whatsapp.count` = linhas com celular brasileiro válido. Canal com contagem 0 nasce desligado e não pode ser ligado.
- **Variáveis da mensagem:** no passo Mensagem, o sistema sugere a coluna extra para cada variável do modelo comparando os rótulos (a IA recebe só os rótulos da variável e os cabeçalhos, nunca valores); a pessoa confirma ou troca.
- Gravação ao **salvar o público**, em blocos de 500, cada bloco em sua transação, idempotente por `row_number`.
- Rascunho não confirmado não cria contato, empresa nem etiqueta; expira em 30 dias.

### 8.3 Envio

- WhatsApp Oficial: guarda de caixa Cloud (422 antes de `mark_processing!`); destinatários `queued` antes do envio (módulo do fork, 8.0-3); webhook de status já existente atualiza entregue/lido/falhou.
- WhatsApp API: motor atual (`WhatsappApiCampaigns::*`) sem mudança; ganha a ficha "empresa" no texto (resolvida por `contact.company.name`).
- E-mail: motor atual; destinatários vêm do público (contatos) em vez da lista solta, mantendo supressão e descadastro.
- "Respondeu" = mensagem recebida do contato na mesma caixa até 72h depois do envio.
- **Marca no CRM (D14):** um job do fork, disparado na primeira mensagem recebida que conta como "respondeu", chama `Ctwa::CampaignBuilder.attribute!(conversation, source_type: "campaign_whatsapp" | "campaign_email", source_id: "campaign:<tipo>:<id>", headline: <nome da campanha>)`. No e-mail, o botão que leva ao WhatsApp usa o mesmo `#TOKEN` dos links rastreados (`Ctwa::TrackedLinkAttributor` ganha o reconhecimento do código de campanha). `source_for` e `useCrmOrigin.js` (código do fork) ganham as duas origens e rótulos. Nada é gravado no envio.

### 8.4 Correções que entram primeiro

- `LabelPlanner#batch_sizes` com `divmod` (backend, sem tela).
- `Validator`: exceção inesperada registrada com classe e mensagem segura.

### 8.5 Guia da Plataforma e i18n

- Rotas novas no roteador; `pnpm guia:build` e blocos em `lib/operator_guide/porques.md` para Todas as campanhas, Nova campanha e Públicos; remover os fluxos "Base Campanha" e "Histórico de bases".
- `pnpm i18n:fork:check`.

### 8.6 Envio para a lista do público (sem etiqueta)

- Público = `campaign_imports` + `campaign_import_rows.contact_id`; campanha ↔ público por `campaign_audience_links`.
- Módulo do fork `CampaignJourney::AudienceContacts` entrega os contatos do público aos serviços de envio (WhatsApp Oficial, WhatsApp API, SMS, e-mail), prepended por initializer; os serviços do Chatwoot não são editados.
- Novas importações não chamam `LabelPlanner`; importações e campanhas antigas por etiqueta continuam funcionando sem mudança.
- E-mail: destinatários da campanha passam a vir dos contatos do público (com `contact_id`), mantendo `email_campaign_recipients` e todas as travas de §6.9.

### 8.7 Jev em todas as importações

- Um serviço só para ler planilha (Públicos e Importar contatos), reaproveitando `CampaignImports::Parser`/`SchemaResolver` e `TypesafeAi::ImportSchemaResolver` generalizado (alvos: nome, celular, e-mail, empresa; resto vira coluna extra/atributo).
- `TypesafeAi::Client#evaluate`, modelo fixo `jev-1.13.0` (nunca `jev-latest`), retries e erros sanitizados existentes; chave em `AiProviderCredential.for('typesafe')`.
- Payload só com cabeçalhos, contagens e formato mascarado; limiares atuais (≥ 0,8 por coluna).
- Flag própria do fork para a jornada (ex.: `CAMPAIGN_JOURNEY_JEV_ENABLED`); `TYPESAFE_JEV_ENABLED` continua governando a importação de e-mail atual. Jev indisponível → escolha manual na tela, nunca alias silencioso.
- Importar contatos: tela do fork na entrada do menu ⋮ de Contatos; colunas extras viram atributos personalizados do contato; cria/liga empresas (§8.2). O importador do Chatwoot fica intacto atrás da flag.

### 8.8 SMS

- Módulo do fork nos serviços `Sms::OneoffSmsCampaignService` / `Twilio::OneoffSmsCampaignService`: `CampaignRecipient` por contato (`mark_sent!`/`mark_failed!` com motivo), conversa e mensagem de saída com `campaign_id`, resposta marcada por contato+caixa (padrão do WhatsApp) e marca no CRM (D14).
- Callbacks de status (Twilio `StatusCallback`, Bandwidth) para entregue/falhou quando disponíveis.
- Corrigir `getSMSCampaigns` para filtrar medium SMS (hoje lista campanhas de WhatsApp via Twilio).

### 8.9 E-mail: respostas e teste

- **Reply-to por caixa:** quando a campanha escolhe "Respostas vão para a caixa X", o envio (SES e direto) usa o endereço dessa caixa no `Reply-To`; a resposta entra como conversa nela, ligada ao contato e à campanha (marca D14).
- **Enviar teste no envio direto:** `test_sends_controller` passa a enviar pela caixa quando `delivery_mode = direct_inbox`, com as mesmas regras (amostra do primeiro destinatário, descadastro inerte).

### 8.10 Canais conectados

- Composable do fork `useAvailableCampaignChannels()` decide, por canal, "recurso ligado" + "tem caixa ou remetente":
  - E-mail: `EMAIL_CAMPAIGN_ENABLED` + `CRM_KANBAN_ENABLED` e (domínio verificado ou caixa de e-mail).
  - WhatsApp Oficial: recurso `whatsapp_campaign` e caixa WhatsApp Cloud.
  - WhatsApp API: `WHATSAPP_API_CAMPAIGNS_ENABLED` e caixa API marcada para campanha.
  - SMS: caixa de SMS (Twilio SMS ou Bandwidth).
  - Chat ao vivo: caixa de site.
- O mesmo resultado alimenta menu, escolha de canal e filtros; o backend recusa criar campanha em canal não conectado (422).

## 9. Termos de aceite

Formato **Dado · Quando · Então**. Só passa com evidência (teste automatizado citado no PR ou captura do produto construído).

### J. Público primeiro

- **J1** Dado "Nova campanha", então o Passo 1 é "Quem vai receber" e lista só públicos salvos, cada um com selos de canal e contagens.
- **J2** Dado conta sem nenhum público, então o Passo 1 mostra uma frase e um único botão "Criar público"; ao clicar, abre Públicos com o aviso da campanha em andamento e o rascunho fica salvo.
- **J3** Dado público salvo a partir da campanha, então a pessoa volta ao Passo 1 da mesma campanha com esse público já escolhido.
- **J4** Dado público com e-mail mas sem celular, então no passo Mensagem os cartões de WhatsApp aparecem indisponíveis com "Este público não tem celular" (e o inverso para e-mail); a API recusa canal fora do público.
- **J5** Dado planilha com e-mail e celular, então os dois selos nascem ligados com suas contagens; desligar um faz o público não aparecer como opção daquele canal.
- **J6** Dado planilha sem coluna de e-mail, então o selo E-mail aparece desligado com "sem dados" e não pode ser ligado.
- **J7** Teste de leitura com 3 pessoas sem treinamento: as três criam o primeiro público e voltam para a campanha sem ajuda.

### K. Marca no CRM

- **K1** Dado destinatário de campanha WhatsApp que responde em até 72h, então a conversa ganha a marca "Campanha: <nome>" e o card ligado mostra a marca (teste com webhook simulado).
- **K2** Dado destinatário que não responde, então nenhuma marca é gravada (teste de banco após o envio).
- **K3** Dado card que já tinha "Link: Feira 2026" e recebe a marca de duas campanhas, então mostra a primeira e o selo "+2", e a gaveta lista as três na ordem.
- **K4** Dado e-mail cujo botão leva ao WhatsApp e a pessoa manda a mensagem, então a conversa ganha "Campanha: <nome do e-mail>".
- **K5** Dado resposta por e-mail que vira conversa na caixa das respostas, então a conversa ganha a marca.
- **K6** O filtro de campanha do Kanban e das Conversas lista as campanhas e filtra os cards marcados.
- **K7** Marca de campanha não substitui a primeira origem de uma conversa que já veio de anúncio ou link (aparece como toque seguinte).

### L. E-mail sem perder nada (§6.9)

- **L1** Cada trava da lista de prontidão (assunto, conteúdo, remetente, destinatários, importação, higiene, reputação) impede o envio na jornada nova exatamente como hoje — spec por trava.
- **L2** Provedor com bounce ≥ 5% ou reclamação ≥ 0,1% (ou dado desconhecido) bloqueia o envio e mostra o motivo.
- **L3** Rodapé de descadastro continua travado no editor; `List-Unsubscribe` one-click continua no cabeçalho.
- **L4** Envio direto pela caixa: horário comercial, teto diário e pausa automática funcionam como hoje.
- **L5** "Respostas vão para a caixa X": e-mail de teste e envio real saem com `Reply-To` da caixa; a resposta vira conversa nessa caixa, ligada ao contato e com a marca da campanha.
- **L6** "Enviar teste" funciona no envio por domínio e no envio direto; não conta no resultado.
- **L7** Criar com IA (briefing, recursos, adaptar), ações por bloco, biblioteca/Meus modelos, salvar como modelo, tela cheia, celular/computador e personalização funcionam dentro da jornada.
- **L8** Pausar, retomar, cancelar, duplicar e excluir rascunho funcionam a partir do Resultado e da lista.

### M. Canais conectados, SMS e Chat ao vivo

- **M1** Conta sem caixa de SMS não vê SMS em lugar nenhum (menu, escolha, filtro); ao conectar, aparece sem deploy.
- **M2** Mesma regra para E-mail, WhatsApp Oficial, WhatsApp API e Chat ao vivo (§8.10); API recusa canal não conectado.
- **M3** SMS: cada destinatário fica com situação (enviado/entregue/falhou com motivo); o envio aparece na conversa; resposta conta em "Responderam" e marca no CRM.
- **M4** A lista de SMS não mostra campanhas de WhatsApp via Twilio.
- **M5** Chat ao vivo: atalho no passo Público leva a Quando aparece → Mensagem → Ativar; aparece na lista com "Sempre ativa"; quem conversa ganha a marca.

### N. Público sem etiqueta

- **N1** Importação nova não cria nenhuma etiqueta (teste de banco).
- **N2** Campanha de cada canal envia exatamente para os contatos do público (sem etiqueta), respeitando recusa/descadastro.
- **N3** Campanhas e importações antigas por etiqueta continuam enviando e aparecendo.
- **N4** "Excluir público" apaga só a lista; contatos, empresas, conversas e resultados ficam.

### O. Resultado × Gestão de campanhas

- **O1** Todo indicador, gráfico, tabela, filtro, exportação e ação da Gestão de campanhas de hoje existe no Resultado da campanha de e-mail (checklist item a item no PR).
- **O2** Resultado do WhatsApp mantém tudo da página atual e ganha exportação, "Responderam" e "Abrir conversa".
- **O3** Gestão de campanhas mostra só a visão geral multicanal (período, canal, totais, comparativo) e leva ao Resultado ao clicar.

### P. Marcas na conversa

- **P1** Conversa de contato com link + duas campanhas mostra as três marcas na ordem no painel do contato.
- **P2** A mensagem enviada pela campanha aparece na conversa com o nome da campanha.

### Q. Jev em todas as importações

- **Q1** Públicos e Importar contatos usam o mesmo serviço de leitura com Jev; spec prova que o payload não tem nome, número nem e-mail.
- **Q2** Importar contatos cria/reaproveita/liga empresas com as mesmas regras de C1–C7 e grava colunas extras como atributos do contato.
- **Q3** Jev desligado ou indisponível: escolha manual das colunas, sem erro e sem alias silencioso.
- **Q4** Rodada real paga do Jev só com teto aprovado pelo Rodrigo, registrada em `docs/audit/`.

### A. Lugar e navegação

- **A1** Dado `campaign_view`, quando abre o menu Campanhas, então vê "Todas as campanhas" e "Públicos" no topo do grupo.
- **A2** Dado qualquer usuário, quando abre o menu ⋮ de Contatos, então não vê "Base Campanha" nem "Histórico de bases".
- **A3** Dado os endereços antigos de E-mails, WhatsApp Oficial, WhatsApp API e `/contacts/campaign-imports`, quando acessados, então abrem a lista filtrada pelo canal (ou Públicos) sem erro.
- **A4** Dado só `campaign_view`, então não vê importar, remover do público, agendar ou disparar, e a API devolve 401/403 para essas ações.
- **A5** Dado `CAMPAIGN_JOURNEY_ENABLED=false`, quando a conta navega em Campanhas, então vê as telas antigas como antes (teste de rota).

### B. Planilha e colunas

- **B1** Dado XLSX com `Segurado`, `Fone 1`, `Corretora`, `Vencimento` e modelo com `{{1}}` nome e `{{2}}` mês de vencimento, quando enviado em Novo público, então nome, celular e empresa ficam ligados às colunas e `Vencimento` fica como coluna extra; no passo Mensagem, `{{2}}` vem sugerido como "Coluna do público: Vencimento", e `schema_resolution.method = "jev"`.
- **B1a** Em nenhuma tela, texto ou dica da jornada aparece "Jev", "IA" ou nome de modelo — spec verifica os textos i18n das telas novas.
- **B1b** Dado linha válida sem valor numa variável usada, então fica de fora com motivo "falta <variável>", salvo texto padrão escolhido.
- **B1c** Dado CSV `;` com `Responsável`, `Email comercial`, `Corretora`, quando enviado em Novo público, então nome, e-mail e empresa são ligados e o selo E-mail nasce ligado.
- **B2** Dado Jev desligado, então a tela pede a escolha manual das colunas que faltarem e a importação conclui depois.
- **B3** Dado cabeçalho na linha 3, então é achado sem intervenção.
- **B4** Dado qualquer arquivo, quando o Jev é chamado, então o payload tem só cabeçalhos, contagens e formato mascarado — spec prova que nenhum nome, número ou e-mail do arquivo aparece.
- **B5** Dado 100 linhas com 2 inválidas, então mostra "98 prontos · 2 com problema", motivo por linha mascarado, e permite seguir com 98.
- **B6** Dado arquivo sem linha válida, então é recusado com os motivos e nada é gravado.
- **B7** Dado celular salvo como `+55DD8XXXXXXX`, quando a planilha traz `+55DD98XXXXXXX`, então o contato existente é reutilizado.
- **B8** Dado contato que recusou mensagens (WhatsApp) ou descadastrado/e-mail que voltou (e-mail), então aparece em "não recebem" e fica fora do total.
- **B9** Dado que o usuário sai antes de salvar o público, então nenhum contato, empresa, etiqueta ou vínculo é criado (teste de banco).
- **B10** Dado 20.000 linhas, quando confirmado, então conclui em até 5 min em teste, em blocos, e uma falha simulada marca só aquela linha.

### C. Empresas

- **C1** Dado coluna de empresa com "Alfa Corretora" em 10 linhas e a empresa inexistente, quando confirmado, então é criada **uma** empresa e os 10 contatos ficam ligados a ela.
- **C2** Dado "ALFA  corretora" na planilha e "Alfa Corretora" já na base, então a existente é reaproveitada (nenhuma nova).
- **C3** Dado contato com e-mail `@alfacorretora.com.br` e empresa com `domain = alfacorretora.com.br`, então liga a ela mesmo que o nome na planilha seja diferente.
- **C4** Dado contato já ligado à "Beta Seguros" e a planilha diz "Alfa Corretora", então o contato continua na Beta, a linha conta como "mantida" e a tela mostra o número.
- **C5** Dado o interruptor "Criar e ligar" desligado, então nenhuma empresa é criada nem ligada.
- **C6** Dado a flag `companies` desligada na conta, então a linha "Empresa" e o bloco Empresas não aparecem e nada é criado.
- **C7** Dado "Remover do público", então nenhuma empresa nem ligação contato–empresa é desfeita.

### D. Envio

- **D1** Caixa WhatsApp não-Cloud não aparece no passo Mensagem do WhatsApp Oficial; a API recusa com 422 se enviada à força.
- **D2** Dado o horário, então todos os destinatários elegíveis ficam com situação registrada — zero sem situação depois que a campanha conclui, nos três canais.
- **D3** Nenhuma tela mostra lote, quantidade de lotes ou envio em etapas; importação nova grava `batch_count = 1`.
- **D4** Erro do provedor deixa o destinatário `failed` com motivo legível; os demais seguem.
- **D5** Contato que recusa durante o envio é pulado (regra #737).
- **D6** Resposta de número sem o 9 entra na conversa do contato importado (webhook simulado).
- **D7** WhatsApp API: ficha "empresa" vira o nome da empresa do contato; sem empresa, a linha fica de fora com motivo "falta empresa" (ou texto padrão).
- **D8** E-mail: "Enviar teste para mim" chega só ao usuário logado e não conta no resultado.
- **D9** E-mail: depois de canal e nome, a jornada mostra "Como você quer começar?" com Criar com IA, Escolher um modelo e Começar do zero; cada opção leva à tela certa e o passo continua marcado como 2 (Mensagem).
- **D10** E-mail com IA: dado briefing, objetivo, tom e um recurso (logo), quando gerar, então o editor abre com assunto, prévia e layout montados, usando as fichas nome/primeiro nome/empresa; erro ou IA não configurada mostra a mensagem atual do produto e permite seguir pelo modelo ou do zero.
- **D11** E-mail com modelo: Biblioteca e Meus modelos, filtro por objetivo, busca, prévia e "Usar este"; "Adaptar com IA" mantém o layout e reescreve os textos.
- **D12** O editor existente abre dentro da jornada e "Continuar" leva a Detalhes do envio sem perder o conteúdo; nenhuma mudança interna no editor (aceite H).
- **D13** Detalhes do envio: só domínios verificados; caixa das respostas escolhida; assunto com sugestões da IA (quando configurada); prévia de caixa de entrada atualiza ao trocar o assunto.

### E. Resultado

- **E1** WhatsApp: soma Enviadas + Falharam + Puladas = Público elegível; e-mail: Entregues + Voltaram + não enviados = Público elegível.
- **E2** Status do provedor muda os números sem recarregar (ou no polling de até 30s).
- **E3** "Abrir conversa" abre a conversa do contato que respondeu.
- **E4** "Baixar resultado" traz situação, horários e motivo por pessoa, mascarado.

### F. Públicos

- **F1** As 13 importações antigas da conta 6 aparecem com nome, contatos e a campanha que as usou (vínculo inferido pela etiqueta, migração idempotente).
- **F2** "Excluir público" apaga só a lista; nada é apagado da base; a campanha concluída mantém o resultado (ver N4).
- **F3** "Usar em nova campanha" abre a campanha com o público já escolhido no Passo 1.
- **F4** Nome técnico de etiqueta não aparece em nenhum texto da interface.

### G. Layout e acessibilidade

- **G1** Telas seguem o mockup aprovado e o padrão #800 — revisão visual no PR.
- **G2** Nenhum `<select>` nativo nem `ComboBox` antigo nas telas novas; spec no estilo de `uxAcceptance444.spec.js`.
- **G3** Sem rolagem horizontal da página nem texto cortado em 1440/1280/1024/768/390, claro e escuro (capturas).
- **G4** Teclado completo nos 3 passos; `aria-current="step"`; alvos ≥ 44px; contraste ≥ 4.5:1; interruptor de empresas com `role="switch"`.

### H. Construção aditiva

- **H1** O PR lista cada arquivo do Chatwoot tocado, com motivo e linhas; nenhum arquivo do Chatwoot tem mais que o registro de rota/menu ou um `prepend_mod_with`/`include`.
- **H2** `git diff upstream/<versão>...` dos arquivos de campanha do Chatwoot (`WhatsAppCampaignsPage.vue`, `CampaignLayout.vue`, `WhatsAppCampaignDialog.vue`, `EmailCampaignDialog.vue`, `Whatsapp::OneoffCampaignService`, `enterprise/.../oneoff_campaign_service.rb`) não muda por causa desta épica.
- **H3** Nenhuma migration adiciona coluna em tabela do Chatwoot; todas são reversíveis sem perda (tabelas e colunas novas).
- **H4** Merge de teste com a próxima versão do Chatwoot (ou a atual `main` do upstream) sem conflito nos arquivos da épica.

### I. Correções e operação

- **I1** `LabelPlanner`: spec 1..50 linhas × 1..10 lotes, tamanhos positivos e soma exata.
- **I2** Exceção inesperada na validação aparece no log com classe, sem dado pessoal.
- **I3** `pnpm guia:check`, `pnpm i18n:fork:check`, RuboCop, ESLint, RSpec e Vitest dos arquivos tocados verdes; saída lida.
- **I4** Revisor independente antes do merge; tester de produção com roteiro listado antes de rodar.
- **I5** Rollback escrito: `CAMPAIGN_JOURNEY_ENABLED=false` volta as telas antigas; `CAMPAIGN_IMPORT_ENABLED=false` esconde Públicos; migrations não são revertidas.
- **I6** Primeiro envio real por canal acompanhado em produção: zero destinatários sem situação.

## 10. Como será construído e testado

- **Orquestração dinâmica:** cada PR é feito com orquestração de agentes (workflow): implementação, revisor independente e tester em paralelo por fatia, com verificação cruzada antes de declarar pronto. Tamanho do workflow combinado com o Rodrigo por PR.
- **Testes reais no chat2you local:** instância local do Chatwoot (rails + vite numa worktree em `/dev/worktrees/chat2you/`, `Procfile.worktree`, banco e portas por worktree, conta de desenvolvimento criada por script) — a mesma usada pelas outras sessões. Cada termo de aceite é exercitado ponta a ponta nela (planilhas sintéticas, envio para caixas e números de teste), além de RSpec/Vitest. Suíte Ruby em paralelo pelos snapshots do MacCluster (`/Users/Shared/maccluster-workspaces/chat2you/`), nunca sobrescrevendo o checkout ativo.
- **Envio real** só para números e endereços de teste, com OK do Rodrigo por rodada; nunca para clientes. Rodada paga do Jev só com teto aprovado.
- **Produção:** só leitura (psql via SSM, sem `rails runner`), e só com necessidade; merge e deploy pela fila, um PR por vez, avisando as outras sessões e com "ok, SHA" depois; rollback escrito antes.
- **Pronto quando:** aceite com evidência (spec citado ou captura do chat2you local), revisor independente, tester de produção no primeiro envio real de cada canal.

## 11. Entrega em PRs

| PR | Issue | Conteúdo | Aceite |
|---|---|---|---|
| 1 | #991 | Correções: lotes (backend), importar só válidas, busca com/sem 9, blocos de 500, guarda de caixa Cloud, log | B5–B7, B10, D1, I1, I2 |
| 2 | #992 | Colunas pelo Jev: celular, e-mail, empresa e variáveis; escolha manual | B1–B4, B1a–B1c |
| 3 | #998 | Empresas na importação (criar, reaproveitar, ligar, manter) | C1–C7 |
| 4 | #993 | Menu (Público, Campanha), lista "Campanha" com canais conectados, Públicos, jornada em 3 passos para WhatsApp Oficial (Público → Mensagem → Revisar), selos de canal, criação de público com volta para a campanha, resultado WhatsApp, flag e redirecionamentos | A, B8–B9, D2–D6, E, F, G, H + J1–J7 |
| 5 | #999 | WhatsApp API e E-mail dentro da jornada (Passo 1 de cada canal, Passo 2 de e-mail com contatos, resultado e-mail, fim do formulário lateral) + reply-to por caixa e teste no envio direto (§8.9), lista "não pode perder" (§6.9) | D7, D8, E1 (e-mail), G, H + L1–L7 |
| 6 | #1002 | Marca da campanha no CRM na resposta (WhatsApp, SMS, e-mail, Chat ao vivo), filtros de campanha e marcas na conversa | K1–K7, P1–P2 |
| 7 | #1005 | Público sem etiqueta: envio para a lista do público | N1–N4 |
| 8 | #1007 | Resultado por campanha com todos os motores + Gestão como visão geral | O1–O3, L8 |
| 9 | #1004 | SMS na jornada (registro, conversa, marca) | M1–M4 |
| 10 | #1008 | Chat ao vivo com fluxo próprio | M5 |
| 11 | #1006 | Importar contatos com Jev e empresas | Q1–Q4 |

Cada PR com `Refs #990`; o último fecha a épica.

## 12. Riscos

| Risco | Mitigação |
|---|---|
| Conflito em atualização do Chatwoot | Regra 8.0 + aceite H; flag para voltar às telas antigas |
| Empresa duplicada por grafia diferente | Domínio antes do nome; nome normalizado; uma por importação; contagem "já existiam" visível antes de confirmar |
| Sobrescrever empresa certa | Nunca troca empresa já ligada; conta como "mantida" |
| E-mail criar milhares de contatos (D11) | Só na confirmação; contagem de novos visível antes de confirmar |
| Jev indisponível ou caro | Fallback determinístico + escolha manual; uma chamada por arquivo |
| Limite da Meta | Motivo de falha legível; aviso na revisão |
| Importações antigas sem vínculo | Migração idempotente pela etiqueta |
