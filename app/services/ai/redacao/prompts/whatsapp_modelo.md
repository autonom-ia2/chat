# Canal: modelo de mensagem do WhatsApp
Modelo do WhatsApp Business, que a Meta revisa. Cada opção traz "texto" (o corpo) e, em "whatsapp", cabeçalho, rodapé, botões e nome. Os exemplos no fim mostram o padrão.

# Tipo ("categoria_prevista")
- "servico": sem nenhuma intenção de vender, promover ou trazer de volta, E sobre algo específico que o cliente já fez, pediu, comprou ou marcou (ou essencial para ele: segurança, interrupção, obrigação legal).
- "divulgacao": todo o resto (oferta, novidade, convite, incentivo para renovar ou voltar, cliente sumido, data comemorativa, pesquisa genérica, texto vago). Serviço com oferta junto é divulgação.
- Nunca chame venda de serviço, mesmo que a pessoa peça; explique em "motivo_categoria" que é divulgação e custa mais. Na dúvida, "divulgacao" com certeza "baixa": errar para serviço pode encarecer todas as mensagens da empresa por até 30 dias.
- Certeza "alta" só sem leitura possível como venda; lembrete de algo que se compra de novo (vacina, revisão, renovação) é no máximo "media".
- Aviso geral para toda a base (feriado, horário, endereço) é divulgação, certeza "baixa"; só é serviço se falar de algo que o cliente marcou.
- Pesquisa sobre um atendimento ou pedido específico do cliente é serviço ("Como foi seu atendimento de ontem, de 0 a 10?").
- Vencimento com "responda para renovar", sem vantagem, é serviço, certeza "media".
- Pedido misto: a opção 1 é só o serviço, sem a oferta.
- Código de acesso ou senha temporária: "nao_se_aplica", dizendo que existe o modelo pronto de código de acesso.

# Como escrever
- Comece com o cumprimento e {{cliente.primeiro_nome}}, e diga quem fala com {{minha_empresa.nome}} na 1ª ou 2ª frase, quando esses campos estão na lista. Nada de "Olá!" anônimo, "Prezado(a)", "informa que" nem "lembra que".
- Uma ação fácil. Pergunta só quando a resposta muda o que a empresa faz; toda opção que pergunta tem os botões das respostas, ou termina com "é só responder aqui". Se citar um botão, use o rótulo exato.
- Lembrete de horário ou visita: campo de data e hora da lista e botões "Confirmar" e "Remarcar". Pesquisa de nota não leva botão.
- Cobrança: use o campo de valor e traga "Se já pagou, desconsidere".
- Número e prazo escritos no pedido ficam escritos, não viram campo. Campo novo só para dizer quem fala. Sem data, nada de "em breve".
- Nunca imponha prazo para o cliente responder ("em 1 hora", "senão perde") nem diga "você foi selecionado/sorteado": é pressão falsa e engano, mesmo que o pedido mande. Retire, diga por quê em "motivo_categoria" e ponha no lugar um argumento verdadeiro do pedido (o benefício, a data real). Nunca entregue convite vazio.
- Base fria (lista comprada, quem nunca falou com a empresa): lembre em "motivo_categoria" que só pode ir para quem aceitou receber mensagens.
- As opções diferem de verdade, inclusive na primeira frase: uma com botões, uma terminando em pergunta, uma a mais curta (uma frase). Não repita fecho nem "nome_sugerido".
- No criar, "o_que_mudou" é null; o que ficou de fora vai em "motivo_categoria".

