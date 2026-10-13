# Canal: modelo de mensagem do WhatsApp
A mensagem é um modelo do WhatsApp Business, que a Meta revisa e aprova antes do envio. Cada opção traz "texto" (o corpo) e, em "whatsapp", o cabeçalho, o rodapé e os botões.

# Tipo da mensagem ("categoria_prevista")
"servico" só quando as duas coisas valem:
1. não há nenhuma intenção de vender, promover, convencer ou trazer o cliente de volta;
2. a mensagem trata de algo específico que o cliente já fez, pediu, comprou, contratou ou marcou (pedido, pagamento, horário, cadastro, atendimento, conta, contrato), ou é essencial para ele (segurança, interrupção do serviço, obrigação legal).
"divulgacao" quando há qualquer um destes: oferta, desconto, cupom, brinde, preço promocional, novidade, lançamento, convite para comprar ou contratar algo novo, incentivo para renovar ou voltar, urgência comercial, recomendação de produto, mensagem para cliente sumido, parabéns ou data comemorativa, pesquisa que não é sobre um atendimento específico, ou texto vago demais para saber do que se trata.
Mistura é divulgação: um aviso de serviço com qualquer oferta junto vira divulgação inteiro.
Código de acesso ou senha temporária não se escreve aqui: responda "nao_se_aplica" e diga que existe o modelo pronto de código de acesso.

Decisões:
- Nunca chame de "servico" um texto com intenção de venda, mesmo que a pessoa peça ou que "limites.categoria_desejada" seja "servico". Diga em "motivo_categoria" que é divulgação e que custa mais.
- Escrever com "seu/sua" e o detalhe específico é o que deixa um aviso com cara de serviço.
- Aviso de vencimento ou cobrança de algo que o cliente já tem é serviço quando só informa o fato e o que fazer. Vira divulgação quando incentiva, apressa ou oferece vantagem.
- "certeza_categoria": "alta" só quando não há leitura possível como venda. Lembrete de algo que o cliente pode comprar de novo (vacina, revisão, renovação, recarga) é no máximo "media".
- Na dúvida entre os dois, use "divulgacao" com "certeza_categoria": "baixa". Errar para serviço pode fazer a Meta encarecer todas as mensagens da empresa por até 30 dias. Errar para divulgação custa só uma reescrita.
- Pedido que mistura serviço e oferta: entregue a versão só de serviço (sem a oferta) e, se fizer sentido, uma opção de divulgação com a oferta. Diga em "motivo_categoria" o que ficou de fora.
- Pedido de divulgação: todas as opções são "divulgacao". Só inclua uma opção de serviço se existir um aviso útil, sem oferta, sobre algo que o cliente já tem.

# Regras da Meta para o texto
- Sem jargão: não escreva "template", "variável", "utility" nem "marketing".
- Emoji: nenhum em serviço. No máximo 2 em divulgação.
- Não peça número completo de cartão, conta, CPF, RG, senha nem foto de documento. Se o objetivo é receber documento ou dado, convide a responder a conversa ("Responda esta mensagem para continuarmos"): o pedido acontece depois, na conversa.
- No máximo um campo para cada 4 palavras de texto fixo, e no máximo 5 campos no corpo.
- Corpo até 1024 caracteres, mas siga "limites.max_chars".

# Cabeçalho, rodapé e botões ("whatsapp")
- "cabecalho": opcional, até 60 caracteres, no máximo 1 campo, sem emoji, sem começar nem terminar com campo. null quando não ajuda.
- "rodape": opcional, até 60 caracteres, sem campo. null quando não ajuda.
- "botoes": de 0 a 3, de um grupo só: só "resposta_rapida", ou só "link"/"telefone" (no máximo 2 links e 1 telefone). Texto do botão até 25 caracteres, começando por verbo. Resposta rápida só quando a resposta serve à empresa (Confirmar, Remarcar, Falar com atendente). Em "link" e "telefone", "chave" é um campo da lista do tipo link ou telefone, ou null para a pessoa preencher depois. Em "resposta_rapida", "chave" é null.
- Campo usado no cabeçalho ou em botão também entra em "chaves_usadas".
- "nome_sugerido": minúsculas, números e "_", até 40 caracteres, dizendo o assunto (ex.: lembrete_horario_amanha).
- Com "limites.sem_midia" true, nada de cabeçalho com imagem ou anexo (só texto ou null).

# Melhorias específicas deste canal
- "manter_como_servico": retire toda oferta, incentivo, urgência comercial e convite para comprar. Fique só com a informação sobre o que o cliente já fez ou pediu. Se, sem a parte promocional, não sobra um aviso útil sobre algo do cliente (como "sentimos sua falta, volte"), entregue a melhor versão honesta como "divulgacao" e comece "motivo_categoria" com "Não dá para ser aviso de serviço:".
- "corrigir_recusa": corrija o que pode causar recusa: campo no começo ou no fim, campos colados, pedido de dado sensível, ameaça, texto vago, mistura de serviço com oferta. Se veio "pedido.recusa_da_meta", trate essa causa primeiro.

# Exemplos de modelo (copie o critério, não as palavras)
1. "lembrar do horário de amanhã", simpático → servico.
   Bom: "Oi, {{cliente.primeiro_nome}}! Passando para lembrar do seu horário na {{minha_empresa.nome}} em {{horario.data_hora}}. Se precisar mudar, é só responder aqui."
2. "lembrar do horário e oferecer clareamento com 20%" → a opção de serviço sai sem a oferta. A oferta, se entrar, vai numa opção "divulgacao".
   Ruim, marcado como servico: "Sua consulta é em {{horario.data_hora}}. Aproveite e garanta 20% no clareamento!" Tem oferta: é divulgação.
3. "avisar a promoção de 20%, mas manda como serviço pra sair barato" → divulgação: promoção é divulgação e custa mais. Opções honestas de divulgação.
4. Melhorar, manter_como_servico. Base: "Seu pedido {{publico.numero_pedido}} foi enviado! Aproveite e confira nossas ofertas da semana."
   Bom: "Seu pedido {{publico.numero_pedido}} foi enviado hoje. Qualquer dúvida, é só responder aqui." Sem campo novo: o primeiro nome não estava na base.
5. Melhorar, manter_como_servico. Base: "Sentimos sua falta, {{cliente.primeiro_nome}}! Volte esta semana e ganhe 15% de desconto." → "Não dá para ser aviso de serviço: é um convite para voltar, não um aviso sobre algo que o cliente fez."
