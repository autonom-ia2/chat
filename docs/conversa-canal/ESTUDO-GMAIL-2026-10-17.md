# Estudo do Gmail para a conversa de e-mail (#1786)

17/10/2026. O que o Gmail web faz na leitura e na resposta de uma conversa, para guiar a conversa de e-mail do Chat2You. Serve de **referência de experiência**: não copiamos marca, logo, cores próprias do Google nem código.

**Como foi feito:** REA 6.5.0 em linha de comando, conectado por CDP (porta local) a um Chrome de estudo com a conta do Rodrigo, com autorização dele, restrito a `https://mail.google.com`. Coleta passiva:
- prints da tela (`capture-web-screenshot`);
- árvore de acessibilidade (`inspect-web-page --include-accessibility-text`).

Deste documento ficaram fora nomes, endereços, assuntos e textos dos e-mails. Os arquivos brutos ficaram fora do projeto e foram apagados no fim do estudo.

Evidências (IDs do REA):
- `ev_c28c5781…` — lista de abas (só a origem do Gmail);
- `ev_063c35dc…` / `ev_1310af27…` — conversa aberta, rolada no meio (print e acessibilidade);
- `ev_b4e80ff2…` — topo da conversa (print);
- `ev_9e821a00…` — caixa de resposta aberta (print e acessibilidade).

Observação = visto no print ou na árvore de acessibilidade. Inferência = conclusão nossa, marcada como tal.

## 1. Estrutura da tela de leitura (observado)

- **Painel dividido:** lista à esquerda e conversa à direita ("Alternar modo de painel de divisão"). Sem conversa escolhida, aparece "Nenhuma conversa selecionada".
- **Barra de ações da conversa**, acima, só com ícones e dica ao passar o mouse:
  - Arquivar · Denunciar spam · Excluir;
  - Marcar como não lida · Suspender (adiar) · Adicionar ao Tarefas;
  - Mover para · Marcadores · Automatizar · Mais opções de e-mail;
  - à direita: "1–50 de N" e Anteriores/Próximas.
- **Cabeçalho da conversa:**
  - **assunto grande** (título da região), uma vez só;
  - ao lado, as etiquetas como chips ("External", "Caixa de entrada ×");
  - à direita: Imprimir tudo · Nova janela.
- **"Visão Geral Criada por IA"**: caixa de borda azul, recolhível, logo abaixo do assunto.
  - Resumo em 3 tópicos.
  - Rodapé "Criado pelo Gemini; pode conter erros. Saiba mais".
  - "Boa sugestão" / "Sugestão ruim" / "Denunciar abuso".

## 2. Cartão de cada e-mail (observado)

- **Linha do remetente:**
  - foto redonda e nome em negrito;
  - "para mim / para <pessoa>, <lista>" com seta ("Mostrar detalhes" abre De, Para, Cc, data, assunto e "enviado por");
  - à direita, a data ("sex., 16 de out., 12:20 (há 1 dia)") e Sem estrela · Adicionar reação · Responder · Mais opções de mensagem.
- **Corpo** em HTML do remetente, com a formatação original (negrito, listas, tabelas da assinatura, imagens).
- **Assinatura:** o Gmail não separa a assinatura. Ela vem dentro do corpo; quando o texto se repete, cai no "…".
- **Citação e conteúdo repetido** recolhidos num botão "…" ("Mostrar conteúdo cortado").
- **E-mail longo:** "[Mensagem cortada] Exibir toda a mensagem".
- **Mensagens antigas** recolhidas numa linha ("Mostrar mais mensagens"). → **No Chat2You é diferente** (decisão do Rodrigo): abertas por padrão; recolher é opção do atendente.
- **Anexos:** cartões com miniatura no fim do e-mail (inferência: não havia anexo na conversa estudada; conferir num segundo exemplo).

## 3. Fim da conversa (observado)

Botões grandes, em pílula, com ícone e texto:
- **Responder** · **Responder a todos** · **Encaminhar** · reação;
- "Compartilhar no chat (Nova)", que é do Google e não entra.

## 4. Caixa de resposta (observado)

- Abre **dentro da conversa**, embaixo da última mensagem, como um cartão com a foto de quem responde à esquerda.
- **Linha de cima:** seta do tipo de resposta com menu ("Tipo de resposta": Responder / Responder a todos / Encaminhar…) e o destinatário como texto clicável (nome e domínio). Clicar abre Para/Cc/Cco (inferência a conferir: o print não mostra os campos abertos).
- **Campo:** "Corpo da mensagem", placeholder curto e útil. O do Gmail é sobre a IA ("Pressione / para usar o recurso Me ajude a escrever").
- **"…"** abaixo do campo: mostra a citação que vai junto.
- **Barra de baixo, da esquerda para a direita:**
  - **Enviar** (botão azul) com seta ao lado, "Mais opções de envio" (agendar envio);
  - **Aa** (abre a barra de formatação);
  - caneta de IA ("Me ajude a escrever ⌥H");
  - **Anexar arquivos** · **Inserir link (⌘K)** · emoji · Drive · **Inserir foto** · Mais opções;
  - Descartar rascunho (⌘⇧D);
  - "Abrir em um pop-up" no topo do cartão.

## 5. O que leva para o Chat2You

| Gmail | Chat2You (#1786) |
|---|---|
| Assunto grande uma vez, chips de etiqueta | Assunto do **e-mail** como título; assunto do **funil** como chip com o nome do funil (pedido do Multifunnel); etiquetas da conversa como chips |
| Visão geral por IA | Fase 2: resumo com a chave de IA da conta (modelo a confirmar com o Rodrigo); nada ligado por padrão |
| Cartão por e-mail com foto, nome, "para…", detalhes, data relativa | Igual. **Remetente real** do `email.from`, com selo "em cópia" quando não é o contato. Selo "Cliente" e empresa ligada (Base de Clientes). "Agente de IA · nome" para a IA. Data no fuso da conta (`fusoDaConta.js`) |
| Mensagens antigas recolhidas | **Abertas por padrão**; botão "Recolher mensagens antigas" (escolha guardada por atendente) |
| Citação em "…" | Igual, sanitizado. Nunca esconder o link do horário dos avisos de agendamento |
| Imagens abertas | Igual, exceto o pixel e os links de rastreio das campanhas (`/email_campaigns/t/`) |
| Um cartão por e-mail | Igual (os pedaços da IA aparecem separados: #1790) |
| Avisos automáticos | Cartão compacto de uma linha: "Aviso automático de agendamento" + link |
| Responder / Responder a todos / Encaminhar no fim | Igual. Encaminhar com chave própria (`email_forward`), nunca `forwarded` |
| Caixa de resposta dentro da conversa, tipo de resposta, Para/Cc/Cco | Igual, pelo mesmo envio de hoje (mesmo POST, `crm_card_id`, assunto do funil, assinatura) |
| Barra: Enviar · Aa · anexar · link · emoji · foto | Barra única e-mail/WhatsApp (decisão do Rodrigo); no e-mail com formatação própria (sublinhado etc.) |
| Barra de ações da conversa (arquivar, adiar, marcadores…) | Já existe no topo do Chat2You (Resolver, adiar, etiquetas, Passar para, Agendar, CRM): manter o nosso |

## 6. Em aberto

- Segundo exemplo com **anexo**, para ver o cartão de anexo e confirmar Para/Cc/Cco aberto.
- Modelo de IA do resumo (Rodrigo).
- Tratamento no servidor do e-mail escrito por quem está em cópia (Issue com o Multifunnel).
