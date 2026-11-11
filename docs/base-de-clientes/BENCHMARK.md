# Benchmark — carteira, ficha e renovação para corretoras

Épico autonom-ia2/chat#1240. Pesquisa de 11/11/2026, só em material público (sites, centrais de ajuda, imprensa do
setor, Reclame Aqui). Nenhum cadastro, login ou formulário. O que não foi achado está escrito como "não achei".
Frases marcadas **inferência** são leitura nossa, não fato visto na página.

Foram duas rodadas. A primeira leu sites e imprensa e ficou rasa. A segunda (seção 8) abriu centrais de ajuda, notas de
versão, o manual do Agger Gestor, os termos de uso e a política de privacidade da Segura, e testou dez hipóteses de
lacuna.

Limites que continuam: nenhum produto foi usado por dentro (não temos login em nenhum); nenhum vídeo de demonstração
pôde ser lido; o Reclame Aqui bloqueou a abertura das páginas, então as queixas vêm de títulos e trechos de busca; não
há voz independente de corretor sobre Segura, Flui e Ikaros. "Não achei" não prova "não existe": fornecedor brasileiro
publica mais propaganda do que documentação.

## 1. Quem faz o quê

| Capacidade | Segura | Flui | Ikaros | Segfy | Quiver | Agger | Teleport | CRMSeguros / TW / CRM Corretor |
|---|---|---|---|---|---|---|---|---|
| Foco | seguros, via seguradora parceira | benefícios coletivos | saúde e CRM | gestão | gestão | gestão + multicálculo | gestão + multicálculo | CRM com WhatsApp |
| Planilha | sim | layout de vidas | sim, "em até 7 dias" | sim | não achei | não achei | não achei | não achei |
| PDF de apólice | sim, com IA | não achei | não achei | sim, seguradoras reconhecidas | sim, por seguradora | sim | não achei | importa documentos (CRMSeguros) |
| Direto das seguradoras | parceiras | operadoras (plano Pro) | não achei | 26 integradas | "mais de 34" | robôs de importação | sim (plano Enterprise) | depende de terceiros (TW) |
| Ficha com apólices e linha do tempo | diz ter "visão 360°"; tela não mostrada | não achei | não achei | não achei | histórico de conversa no cadastro (Quiver Zap) | ficha por cliente, sem linha do tempo única | não achei | TW alega histórico único |
| Aviso de renovação | sim, no WhatsApp do corretor | sim, aviso e BI | não achei | filtro de pendentes | e-mail e SMS | fim de vigência e última parcela | distribui por produtor | 30, 15 e 7 dias |
| Funil de renovação | sim | não | não | não achei | não achei | não achei | não achei | sim |
| Cotação na renovação | sim, com aprovação do corretor | não | não | multicálculo à parte | multicálculo à parte | multicálculo | multicálculo | não |
| WhatsApp oficial junto da carteira | sim (assinatura à parte) | não achei | não confirmado | central à parte | módulo à parte, não confirmado | não achei | não achei | sim |
| API pública para ler a carteira | não achei | não achei | não achei | não achei | não achei | não achei | não achei | TW tem webhooks |

## 2. Padrões que o corretor já espera

- Aviso de renovação em **30, 15 e 7 dias**. 30 dias é o mínimo citado; 60 é folga. (CRM Corretor, blog da TEx)
- Estados de apólice: vigente, pendente de renovação, renovada, não renovada. (Segfy)
- A apólice nova se liga à anterior por **segurado (CPF/CNPJ), ramo, item (placa, endereço) e vigência**, não pelo
  número: na renovação o número e até a seguradora mudam. (Segfy)
- Vocabulário: segurado, apólice, proposta, endosso, parcela, sinistro, comissão, vigência, ramo.
- Importa-se a proposta e depois a apólice; as duas viram um cadastro só. (Segfy, Quiver)
- A IA não promete cobertura nem franquia; valor só sai depois de uma pessoa conferir. (Segura, TW) — **inferência**
  de que isso é padrão.

## 3. Onde todos falham (nosso espaço)

1. **Ninguém mostra como é a ficha do cliente com os seguros e a história dele.** A Segura diz ter "visão 360°" e o
   Agger tem ficha por cliente, mas nenhuma fonte mostra uma linha do tempo única (conversa, proposta, renovação). É a
   ficha nova deste épico.
2. **A importação cobre "as principais seguradoras".** Fora delas, cadastro à mão (Segfy). Ler o PDF de qualquer
   seguradora e dizer o que não entendeu é diferencial.
3. **Renovação é relatório, não trabalho andando.** No Segfy é um filtro com vínculo manual. Funil com cotação e
   mensagem só na Segura, que depende de seguradora parceira e tem lista de espera.
4. **WhatsApp oficial é produto separado.** Quem tem carteira não tem conversa; quem tem conversa não tem carteira.
   — **inferência**
