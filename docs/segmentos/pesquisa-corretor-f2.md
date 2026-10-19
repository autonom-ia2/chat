# Pesquisa de mercado: a língua do corretor de seguros (F2 corretora)

Issue autonom-ia2/chat#1802 · épico #1545 · 18/10/2026 · só leitura.

Esta pesquisa completa o que já foi feito na F0/F0b. Ela não repete o que está
decidido. Traz fontes novas, de ferramentas brasileiras e da imprensa do setor,
e confere com elas o que ainda estava fraco.

**Como ler.**
- Frequência: **A** = 2 ou mais fontes literais; **M** = 1 fonte literal;
  **B** = só por analogia, ou só da base.
- "não achado" quer dizer que a página lida (às vezes parcial ou dinâmica) não
  trazia o termo. **Não quer dizer que o termo não existe.**
- Fonte de fornecedor de chatbot (AiSensy, Aurora, SocialHub) é material de
  venda: serve para jornada, não para número.
- Os códigos `[SG-AJ]`, `[AG-MAN]` etc. são os da F0 (anexo do comentário
  6170730386 na #1545). As fontes novas vêm com a URL no próprio texto e na lista
  do fim.

---

## 1. O que já está decidido

Isto não se discute de novo nesta F2.

**Arquitetura do pacote** (docs/segmentos/README.md, F1 #1579 no ar):
- Conta corretora usa as camadas `seguros` e depois `seguros/corretora`, por chave, com o geral como
  reserva. Quem ganha: nome que a conta deu > pacote > geral.
- O interruptor `AUTONOMIA_PACOTES_ENABLED` fica desligado e **só liga depois da #1584**
  (IA, Guia e Central na mesma língua).
- Funil já criado não muda, porque o nome da etapa fica gravado em `crm_stages.name`.

**Vocabulário** (decisões do Rodrigo de 14/10, comentários 6169865877, 6171332975 e 6171475623):
1. O vocabulário muda por tipo, o mais específico possível.
2. **O menu continua "Contatos" para todos os tipos.**
3. **"Segurado" só onde a pessoa já tem apólice; no resto, "cliente".** Hoje nenhum
   texto diz "segurado", porque saber se há apólice exige código. "Cotação" e
   "proposta" ficam só no funil.
4. **Funil de Vendas igual em todos os tipos:** Novo contato · Em conversa ·
   Proposta enviada · Negociação · Fechado ("tem funcionado, não mudaria").
5. **O resultado da venda vira "Seguro ativo / Não fechou"**, com as 11 regras
   de texto do README ("Fechou o seguro", "Taxa de fechamento", nunca "perda"
   nem "perdido", e "Negócio" sai do resultado).
6. Os modelos de Atender **são renomeados por tipo**, com o critério de IA por
   modelo e posição (Multifunnel #1548/#1554). Os nomes são os da validação de
   mercado (comentário 6171647302):
   - **Renovação:** A renovar · Cotando a renovação · Esperando o cliente · Renovada.
     Saída de cancelamento: "Não renovou".
   - **Sinistros:** Aviso recebido · Em análise · Esperando documentos · Encerrado.
     Saída: "Recusado". Sinistro negado sai como Resolvido, com o motivo "negado".
   - **Parcelas:** A vencer · Atrasada · Prometeu pagar · Paga.
   - **Agendamento:** o da base, sem mudança agora.
7. A Renovação é funil de atendimento. Usar o vencimento da apólice como prazo
   fica para depois e exige código.
8. Regra de texto: nome curto, palavra do dia a dia e sem sigla ("QI 70").
   O pacote em inglês só aparece com o painel em inglês.

**Combinados com os chats** (comentário 6169910139):
- **Modelos WhatsApp:** a galeria de prontos (`campaigns/modelos/constants.js`)
  e os rótulos dos campos **entram** no pacote. A categoria vem do pronto, e
  não do pacote.
- **Não entram:** os prontos de sistema (`Whatsapp::Templates::Garantir`,
  cobrança e agendamento), os prompts de `ai/redacao` e o que já está na Meta.
- **Base de Clientes:** "segurado" é só a palavra para o mesmo estado
  `customer`, nunca um campo novo.
- **Followup IA:** o bloco de segmento entra só como dado. Linha nova no prompt
  pede eval pago, com decisão do Rodrigo.

**O que a F0b já levantou da corretora** (comentário 6170729699, seção 2.1):
- como a corretora trabalha;
- a tabela da camada, com placeholders, meta de produção e produtor;
- os campos e lembretes propostos (exigem código);
- os conflitos.

Esta pesquisa **não reescreve** essa tabela. Ela confirma ou corrige a tabela
nas seções 3 a 6.

---

## 2. Ferramentas brasileiras

Legenda: **lido** = página ou documento aberto nesta rodada; **F0** = já lido na
F0, aqui só o que importa.

| Ferramenta | O que é | Menus e telas (literal) | Etapas de funil e status (literal) | KPIs e relatórios | WhatsApp | Termos para o cliente e para a venda | Fonte |
|---|---|---|---|---|---|---|---|
| **Segfy** (Porto) | Gestão e multicálculo | Produtos: Segfy Gestão, Multicálculo, Vende, Carteira, Mensagem, Assina, Inteligência e Saúde. A Gestão cobre "Segurados, apólices, propostas, renovações, sinistros, comissões, financeiro e multicálculo". Na ajuda: "Segurados, Propostas e Apólices", "Parcelas do Segurado, Tarefas e Sinistros", "Grades de Recebimento e Parcelas", "Repasse de Comissão", "Recebimento de Comissão", "Fluxo de Caixa", "Endossos", "Portal da Seguradora" e "Automações" | **Documento:** "vigente", "não renovada", "recusada", "Propostas pendentes de emissão", "Apólices pendentes de renovação". **Orçamento:** "aceitas pelo cliente", "aguardando resposta", "mover um orçamento para efetivado", "motivo de cancelamento de um orçamento" e "HFy - Como usar o funil de vendas". **Parcela:** "paga" / "não paga" e "Parcelas Atrasadas" | Relatório de produção por produtor, ramo, companhia e segurado. Relatório de renovação por produtor e por companhia. Comissões recebidas e não recebidas, "comissões a pagar" e "com previsão de pagamento". Telas "Renovações do dia de hoje" e "Renovações dos próximos 30 dias". "Pendência de Emissão" | "Central de mensagens integrada ao WhatsApp" (Segfy Mensagem) e "Atendimento no WhatsApp" (Segfy Vende, em breve). Nenhum texto de modelo achado | segurado (telas), cliente (marketing), produtor, companhia. "Lead" não achado | segfy.com; ajuda.segfy.com/knowledge (+ artigos na seção 7) |
| **Agger** (Gestor e ONE) | Gestão | Menu: NEGÓCIOS (Dashboard, Painel B.I, Prospectar), SEGUROS (Consultar, Clientes, Apólices, Faturas, Manutenções do documento: Renovar / Endossar / Recusar, Tarefas, Itens, Sinistros, Comissão automática), RELATÓRIOS, AGGILIZADOR, FINANÇAS e FERRAMENTAS (Seguradoras, Ramos, Produtos, Qualificação, Status da apólice, Estipulante, Vendedores) | **Renovação:** "RENOVANDO, RENOVADO e PERDIDO". "SEGURO PERDIDO: Contrato que venceu e não renovará, podendo então CRIAR PROSPECÇÃO", com agenda "SAIR EM RENOVAÇÃO". **Endosso:** "COM MOVIMENTO DE PRÊMIO", "SEM MOVIMENTO DE PRÊMIO", "CANCELAMENTO DE APÓLICE", "REABILITAÇÃO DE APÓLICE", "PRORROGAÇÃO DE VIGÊNCIA". **Cotação:** status "Ganho" e "STATUS PERDIDO", com lembrete na "vigência final do seguro menos 15 dias". **Tarefas:** "Agendado, A Fazer, Em Andamento e Concluído" | Relatórios: Novos negócios, Aniversariante, Licenciamento, Produção, Apólices pendentes, Renovações, Sinistro, Metas (seguradoras ou vendedores), Fechamento, Comissão recebida, Vencimento de parcela, Pagamento de vendedor, Faturas pendentes, Previsão de pagamento de comissão. Meta "baseada no prêmio líquido, data de emissão, ramo". Qualificação "Cliente Bronze / Prata / Ouro" | "ENVIAR WHATSAPP" da cotação, envio do cartão de assistência ao segurado e campo "WHATSAPP SINISTRO" | "Cliente/Segurado", vendedor, Cia. Seguradora, prêmio líquido. No sinistro: "PARTICIPANTE (terceiro)", "B.O., Orçamentos" | Manual do Gestor (PDF, lido); agger.com.br/?p=532, ?p=745, ?p=883 e blog sobre gestão, multicálculo e CRM |
| **Aggilizador** (Agger) | Multicálculo | "Cálculo", "Resultado de cálculo", "Funil de vendas", "Prospectar", "Metas", "Lembretes" | "Utilizado para o acompanhamento do seguro desde a elaboração da cotação até o fechamento. O funil é representado pelo status da cotação" | Funil com "cotações únicas" | "fazer a cotação e já enviar a cotação por e-mail ou por WhatsApp" | cotação, cálculo, fechamento | agger.com.br/?p=598; Manual |
| **Infocap** (da Agger desde 2024) | Gestão e multicálculo | Produtos "MultiGestor" (cotação) e "Corp" (gestão) | não achado | não achado | não achado | — | baguete.com.br/noticias/agger-compra-infocap; revistaapolice.com.br/?p=87474 |
| **"Corretor Online"** | **Não é da Infocap.** É o portal da Porto para o corretor gerir a própria carteira | — | Na Porto, a transmissão de proposta tem o status "pendência, emitida ou recusada" (via busca, no manual da Porto) | — | — | — | Busca; wwws.portoseguro.com.br/docs/calculo/ManualPortoPrintWEB.pdf (não aberto) |
| **Teleport** (TEx / Serasa) | Gestão e multicálculo | "gestão de clientes e apólices, financeiro, CRM completo, gerenciamento eletrônico de documentos". Funções: "Distribuição de Renovação em Lote", "Relatório de Parcelas", "Percentual de Parcelas de Repasse", "Cliente VIP", "Ramos Não Seguros", "Assinatura Eletrônica" | não achado | "Relatório de Parcelas" | Link de assinatura enviado ao segurado "através de aplicativos de mensagens" | "Quando o Segurado fecha com o corretor" | cqcs.com.br/noticia/teleport-ganha-novas-funcionalidades… |
| **Quiver** (Dimensa) | Gestão (QuiGo, Quiver MULT, BI) | F0: módulos Orçamentos, Renovações, Sinistros, Comissões/Prêmios, Produtores [QV-TOC]. **A ajuda deu 503 nesta rodada** | Artigo da Quiver: só "Topo / Meio / Fundo do Funil". F0: "não renovado", "avisos de sinistros" | "taxa de conversão de leads", "tempo médio de permanência no funil", "ticket médio" | não achado | leads, potenciais clientes, "fechamento de negócios" | cqcs.com.br/noticia/como-maximizar-as-vendas…; F0 |
| **Segura** (CRM com IA) | CRM e WhatsApp ("Conversas", assistente "Helena") | "central de negócios", "Conversas", Kanban | **"cotação, negociação, aguardando emissão e apólice emitida"**. A venda "só é encerrada quando o corretor insere no sistema a apólice emitida" | não achado | API oficial: "coleta informações necessárias para cotação", "encaminha o atendimento ao corretor responsável", e "cotações, renovações e atendimentos recorrentes" | leads, cotação, proposta, renovação | revistaapolice.com.br/2026/08/segura-integra-ia…; cqcs.com.br/noticia/segura-leva-ia-operacional… |
| **Agendor** | CRM genérico com página de corretora | "Funil + Painel de Vendas" | **"Um para novos seguros, outro para renovação"**. Campos: "Apólice", "ramo", "data de renovação". Aviso "1 ou 2 meses antes" do vencimento | "Produção do mês visível por corretor e por ramo", "Pipeline por vendedor, metas, conversão e alertas de negócio parado" | não achado | segurados, cliente, produção, "o que vai fechar no mês" | agendor.com.br/clientes/sistema-crm-corretoras-seguros; blog |
| **RD Station CRM** | CRM genérico com página de corretora | "Funil de Vendas", "Campos personalizados ilimitados" | Sem etapas. Recurso "multivendas" para "cliente que ainda não renovou sua apólice" | "metas de vendas", "tempo de primeiro contato" | "CRM para Vendas por WhatsApp" | cliente, apólice | rdstation.com/produtos/crm/solucoes/para-corretoras-de-seguros |
| **Ploomes** | CRM genérico | "vencimentos, renovações e recorrências com alertas automáticos". Caso Sixtini: funis de pré-venda e de venda | não achado | "conversão", "performance do time comercial" | só o ícone | clients | ploomes.com/en/industries/service-copy |
| **Pipedrive** | CRM genérico | "tipo de apólice e valores de prêmios" | sem nomes | "retenção do cliente", "probabilidade de conversão" | — | segurados, apólice, prêmio | pipedrive.com/pt/industries/insurance-crm |
| **SocialHub, AiSensy, Aurora** | Chatbot de WhatsApp (venda) | Fluxos de renovação a 30 dias e de sinistro (coleta de fotos e documentos, protocolo, status) | Sinistro, só AiSensy: "enviada, em análise, aprovada e liquidada" | promocionais, sem fonte | Um texto de renovação (AiSensy); categoria não informada | cliente | socialhub.pro/blog/…; m.aisensy.com/blog/pt/…; aurorainbox.com/pt/2026/05/18/… |
| **Ikaros** (saúde) | ERP de saúde | Ver F0 (camada `saude_beneficios`). Fora desta F2 | — | — | — | — | F0 |
| **Bidu, Kakau** | Corretora online e insurtech (para o consumidor) | não achado nada de tela ou mensagem | — | — | — | — | Busca |
| **Bitrix24, Kommo, Gestor Seguros, SIS, Zeeway** | — | **não achado** modelo de corretora com etapas. Fica como lacuna | — | — | — | — | Busca |

**O que se repete entre as ferramentas:**
1. Quatro blocos separam o trabalho: vender (cotação ou orçamento), cuidar do
   documento (proposta, apólice, endosso), renovar e o financeiro (parcela e
   comissão). O sinistro aparece como módulo próprio em Segfy, Agger e Quiver.
2. Duas ferramentas sem ligação entre si usam funil separado para renovação:
   Agendor ("um para novos seguros, outro para renovação") e Agger (status de
   renovação próprio). Isso valida a decisão 6.
3. O status de documento é sempre do mesmo tipo: pendente de emissão, emitida,
   recusada, vigente e não renovada (Segfy, Agger, Porto).
4. Relatório de verdade é **produção** (por produtor, ramo e seguradora),
   **renovação** e **comissão** (recebida, a receber e previsão). Nenhuma
   ferramenta brasileira mostra "taxa de conversão" como número principal.
5. O WhatsApp é usado para mandar cotação, cartão de assistência e link de
   assinatura, e como central de atendimento. **Nenhuma ferramenta publica o
   texto dos modelos.**

---

## 3. Glossário recomendado

Termo genérico do painel → termo do corretor. A coluna "Já no pacote?" diz se a
decisão já existe (seção 1). "Exige código" segue o critério da F0.

| Genérico (painel hoje) | Termo do corretor | Frequência | Fonte | Recomendação |
|---|---|---|---|---|
| Contatos (menu) | Clientes / Segurados nas ferramentas | A | Agger "CLIENTES", Segfy "Segurados" | **Fica "Contatos"** (decisão do Rodrigo). Não reabrir |
| Cliente (ficha) | cliente; segurado com apólice | A | Segfy, Agger "Cliente/Segurado", Teleport "Segurado" | Decidido. "Segurado" exige código |
| Lead | lead (CRM, marketing); **prospecção** (gestão) | A / A | Segura, Quiver: lead · Agger "PROSPECTAR", Segfy "prospecções" | "Lead" pode ficar. "Prospecção" serve para o cliente que não renovou e volta no ano seguinte (Agger) |
| Orçamento | **cotação** (funil); "orçamento" é sinônimo | A | Segfy "Orçamentos" e "Cotações HFy"; Agger "cotação"/"cálculo"; CQCS usa os dois | Na tela, "cotação". O agente aceita os dois |
| Proposta | proposta = documento formal enviado à seguradora | A | Segfy, Sompo, Porto, CQCS | Fica "Proposta enviada" no Vendas (decidido). Na Central, explicar que a proposta vai à seguradora |
| Fechar a venda | **efetivar** e **transmitir** a proposta | M / M | Segfy "mover para efetivado"; Sompo "efetivar o seguro"; Porto "histórico de transmissão" | Só na Central e na orientação do agente. Na tela, fica "Fechou o seguro" (decidido) |
| Ganho | **apólice emitida**; "Ganho" (Agger); "fechamento" | A | Segura, Agger, Agger "RELATÓRIO DE FECHAMENTO" | "Seguro ativo" (decidido). Coerente: o seguro só está ativo com a apólice emitida |
| Perdido | perdido (Agger, Quiver); "não renovada" (Segfy) | A | Agger, Segfy, Quiver | "Não fechou" e "Não renovou" (decidido) |
| Aguardando | **pendente de emissão** / "pendência" | A | Segfy "Propostas pendentes de emissão"; Agger "Apólices pendentes"; Porto "pendência" | Exemplo de follow-up "Cobrar a emissão da seguradora" (F0b) confirmado |
| Valor vendido / receita | **produção** | A | Segfy e Agger (relatório de produção), Agendor | Usar "produção" no título do painel e da meta (F0b já propõe "Meta mensal de produção") |
| Valor do negócio | prêmio; **prêmio líquido** (meta e comissão) | A | Agger, Pipedrive, Segfy | Na tela da equipe, "prêmio". Com o cliente, "valor do seguro" (F0) |
| Agente / vendedor | **produtor** (Segfy, Quiver); **vendedor** (Agger) | A / M | Segfy "produtor de repasse"; Agger "VENDEDORES" | "Produtor" em comissão e meta. "Atendente" no resto (F0b) |
| Empresa parceira | seguradora, **companhia**, "Cia." | A | Segfy "por companhia"; Agger "Cia. Seguradora" | "Seguradora" na tela. "Cia." só onde falta espaço |
| Pagamento / fatura | **parcela** (paga, não paga, atrasada); fatura nos seguros de vida | A | Segfy, Agger "Vencimento de parcela", "Faturas"; Teleport | Decidido ("Parcelas") |
| Inadimplente | **parcela atrasada / em atraso** | A | Segfy "Parcelas Atrasadas"; Agger "parcela em atraso" | Nunca "inadimplente" na tela. GetApp usa "inadimplência" para a Segfy; é termo de relatório |
| Comissão | comissão **recebida / a receber / a pagar**, previsão, **repasse** | A | Segfy, Agger, Teleport | Só no relatório. Comissão não é assunto com o cliente (F0b) |
| Alteração | **endosso** (com ou sem movimento de prêmio, cancelamento, reabilitação, prorrogação de vigência) | A | Agger; Segfy "Endossos" | Etiqueta e Central. Com o cliente, "alteração na apólice" |
| Ocorrência | **sinistro**, **aviso de sinistro**; terceiro = "participante" | A | Agger, Segfy, Quiver, SUSEP (via busca) | Decidido ("Sinistros"). "Terceiro" na Central, nunca "participante" |
| Validade | **vigência** (inicial e final), vencimento | A | Agger, Segfy, Agendor ("data de renovação") | "Vencimento" com o cliente; "vigência" na ficha |
| Cliente importante | Cliente Bronze / Prata / Ouro (Agger); "Cliente VIP" (Teleport) | M / M | Agger Manual; Teleport | Fora do pacote: é etiqueta da conta |
| Vistoria | **vistoria prévia** (auto), vistoria digital por link | A | Tokio, Mapfre, Porto, Previsul (via busca) | Etiqueta e pronto de WhatsApp (seção 5) |
| Assinatura | assinatura eletrônica da proposta | A | Agger Signner, Teleport, Segfy Assina | Central |
| Aniversário | **aniversariantes**, licenciamento, CNH vencendo | A | Agger (relatórios); Segfy (F0) | Público de campanha (F0b confirmado) |

**Conflito novo.** "Beneficiário" aparece em dois sentidos:
- no Agger, como seção da fatura (seguro de vida: quem recebe);
- na saúde, como a pessoa coberta pelo plano.

Isso reforça a regra da F0: "beneficiário" fica só na camada saúde.

---

## 4. Etapas de funil

**Vendas.** Fica como está, por decisão do Rodrigo: Novo contato · Em conversa
· Proposta enviada · Negociação · Fechado, com o resultado "Seguro ativo / Não
fechou".

A pesquisa nova **não muda** isso. Ela confirma que o mercado fecha a venda na
apólice emitida (Segura, Agger "Ganho" ligado à emissão), e isso combina com
"Seguro ativo".

### 4.1 Renovação: confirmar o que foi decidido

| Posição (categoria) | Decidido | Evidência nova | Frequência agora | Recomendação |
|---|---|---|---|---|
| E1 (novo) | A renovar | Segfy "Apólices pendentes de renovação", "Renovações dos próximos 30 dias"; Agger "SAIR EM RENOVAÇÃO" | A (antes M) | **Manter** |
| E2 (andamento) | Cotando a renovação | Agger **"RENOVANDO"**; SocialHub "re-cotar"; Agger blog "recotar" | M | **Manter.** Alternativa literal e mais curta: "Renovando" (Agger). A frase de hoje diz o que a equipe faz; "Renovando" é palavra de sistema. Decisão do Rodrigo |
| E3 (espera, pausa o prazo) | Esperando o cliente | Segfy HFy **"aguardando resposta"**; Agendor e SocialHub (cliente decide) | M (antes M fraco) | **Manter.** Espera o cliente de fato, então a pausa do prazo está certa |
| E4 (resolvido) | Renovada | Agger **"RENOVADO"**; Segfy "renovação" ligada à apólice mãe | A | **Manter** |
| Saída (cancelado) | Não renovou | Segfy **"não renovada"**; Agger "SEGURO PERDIDO" / "PERDIDO"; F0 Quiver "não renovado" | A | **Manter** |

Achados para o Multifunnel (código, não pacote):
- O Agger, ao marcar "SEGURO PERDIDO", oferece **criar prospecção** para o
  próximo ano. Fica como ideia de automação: o card que sai em "Não renovou" vira
  lembrete de cotação na próxima vigência. Hoje isso não é etapa.
- A Renovação começa de 30 a 60 dias antes do vencimento:
  - Agendor: "1 ou 2 meses antes";
  - Segfy: tela "próximos 30 dias";
  - SocialHub e Aurora: D-30.
- **A antecedência continua vindo da configuração da conta, nunca do texto**
  (regra da F0).

### 4.2 Sinistros: confirmar o que foi decidido

| Posição | Decidido | Evidência nova | Frequência agora | Recomendação |
|---|---|---|---|---|
| E1 | Aviso recebido | "aviso de sinistro" (SUSEP, Porto, via busca); Agger "WHATSAPP SINISTRO" para o cliente avisar | A | **Manter** |
| E2 | Em análise | AiSensy "em análise" (fornecedor); prazo de análise da seguradora "a partir do recebimento de toda a documentação" (via busca, sem norma lida) | A (F0) | **Manter.** É a espera pela seguradora e conta no prazo, o mesmo critério da saúde |
| E3 (espera) | Esperando documentos | Agger: "B.O., Orçamentos" anexados; SocialHub e AiSensy: fotos, laudos, BO | M | **Manter.** Aqui se espera o cliente, então a pausa está certa |
| E4 | Encerrado | AiSensy "liquidada"; F0 AIG, Quiver | A | **Manter** |
| Saída | Recusado | F0 Quiver | M | **Manter.** Negado sai como Resolvido, com motivo (decidido) |

Lacuna que continua: nenhuma ferramenta de corretora publica a lista de status
do sinistro, então estas etapas seguem por dedução do processo. Quem pode
validar é a conta 18, olhando só a estrutura.

### 4.3 Parcelas: confirmar o que foi decidido

| Posição | Decidido | Evidência nova | Frequência agora | Recomendação |
|---|---|---|---|---|
| E1 | A vencer | Agger "RELATÓRIO DE VENCIMENTO DE PARCELA"; Teleport "Relatório de Parcelas" | M | **Manter** |
| E2 | Atrasada | Segfy **"Parcelas Atrasadas"** (título lido nesta rodada); Agger "parcela em atraso" | **A** (a ressalva de "não reaberta" cai) | **Manter** |
| E3 (espera) | Prometeu pagar | **Nenhuma fonte de novo** | B | Manter, como decidido (é nome da base). Alternativa sem fonte, para o Rodrigo: "Esperando o pagamento" |
| E4 | Paga | Segfy **"paga"** / "não paga" | M (agora com leitura direta) | **Manter** |
| Saída (cancelado) | — (sem rótulo próprio) | Agger "CANCELAMENTO DE APÓLICE"; atraso longo pode cancelar o seguro (Procon-GO, Idec, via busca) | M | **Sugestão:** rótulo de saída "Seguro cancelado" (`outcome_labels`), sem o sentido de "perdido". Texto de pacote, sem código, se o Multifunnel confirmar que a saída aceita rótulo por modelo |

Atenção para a Central e para o agente: um sinistro durante o atraso pode ser
indenizado com desconto da parcela, e o prazo de tolerância varia por apólice
(Procon-GO, Idec). Por isso:
- o agente **nunca** diz que o seguro está cancelado ou que está coberto;
- ele encaminha a pessoa para a apólice ou para a equipe (regra da F0 "não
  dizer que está coberto sem a apólice").

### 4.4 Jornada real do corretor, de ponta a ponta

Juntando as fontes:
- Segfy e Agger: o que a ferramenta mostra.
- Sompo e Porto: o que a seguradora pede.
- CQCS: a validade da cotação.
- Agendor e SocialHub: o que acontece no WhatsApp.

1. **Prospecção ou contato** → cliente novo, ou cliente com o seguro perto de
   vencer.
2. **Cotação (multicálculo)** → um formulário só para várias seguradoras. O
   comparativo vai por e-mail ou WhatsApp (Aggilizador).
   - A cotação vale pouco tempo: o CDC, segundo a CQCS, dá 10 dias quando a
     proposta não fixa prazo.
   - **O agente não promete preço depois de dias.**
3. **Aceite do cliente** ("aceitas pelo cliente", Segfy).
4. **Proposta: efetivar e transmitir** à seguradora, com proposta assinada.
   Assinatura eletrônica em Agger, Teleport e Segfy. Vistoria prévia no auto.
5. **Análise da seguradora** → pendência, emitida ou recusada (Porto). A tela
   da Segfy é "pendentes de emissão".
6. **Apólice emitida** → envio da apólice e do cartão de assistência
   (Agger: cartão via WhatsApp).
7. **Durante a vigência:**
   - parcelas (a vencer, atrasada, paga);
   - endosso (troca de carro, de endereço ou de condutor);
   - sinistro (aviso, documentos, análise, encerramento).
8. **Renovação** → de 30 a 60 dias antes. O desfecho é renovada, ou não renovada,
   que vira prospecção para o ano seguinte.

### 4.5 Diferenças por ramo

Isto vale para placeholders, Central e orientação do agente. Não é etapa nova.

| Ramo | O que muda no trabalho | Frequência | Fonte |
|---|---|---|---|
| Auto | Vistoria prévia (presencial, digital por link de SMS ou WhatsApp, ou acompanhada por vídeo), classe de bônus, CEP de pernoite, condutor, placa. Sinistro: BO (obrigatório em roubo ou furto), CNH, CRLV, fotos, dados do terceiro. Agger tem relatório de licenciamento | A | Tokio, Mapfre e Liberty (via busca); idinheiro e MAG (sinistro); F0 |
| Residencial | Vistoria rara e, quando há, digital (fotos tiradas pelo cliente); assistências 24h pesam na venda | M | Previsul (2020, via busca) |
| Vida | **DPS** (declaração pessoal de saúde) na contratação, às vezes com exames; "simulação" em vez de cotação na insurtech; fatura mensal; o beneficiário é quem recebe | A | MAG, Icatu (DPS); Agger "FATURAS > BENEFICIÁRIOS"; F0 Azos |
| Empresarial e RC | Vistoria de risco, CNPJ, cliente é pessoa jurídica (a Segfy filtra a produção por "pessoa jurídica"). RC profissional depende da atividade | M | Segfy (relatório PJ); Previsul. **RC: sem fonte de tela nesta rodada** |
| Viagem | Emissão rápida, sem renovação no sentido anual; sinistro é assistência no exterior | B | Nenhuma fonte de tela. A F0 tirou o vocabulário de viagem do pacote. **Não confirmado** |
| Saúde | Camada própria (`saude_beneficios`): operadora, contrato, implantação, beneficiário | A | F0 Ikaros, conta 43 |

**Consequência para o pacote corretora:** os exemplos de tela citam o ramo de
forma genérica, como "seguro auto", "seguro residencial" e "trocar o carro na
apólice", e nunca uma marca (F0b). O agente pergunta o ramo antes de pedir o
documento.

---

## 5. Prontos de WhatsApp sugeridos

**Regra da Meta** (developers.facebook.com, "new template guidelines"):

- **UTILITY** precisa ser "non-promotional", "specific to or requested by the
  user" ou essencial para ele. Lembrete de pagamento é exemplo de UTILITY.
- Mensagem de conta ou pedido "should not promote, recommend, upsell, or
  cross-sell products; include offers; or **attempt to secure renewals**".
- Utilidade misturada com oferta vira MARKETING, e a Meta pode reclassificar
  depois.
- **Consequência:** todo pronto que **puxa a renovação** é MARKETING, mesmo
  quando o texto é um aviso. Isso combina com a regra da memória "fora da
  janela: reengajamento = MARKETING".

**Restrições do chat2you:**
- Hoje a galeria tem `boas_vindas`, `lembrete`, `pesquisa`, `promocao`,
  `cobranca` e `retomar`. `aviso` corresponde a UTILITY e `divulgacao` a MARKETING.
- Os campos que existem são `nome_cliente`, `nome_empresa`, `data`, `horario`,
  `valor`, `desconto`, `link` e `codigo`. **Não há campo de seguradora, ramo
  nem número da apólice**: criar exige código, e o dono é Modelos WhatsApp.
- Os prontos de sistema (cobrança e agendamento) **não entram** no pacote
  (combinado). Os da galeria entram como **variante de texto da corretora**,
  com o mesmo objetivo e a mesma categoria, e o spec "todos os prontos" roda
  `regraEstrutural.js` no pacote.
- **Golpe do boleto.** "Os meios mais usados são boletos falsos e
  transferências via Pix" e "A seguradora não faz cobrança por WhatsApp"
  (Revista Apólice, 21/07/2025). O pronto de parcela, portanto:
  - não manda boleto no topo (já é a regra do #1380);
  - lembra o cliente de conferir quem cobra.

Os textos abaixo são **rascunho nosso**, sem fonte literal: nenhuma ferramenta
publica os seus. Os campos vão escritos [assim], e as regras de voz da F0 valem
(sem travessão, sem emoji, sem "Perfeito!").

| # | Pronto | Objetivo | Base na galeria | Categoria | Rascunho do texto (corretora) | Botões | Fonte do uso |
|---|---|---|---|---|---|---|---|
| 1 | **Renovação chegando** | Abrir a conversa de renovação antes do vencimento | `retomar` ou novo | **MARKETING** (puxa a renovação) | "Olá, [nome_cliente]. O seu seguro vence em [data]. Quer que a gente cote a renovação para você?" | Quero cotar · Falar com a equipe | Agendor, Segfy (30 dias), SocialHub, Aurora (D-30) |
| 2 | **Parcela a vencer** | Lembrar o pagamento | `cobranca` | **UTILITY** (lembrete de pagamento, exemplo da Meta) | "Olá, [nome_cliente]. A parcela do seu seguro vence em [data], no valor de [valor]. Antes de pagar, confira se o boleto está no nome da seguradora. Se precisar, mandamos a segunda via por aqui." | Segunda via · Já paguei | Segfy "Parcelas do Segurado"; Agger "vencimento de parcela"; Revista Apólice (golpe) |
| 3 | **Parcela atrasada** | Evitar o cancelamento | `cobranca` | **UTILITY** | "Olá, [nome_cliente]. Não encontramos o pagamento da parcela do seu seguro que venceu em [data]. Para o seguro continuar valendo, fale com a gente por aqui." | Segunda via · Já paguei | Segfy "Parcelas Atrasadas"; Procon-GO e Idec (o atraso afeta a cobertura) |
| 4 | **Vistoria marcada** | Confirmar a vistoria prévia | `lembrete` | **UTILITY** (pedida pelo cliente na contratação) | "Olá, [nome_cliente]. A vistoria do seu seguro está marcada para [data], às [horario]. Pode confirmar?" | Confirmo · Remarcar | Tokio, Mapfre e Dekra (agendamento); Multiclass (o corretor agenda) |
| 5 | **Vistoria por link** | Mandar o link da vistoria digital | `lembrete` ou novo | **UTILITY** | "Olá, [nome_cliente]. Para continuar a contratação do seu seguro, falta a vistoria. É só abrir o link e seguir os passos: [link]" | Abrir link · Tenho dúvida | Tokio (link por SMS ou WhatsApp); Previsul (fotos) |
| 6 | **Documentos do sinistro** | Pedir o que falta depois do aviso | novo | **UTILITY** (resposta a um aviso do cliente) | "Olá, [nome_cliente]. Para a seguradora analisar o seu sinistro, faltam alguns documentos. Pode mandar por aqui quando tiver?" | Mandar agora · Tenho dúvida | Agger ("B.O., Orçamentos"); SocialHub; MAG e idinheiro (lista por ramo). **A lista não vai no texto**: varia por seguradora e por ramo, e o agente pergunta |
| 7 | **Andamento do sinistro** | Avisar que mudou a situação | novo | **UTILITY** | "Olá, [nome_cliente]. Temos novidade sobre o seu sinistro. Podemos falar por aqui?" | Pode falar · Ligar depois | SocialHub ("proactive updates"); AiSensy |
| 8 | **Seguro emitido** | Avisar que a apólice saiu | novo | **UTILITY** (confirmação da compra) | "Olá, [nome_cliente]. Seu seguro foi emitido. Vamos mandar a apólice e o contato da assistência por aqui." | Recebi · Tenho dúvida | Segura (apólice emitida); Agger (cartão de assistência por WhatsApp) |
| 9 | **Falta assinar a proposta** | Destravar a emissão | novo | **UTILITY** | "Olá, [nome_cliente]. Para a seguradora emitir o seu seguro, falta assinar a proposta: [link]" | Abrir link · Tenho dúvida | Agger Signner, Teleport e Segfy Assina; Sompo (proposta assinada) |
| 10 | **Cotação enviada, sem resposta** | Retomar a cotação parada | `retomar` | **MARKETING** | "Olá, [nome_cliente]. Mandamos a cotação do seu seguro. Ficou alguma dúvida?" | Quero continuar | Segfy "aguardando resposta"; CQCS (a cotação vence) |
| 11 | **Aniversário** | Relacionamento | `boas_vindas` | **MARKETING** | "Feliz aniversário, [nome_cliente]! Conte com a [nome_empresa] sempre que precisar." | Obrigado | Agger (relatório de aniversariante; e-mail de aniversário, ?p=745) |
| 12 | **Oferecer outro seguro** | Vender mais para quem já é cliente | `promocao` | **MARKETING** | "Olá, [nome_cliente]. Você já tem o seguro do carro com a gente. Quer conhecer o seguro para a sua casa?" | Quero saber · Agora não | F0b (cross-sell; Sincor, fraco) |
| 13 | **Pesquisa depois do sinistro** | Medir a satisfação | `pesquisa` | **UTILITY**, como o `pesquisa` de hoje (a Meta pode reclassificar) | "Olá, [nome_cliente]. Seu sinistro foi encerrado. Como foi o nosso atendimento?" | Ótimo · Bom · Pode melhorar | Agger ?p=745 (NPS no pós-venda) |

**O que exige código, e não só pacote** (dono: Modelos WhatsApp):
- Prontos novos, de 4 a 9 e o 13, se a galeria não puder ganhar objetivo por
  segmento.
- Campos "seguradora" e "ramo".
- O pronto 12 precisa do ramo, que hoje não existe como campo: sem ele, o texto
  fica genérico ("conhecer outros seguros").

**O que fica fora:**
- número de dias no texto: a antecedência vem da configuração;
- nome de seguradora fixo;
- lista de documentos no modelo.

---

## 6. KPIs

O que o mercado mostra, comparado com o que o painel de CRM do chat2you já tem
(resultado de venda, ver o README).

| KPI | Nome no mercado | Frequência | Fonte | No chat2you |
|---|---|---|---|---|
| **Produção do mês** por produtor, ramo e seguradora | "Relatório de produção", "Produção do mês… por corretor e por ramo" | A | Segfy, Agger, Agendor | O painel soma o "valor fechado". O **nome** "Produção" entra no pacote. **Por ramo ou seguradora exige código** (sem campo) |
| **Seguros fechados** e **taxa de fechamento** | "Taxa de conversão de vendas", "Ganho", "Relatório de fechamento" | A | Agger ?p=532, Agger Manual, Quiver (conversão de leads) | **Já decidido:** "Seguros fechados", "Taxa de fechamento" |
| **Taxa de renovação** | "Taxa de renovação de apólices" | A (o nome) / sem fórmula no Brasil | Agger ?p=532; F0 AG-KPI | **Exige código:** resultado do modelo Renovação (Renovada ÷ Renovada + Não renovou). Mostrar o número **sem fórmula na tela** (F0) |
| **Renovações a vencer** (hoje, próximos 30 dias) | "Renovações do dia de hoje", "Renovações dos próximos 30 dias", "Relatório de renovação" | A | Segfy, Agger | Contagem de cards na E1 do funil Renovação. A janela por data exige o vencimento como prazo (já adiado) |
| **Propostas pendentes de emissão** | "Propostas pendentes de emissão", "Apólices pendentes", "Pendência de Emissão" | A | Segfy, Agger | Não se aplica ao Vendas de hoje, que não tem a etapa. Fica como ideia de relatório |
| **Parcelas atrasadas** | "Parcelas Atrasadas", "parcela em atraso", inadimplência | A | Segfy, Agger, GetApp (Segfy) | Contagem de cards na E2 do funil Parcelas |
| **Comissão a receber / recebida / previsão** | "comissões não recebidas", "a pagar", "previsão de pagamento de comissão" | A | Segfy, Agger | **Fora do escopo:** o chat2you não tem financeiro de comissão. Não prometer na tela |
| **Meta por seguradora ou por produtor** | "Relatório de metas: seguradoras ou vendedores", meta pelo "prêmio líquido" | M | Agger | Já existe "Meta mensal" no funil. O nome "de produção" vem da F0b |
| **Sinistros abertos** | "Relatório de sinistro", "Extrato de sinistros" | A | Agger, Segfy | Contagem do funil Sinistros sem resultado |
| **Tempo de resposta** | "Tempo de resposta ao cliente", "tempo de primeiro contato" | A | Agger ?p=532, RD Station | Já existe no painel do Chatwoot (relatórios de conversa). Sem troca de nome |
| **Satisfação** | "Índice de satisfação do cliente", NPS | A | Agger ?p=532, Agger ?p=745, Quiver | CSAT do Chatwoot. Sem troca |

**Recomendação para o painel da corretora**, sem código novo:
- títulos "Produção do mês", "Seguros fechados" e "Taxa de fechamento";
- nos funis de Atender, as contagens por etapa já respondem "renovações a
  vencer", "parcelas atrasadas" e "sinistros abertos".

Com código, nesta ordem de valor para o corretor:
1. taxa de renovação;
2. produção por ramo e por seguradora (precisa do campo ramo);
3. renovações por data de vencimento.

Comissão fica fora.

---

## 7. Fontes

Fontes lidas nesta rodada (18/10/2026):
- Segfy: https://www.segfy.com · https://ajuda.segfy.com/knowledge · https://ajuda.segfy.com/knowledge/segurados-propostas-e-ap%C3%B3lices · https://ajuda.segfy.com/knowledge/parcelas-do-segurado-tarefas-e-sinistros?hsLang=pt-br · https://ajuda.segfy.com/knowledge/relat%C3%B3rios?hsLang=pt-br · https://ajuda.segfy.com/knowledge/cota%C3%A7%C3%B5es-hfy-e-painel-de-or%C3%A7amentos?hsLang=pt-br · https://ajuda.segfy.com/knowledge/propostas-e-ap%C3%B3lices-a%C3%A7%C3%B5es-manuais · (a página https://www.segfy.com/segfy-mensagem deu 404)
- Agger: https://aggerinstala.blob.core.windows.net/novogestor/MANUAL.pdf (Manual do Gestor, atualizado em 22/11/2021, lido inteiro em texto) · https://www.agger.com.br/blog/diferenca-sistema-de-gestao-multicalculo-e-crm-2 · https://www.agger.com.br/?p=532 · https://www.agger.com.br/?p=598 · https://www.agger.com.br/?p=745 · https://www.agger.com.br/?p=883
- Teleport: https://www.cqcs.com.br/noticia/teleport-ganha-novas-funcionalidades-para-atender-demandas-de-corretoras/
- Quiver: https://cqcs.com.br/noticia/como-maximizar-as-vendas-dos-corretores-de-seguros-atraves-do-funil-de-vendas/ (a ajuda http://helponline.quiverpro.net.br deu 503)
- Segura: https://revistaapolice.com.br/2026/08/segura-integra-ia-ao-funil-de-vendas-dos-corretores/ · https://cqcs.com.br/noticia/segura-leva-ia-operacional-para-o-whatsapp-dos-corretores-de-seguros/
- CRMs genéricos: https://agendor.com.br/clientes/sistema-crm-corretoras-seguros · https://www.agendor.com.br/blog/faz-sentido-usar-crm-em-uma-corretora-de-seguros/ · https://www.rdstation.com/produtos/crm/solucoes/para-corretoras-de-seguros/ · https://www.ploomes.com/en/industries/service-copy · https://www.pipedrive.com/pt/industries/insurance-crm
- WhatsApp: https://developers.facebook.com/docs/whatsapp/updates-to-pricing/new-template-guidelines · https://m.aisensy.com/blog/pt/whatsapp-para-corretoras-de-seguros/ · https://www.aurorainbox.com/pt/2026/05/18/chatbot-corretores-seguros-whatsapp/ · https://www.socialhub.pro/blog/whatsapp-corretora-seguros-enterprise-cotacao-renovacao-sinistro/
- Imprensa e jurídico: https://revistaapolice.com.br/?p=122763 (golpes, 21/07/2025) · https://cqcs.com.br/noticia/corretor-fique-atento-ao-prazo-de-validade-da-cotacao/

Fontes vistas só no resumo da busca, sem abrir:
- Infocap: https://baguete.com.br/public/noticias/agger-compra-infocap e https://revistaapolice.com.br/?p=87474
- Porto, status de transmissão: https://wwws.portoseguro.com.br/docs/calculo/ManualPortoPrintWEB.pdf
- Sompo: https://sompo.com.br/wp-content/uploads/2020/05/guia-rapido-transporte.pdf
- Parcela atrasada: https://goias.gov.br/procon/atraso-no-pagamento-do-seguro-nao-significa-perda-da-cobertura/ e https://idec.org.br/print/24605
- Sinistro auto: https://www.idinheiro.com.br/seguros/auto/como-acionar-o-seguro-auto/ e https://blog.mag.com.br/sinistro/
- DPS: https://blog.mag.com.br/declaracao-pessoal-de-saude/
- Vistoria: https://revistaapolice.com.br/2024/08/mapfre-adota-vistoria-digital-acompanhada-para-seguro-auto/ e https://cqcs.com.br/noticia/previsul-lanca-vistoria-online-para-seguros-residencial-e-empresarial/
- Segfy no GetApp: https://www.getapp.com/all-software/a/segfy-1/

Da F0/F0b, mantidas: a lista do anexo do comentário 6170730386 da #1545
(SG-*, QV-*, AG-*, AGD, SEGURA, SINCOR, BONUS).

## 8. Lacunas

- **Nenhum texto de modelo de WhatsApp publicado por ferramenta de
  corretora.** Os rascunhos da seção 5 são nossos. Antes de entrarem na
  galeria, passam pelo dono de Modelos WhatsApp e pela regra estrutural.
- **Status de sinistro na corretora:** nenhuma ferramenta publica a lista.
- **Bitrix24, Kommo, Gestor Seguros, SIS e Zeeway:** nada achado.
- **Ajuda da Quiver** fora do ar nesta rodada (503).
- **"Prometeu pagar"** segue sem fonte.
- **Prazos legais** (análise de sinistro, emissão, tolerância de parcela) foram
  vistos só em blog ou trecho de busca. Ler a norma da SUSEP antes de citar na
  Central. Eles não entram no texto do agente.
- **Validar com a conta 18** (Placement, só a estrutura: funis, etapas e
  etiquetas), como pede a #1802.