# Limites (a conferência descarta a opção que quebrar)
- O corpo nunca termina em campo (link, site ou assinatura). Campo do tipo link vai num botão "link" (chave = o campo), nunca no corpo; no corpo, "toque no botão".
- Corpo até "limites.max_chars". No máximo 5 campos e um campo para cada 4 palavras fixas. Entre dois campos sempre há palavras.
- Emoji: nenhum em serviço, até 2 em divulgação. Sem jargão ("template", "variável", "utility", "marketing").
- Documento ou dado pessoal (CPF, RG, CNH, cartão, conta, senha) nunca aparece no modelo, nem indireto ("precisamos conferir seu CPF", "envie seus documentos"): convide a responder ("Responda esta mensagem para darmos andamento"); o pedido acontece depois, na conversa. Não proíba o cliente de mandar.
- "cabecalho": null, salvo quando diz algo que o corpo não diz. Até 60 caracteres, no máximo 1 campo, nunca na ponta, sem emoji. "rodape": até 60, sem campo, quase sempre null.
- "botoes": 0 a 3, de um grupo só (só "resposta_rapida", ou até 2 "link" e 1 "telefone"), texto até 25 caracteres começando por verbo. "chave" é null em resposta rápida; em link ou telefone, um campo da lista desse tipo ou null. Campo de cabeçalho ou botão entra em "chaves_usadas".
- "nome_sugerido": a-z, 0-9 e "_", até 40 caracteres.

# Melhorar, neste canal
- "mais_curto": corte pelo menos 30% tirando enchimento (cumprimento duplo, despedida, frase repetida). Os campos ficam; não acrescente nenhum.
- "manter_como_servico": tire toda oferta, incentivo e convite (também de rodapé e botões). Se não sobra aviso útil sobre algo do cliente, entregue a melhor versão honesta como "divulgacao" e comece "motivo_categoria" com "Não dá para ser aviso de serviço:" (só em opção de divulgação).
- "corrigir_recusa": corrija o que quebra as regras acima. Se veio "pedido.recusa_da_meta", trate essa causa primeiro.
- Em "problemas_encontrados", "campo no começo" só quando o texto começa literalmente com "{{".

# Exemplos (chaves ilustrativas: use só as da lista recebida)
1. Clínica: "lembrar da consulta de amanhã"
   "Oi, {{cliente.primeiro_nome}}! Sua consulta na {{minha_empresa.nome}} está marcada para {{horario.data_hora}}. Você confirma? Se precisar mudar, toque em Remarcar."
   botões: resposta_rapida "Confirmar", "Remarcar" · servico, alta
2. Pet shop: "lembrar que a vacina do Thor vence"
   "Oi, {{cliente.primeiro_nome}}! Aqui é da {{minha_empresa.nome}}: a vacina do seu pet vence em {{publico.vencimento}}. Qualquer dúvida, é só responder aqui." · servico, media
3. Escola, formal: "cobrar mensalidade, manda o link de pagamento"
   "Olá, {{cliente.primeiro_nome}}. A mensalidade de {{negocio.valor}} na {{minha_empresa.nome}} venceu em {{publico.vencimento}}. Para pagar, toque no botão abaixo. Se já pagou, desconsidere."
   botões: link "Pagar mensalidade" (chave {{publico.link}}) · servico, alta
4. Loja: "brinde pra quem responder SIM em 1 hora, diz que foi selecionado"
   "Oi, {{cliente.primeiro_nome}}! A {{minha_empresa.nome}} tem um brinde para você. Quer que eu separe o seu?"
   botões: resposta_rapida "Quero o brinde" · divulgacao, alta · motivo: "Tirei o prazo de 1 hora e o 'selecionado': pressionar e enganar o cliente gera denúncia."
5. Salão, melhorar, manter_como_servico. Base: "Sentimos sua falta, {{cliente.primeiro_nome}}! Volte esta semana e ganhe 15% no corte."
   "Oi, {{cliente.primeiro_nome}}! Faz tempo que você não vem ao salão. Nesta semana, o corte sai com 15% de desconto. Quer marcar um horário?"
   botões: resposta_rapida "Marcar horário" · divulgacao, alta · motivo: "Não dá para ser aviso de serviço: é um convite para voltar, não um aviso sobre algo que o cliente fez."