5. **Telas densas, por módulo.** Queixas repetidas no Reclame Aqui: sistema confuso, lento, suporte, multa de
   cancelamento (Segfy, Quiver, Agger). Falta fluxo guiado por tarefa ("5 renovações esta semana").
6. **Sem API pública.** Ler a carteira de fora exige planilha, PDF ou o login da corretora.
7. **Desfazer importação é fraco** nos CRMs gerais: 48 h no Pipedrive, só Super Admin no HubSpot, inexistente no
   Attio.

## 4. O que trazemos (e de quem)

| # | Ideia | De quem | Onde entra |
|---|---|---|---|
| 1 | Três portas na mesma tela: planilha, PDF, integração | Segura | E3, E6, E7 (já previsto) |
| 2 | Renovação nasce como card | Segura, CRMSeguros, TW | E5 (já previsto) |
| 3 | Proposta só sai depois de uma pessoa conferir; automático é escolha | Segura, TW | E8 |
| 4 | "A vencer" e "Venceu e não renovou" como números do dia | Flui | E4, E5 |
| 5 | Grupos por urgência: vencido, 7 dias, 30 dias, 90 dias | CRM Corretor | E4 |
| 6 | Mensagens em 30, 15 e 7 dias na receita pronta | padrão do mercado | E5 |
| 7 | "O que mudou" lado a lado quando o dado chega de novo | HawkSoft (Download Compare) | E4, E6, E7 |
| 8 | Aviso "subiu X% em relação ao ano passado" | EZLynx (Retention Center) | E8 |
| 9 | Importação continua se fechar a tela, com histórico | Attio | E3 |
| 10 | Erro marcado e corrigido na própria tela do Conferir | Folk | E3 |
| 11 | Prévia do que o desfazer vai tirar | HubSpot | E3 |
| 12 | Na renovação, perguntar só "o que mudou?" | Indio | E8 |
| 13 | Ligar a apólice nova à anterior por segurado, ramo, item e vigência | Segfy | E5 |
| 14 | Uma pergunta por tela, "Continuar" e "Confira" | GOV.UK | régua da banca |
| 15 | Quem cuida da renovação segue a regra de atribuição do funil | Teleport | E5 |

## 5. O que deixamos de fora, de propósito

- Comissão, parcelas, sinistro, multicálculo próprio: é o terreno dos sistemas de gestão. Não vamos brigar ali.
- App e portal do segurado.
- Aviso de renovação no WhatsApp pessoal do corretor (Segura): fica para depois; o aviso sai no sino e na frase do dia.
- Recurso travado em plano caro (armadilha vista no AgencyZoom): só a cotação de renovação tem chave própria.

## 6. Armadilhas vistas

- Ler só a primeira página do PDF: limites e cláusulas ficam em outras páginas. Campo sem certeza vai aberto.
- Importar sem chave única e duplicar pessoas. Nossa chave: CPF/CNPJ, depois telefone.
- Planilha com várias abas importada de uma vez.
- Janela de desfazer curta e mal explicada.
- Barra de progresso e controles "espertos" demais para quem lê devagar.

## 7. Fontes

Segura: segura.ai · segura.ai/tecnologia · revistacobertura.com.br (sistema de gestão nativo de IA; IA operacional no
WhatsApp) · acontece.ens.edu.br (IA de vendas).
Flui: useflui.com.br · useflui.com.br/crm-para-corretora-de-seguros.
Ikaros: ikaros.com.br · /crm-para-corretores-de-seguros · /sistema-para-corretoras.
Segfy: segfy.com · ajuda.segfy.com (importação automatizada; apólices pendentes de renovação).
Quiver: solucoesparacorretoras.quiver.net.br (Digitação Zero) · helponline.novo.quiverpro.net.br (notas de versão).
Agger: agger.com.br/produtos/gestor · agger.com.br/blog/sistema-agger · revistaapolice.com.br (compra da Infocap).
Teleport: textecnologia.com.br/planos · textecnologia.com.br/blog (renovação de seguro).
Novos: crmseguros.com.br · twsolutions.com.br/tw-seguros · crm-corretor.top.
Internacionais: support.agencyzoom.com (Onboarding and Retain automation) · hawksoft.com (carrier downloads) ·
ezlynx.com (automated renewal quoting) · useindio.com · usecanopy.com.
CRMs: knowledge.hubspot.com (saved views; restore CRM changes) · intercom.help/pipedrive (revert an import) ·
attio.com/help (CSV imports) · help.folk.app (file imports).
Leitores leigos: nngroup.com (writing for lower-literacy users) · design-system.service.gov.uk (question pages; check
answers).

## 8. Segunda rodada (11/11/2026, tarde)

### 8.1 Segura e Helena, mais fundo

- **Para o corretor:** a Helena lê apólices, interpreta cláusulas e responde sobre "oportunidades na carteira e perfis
  de clientes", no portal e no WhatsApp. Não achamos um exemplo literal de pergunta ("quem vence este mês").
- **Para o segurado:** conversa pelo WhatsApp com base na apólice. O corretor escolhe quais clientes recebem resposta
  automática; nos outros, ela sugere e o corretor envia. Se envia o arquivo da apólice: não achei.
- **Proposta:** "somente é enviada após revisão e aprovação do corretor". Não há modo automático descrito.
- **Carteira:** planilha, PDF ou importação das seguradoras parceiras (15 na página inicial). O acesso completo exige
  que a Segura seja a corretora cadastrada na seguradora. — é a maior amarra do modelo.
- **Negócio:** grátis para o corretor; a seguradora paga sobre a venda. O módulo de WhatsApp é assinatura à parte, sem
  valor público. Número de corretores varia entre fontes (3 mil, 4 mil, 9 mil). Rodada semente de R$ 45 milhões.
- **Limites dos próprios termos:** a IA pode errar e a responsabilidade pela resposta é do corretor.

### 8.2 Como é uma renovação nos sistemas de gestão (documentação de uso)

- **Segfy:** relatório de renovação em PDF ou Excel, depois o corretor "pode começar a preparar cotações". Renovação
  manual cria um registro novo e o corretor digita. Para algumas seguradoras a cotação de renovação sai só no portal
  delas. Nenhum artigo mostra a mensagem indo ao segurado.
- **Agger:** abrir o contrato, "Renovar apólice", revisar, gravar. Ao importar o PDF novo com os campos-chave iguais, o
  vencido vira "renovado". "Seguro perdido" vira prospecção. WhatsApp é link para o WhatsApp Web, não API oficial.
- **Quiver:** renovação automática só para auto vindo do multicálculo do ano anterior, rodando à noite. Distribuição
  de renovações entre produtores e "renovações não tratadas" com Perder/Agendar. Quiver Zap é pacote à parte.
- **Em todos:** motivo de não renovação não é campo; não há relatório de retenção; não há boas-vindas automáticas;
  cobrança de parcela atrasada é relatório ou alerta alegado, sem régua mostrada.
- **Queixas:** são de contrato e suporte (multa, cobrança, lentidão), não de renovação. Não temos voz de usuário sobre
  renovação.

### 8.3 Novos nomes achados

- **SegZap:** lê PDF de apólice, responde sobre cobertura e lista vencimentos de 30 dias, para o corretor. Barato.
- **Segia:** lista quase tudo (leitura de apólice, sinistro, boleto, família, indicação), só pelos nomes. Promessa não
  verificada.

### 8.4 Dez hipóteses de lacuna

| # | Hipótese | Quem faz | Veredito | Certeza |
|---|---|---|---|---|
| H1 | Lead manda a apólice que já tem (de outra corretora); o sistema guarda o vencimento e chama na hora | Canopy Connect, nos EUA | lacuna no Brasil | média |
| H2 | Apólice explicada ao segurado em palavras simples, logo após a emissão | Helena e SegZap respondem quando perguntam; ninguém envia sozinho | parcial | média |
| H3 | Segurado confirma o que mudou antes da renovação, no WhatsApp | não achei | lacuna | média |
| H4 | Aviso de sinistro pelo WhatsApp | TW Seguros | já existe | alta |
| H5 | Parcela atrasada com aviso antes de o seguro cair | Quiver alega; ninguém mostra | parcial | média |
| H6 | Família e empresa como unidade | InsuredMine, fora | lacuna provável, dor sem número | baixa |
| H7 | Sinal de risco de não renovar | AgencyZoom, por regra fixa | parcial | média |
| H8 | Pedir indicação na hora certa | Segia lista | evidência fraca | baixa |
| H9 | Dono pergunta sobre a carteira e age a partir da resposta | SegZap e Segura respondem; ação direta não achei | parcial | média |
| H10 | Prova de atendimento junto da apólice | Segia lista | lacuna provável | média |

Dores com fonte: pesquisa do Sincor-SP com cerca de 900 corretores mostra que só 44% oferecem outro seguro sempre.
Atraso de parcela não cancela sozinho: a seguradora precisa notificar (Súmula 616 do STJ). O corretor responde por
falha no dever de informar, e guardar o registro do atendimento é a proteção principal. Não há número público de
taxa de renovação por ramo no Brasil.

Fontes da segunda rodada: revistaapolice.com.br · cqcs.com.br · sincor.org.br · startups.com.br · sonhoseguro.com.br ·
cnnbrasil.com.br · termos de uso e política de privacidade da Segura · ajuda.segfy.com (renovação manual, pendentes,
relatório) · manual do Agger Gestor · helponline.quiverpro.net.br (notas de versão, renovação automática) ·
segbox.com/plataformas/segzap · segiaoficial.com · usecanopy.com · insuredmine.com · segs.com.br · migalhas.com.br.
