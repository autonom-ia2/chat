# #2211 — a busca dentro da lista de conversas, no banco (sem OpenSearch). Entra no SearchService por prepend, com o
# tipo 'Lista'; os outros tipos seguem o caminho de sempre.
#
# Acesso: a base é a mesma da lista de conversas (Conversations::PermissionFilterService com for_reading), que já cobre
# caixa, funil e funções personalizadas. As mensagens só vêm dessas conversas. "Pessoas sem conversa" pede a permissão
# de ver contatos (contact_view); "Começar conversa com +55 …" pede a de criar contato (ContactPolicy#create?).
#
# - telefone pelos dígitos (SearchService::TelefoneDigitado): "11 97862-2068" acha "+5511978622068"; com "+" na
#   frente, o número precisa começar com o que foi digitado (número estrangeiro);
# - "#1234" acha a conversa 1234;
# - sem diferença de acento: lower(translate(...)) de SearchService::SemAcento, a mesma expressão dos índices trigram da
#   migration 20261108520000;
# - palavras em qualquer ordem: cada palavra precisa aparecer; nas mensagens, só palavras de 3 letras ou mais;
# - ordem: nome exato, depois começo do nome, depois contém; empate pela última atividade;
# - conversas: uma por pessoa, a de atividade mais recente; acha também pelo título do card e pelo assunto do e-mail;
# - mensagens dos últimos 12 meses, pelo texto e pelo áudio transcrito.
# Cada seção tem no máximo TEMPO_MAXIMO por consulta; a que estourar volta vazia e entra em `parcial`.
module SearchService::BuscaDaLista
  TIPO = 'Lista'.freeze
  LIMITE = 15
  MESES_DE_MENSAGENS = 12
  MAXIMO_DE_CARACTERES = 100
  MAXIMO_DE_PALAVRAS = 6
  MINIMO_DE_LETRAS_NA_MENSAGEM = 3
  TEMPO_MAXIMO = '1500ms'.freeze
  TIPOS_DE_MENSAGEM = %w[incoming outgoing template].freeze
  # O que o card da lista usa, como em ConversationFinder#conversations_base_query.
  CARREGAR_COM_A_CONVERSA = [:taggings, :team, :contact_inbox, { assignee: { avatar_attachment: [:blob] } },
                             { contact: { avatar_attachment: [:blob] } }].freeze
  PRECARREGAR_COM_A_CONVERSA = [{ inbox: :channel }, { ai_assignee: { avatar_attachment: [:blob] } }].freeze

  def perform
    return super unless search_type == TIPO
    return vazio if termos.empty?

    secoes = {
      conversations: -> { conversas_da_lista },
      messages: -> { mensagens_da_lista },
      contacts: -> { pessoas_sem_conversa }
    }.transform_values { |secao| com_tempo_maximo(&secao) }
    secoes.transform_values { |linhas| linhas || [] }
          .merge(telefone_novo: telefone_novo, parcial: secoes.select { |_secao, linhas| linhas.nil? }.keys)
  end

  private

  def vazio
    { conversations: [], messages: [], contacts: [], telefone_novo: nil, parcial: [] }
  end

  # Cada seção na sua transação, com teto de tempo por consulta. Estourou: nil (a seção volta vazia e parcial).
  # Dentro de outra transação (savepoint), o SET LOCAL duraria até o fim dela: o teto anterior volta no fim da seção.
  def com_tempo_maximo
    conexao = ActiveRecord::Base.connection
    anterior = tempo_anterior
    ActiveRecord::Base.transaction(requires_new: true) do
      conexao.execute("SET LOCAL statement_timeout = '#{TEMPO_MAXIMO}'")
      linhas = yield.to_a
      conexao.execute("SET LOCAL statement_timeout = #{conexao.quote(anterior)}")
      linhas
    end
  rescue ActiveRecord::QueryCanceled
    nil
  end

  def tempo_anterior
    @tempo_anterior ||= ActiveRecord::Base.connection.select_value('SHOW statement_timeout')
  end

  def consulta
    @consulta ||= search_query[0, MAXIMO_DE_CARACTERES]
  end

  def termos
    @termos ||= consulta.split.first(MAXIMO_DE_PALAVRAS)
  end

  def telefone
    @telefone ||= SearchService::TelefoneDigitado.new(consulta)
  end

  def busca_por_numero_da_conversa?
    consulta.start_with?('#') && consulta.length > 1 && consulta[1..].delete('0-9').empty?
  end

  def como_like(texto)
    ActiveRecord::Base.sanitize_sql_like(texto)
  end

  # Cada palavra precisa aparecer na expressão, em qualquer ordem e sem diferença de acento.
  def todas_as_palavras(expressao, palavras = termos)
    sql = palavras.map { "#{SearchService::SemAcento.sql(expressao)} LIKE ?" }.join(' AND ')
    [sql, *palavras.map { |palavra| "%#{como_like(SearchService::SemAcento.texto(palavra))}%" }]
  end

  def condicao_do_contato
    return telefone.condicao if telefone.telefone?

    nome_sql, *nome_valores = todas_as_palavras('contacts.name')
    parecido = "%#{como_like(consulta)}%"
    ["(#{nome_sql}) OR contacts.email ILIKE ? OR contacts.identifier ILIKE ?", *nome_valores, parecido, parecido]
  end

  # 0 = exato, 1 = começa com, 2 = contém (no telefone, SearchService::TelefoneDigitado#ordem).
  def ordem_do_nome
    return telefone.ordem if telefone.telefone?

    nome = SearchService::SemAcento.sql('contacts.name')
    sql = "CASE WHEN #{nome} = ? THEN 0 WHEN #{nome} LIKE ? THEN 1 ELSE 2 END"
    sem_acento = SearchService::SemAcento.texto(consulta)
    ActiveRecord::Base.sanitize_sql_array([sql, sem_acento, "#{como_like(sem_acento)}%"])
  end

  def conversas_permitidas
    @conversas_permitidas ||= Conversations::PermissionFilterService.new(
      current_account.conversations, current_user, current_account, for_reading: true
    ).perform
  end

  def com_o_que_o_card_usa(conversas)
    conversas.includes(CARREGAR_COM_A_CONVERSA).preload(PRECARREGAR_COM_A_CONVERSA)
  end

  # Cada parte acha os ids antes: o contato pelo trigram do nome e pelo de telefone/e-mail, os cards da conta lidos uma
  # vez só. A conversa só confere se está entre eles. Sem isso, o Postgres lia todos os contatos da conta tirando o
  # acento de cada nome (300 ms para o administrador, com o volume da hub).
  def condicao_da_conversa
    contato_sql, *contato_valores = condicao_do_contato
    card_sql, *card_valores = todas_as_palavras('crm_cards.title')
    assunto_sql, *assunto_valores = todas_as_palavras("(conversations.additional_attributes ->> 'mail_subject')")
    sql = <<~SQL.squish
      conversations.contact_id IN (SELECT contacts.id FROM contacts WHERE contacts.account_id = ? AND (#{contato_sql}))
      OR conversations.id IN (
        WITH cards AS (SELECT crm_cards.id, crm_cards.conversation_id FROM crm_cards
                       WHERE crm_cards.account_id = ? AND #{card_sql})
        SELECT cards.conversation_id FROM cards
        UNION ALL
        SELECT crm_card_conversations.conversation_id FROM crm_card_conversations
        WHERE crm_card_conversations.card_id IN (SELECT cards.id FROM cards)
      )
      OR (#{assunto_sql})
    SQL
    conta = current_account.id
    [sql, conta, *contato_valores, conta, *card_valores, *assunto_valores]
  end

  def conversas_da_lista
    return com_o_que_o_card_usa(conversas_permitidas.where(display_id: consulta[1..].to_i)) if busca_por_numero_da_conversa?

    achadas = conversas_permitidas.where(condicao_da_conversa)
    # Uma por pessoa: a de atividade mais recente.
    uma_por_pessoa = achadas.select('DISTINCT ON (conversations.contact_id) conversations.id')
                            .reorder('conversations.contact_id, conversations.last_activity_at DESC')
    com_o_que_o_card_usa(Conversation.where(id: uma_por_pessoa).joins(:contact))
      .order(Arel.sql(ordem_do_nome), last_activity_at: :desc)
      .limit(LIMITE)
  end

  # Palavras curtas não usam o índice trigram e varrem a conta inteira: nas mensagens ficam de fora.
  def palavras_da_mensagem
    @palavras_da_mensagem ||= termos.select { |termo| termo.length >= MINIMO_DE_LETRAS_NA_MENSAGEM }
  end

  # Sem o filtro de acesso: ele entra depois, sobre o que o índice trigram achou.
  def mensagens_da_conta
    current_account.messages.where(created_at: MESES_DE_MENSAGENS.months.ago.., message_type: TIPOS_DE_MENSAGEM)
                   .reselect('messages.id, messages.created_at, messages.conversation_id')
  end

  # Texto e áudio em consultas separadas, cada uma no seu índice trigram e num CTE MATERIALIZED: o Postgres acha as
  # mensagens pelo índice primeiro e só depois confere o acesso e ordena. Sem isso, para quem vê poucas caixas, ele
  # descia conversa por conversa e lia todas as mensagens delas (2 s com o volume da hub).
  def ids_das_mensagens
    texto = mensagens_da_conta.where(*todas_as_palavras('messages.content', palavras_da_mensagem))
    # Uma linha por mensagem, mesmo com mais de um áudio transcrito.
    audio = mensagens_da_conta.joins(:attachments).distinct
                              .where(*todas_as_palavras("(attachments.meta ->> 'transcribed_text')", palavras_da_mensagem))
    permitidas = conversas_permitidas.reselect(:id).to_sql
    <<~SQL.squish
      WITH texto AS MATERIALIZED (#{texto.to_sql}), audio AS MATERIALIZED (#{audio.to_sql})
      (SELECT id FROM texto WHERE conversation_id IN (#{permitidas}) ORDER BY created_at DESC, id DESC LIMIT #{LIMITE})
      UNION ALL
      (SELECT id FROM audio WHERE conversation_id IN (#{permitidas}) ORDER BY created_at DESC, id DESC LIMIT #{LIMITE})
    SQL
  end

  def mensagens_da_lista
    return Message.none if palavras_da_mensagem.empty? || busca_por_numero_da_conversa?

    Message.where("messages.id IN (#{ids_das_mensagens})")
           .includes(:attachments, :sender, conversation: :contact)
           .reorder('messages.created_at DESC, messages.id DESC')
           .limit(LIMITE)
  end

  # Pessoas da conta sem nenhuma conversa. Quem não pode ver a base de contatos (contact_view, #1849) não vê esta seção.
  def pessoas_sem_conversa
    return Contact.none if busca_por_numero_da_conversa? || !politica_de_contato.index?

    current_account.contacts.where(condicao_do_contato).includes(avatar_attachment: :blob)
                   .where('NOT EXISTS (SELECT 1 FROM conversations WHERE conversations.contact_id = contacts.id)')
                   .order(Arel.sql(ordem_do_nome), :name)
                   .limit(LIMITE)
  end

  def politica_de_contato
    @politica_de_contato ||= ContactPolicy.new({ user: current_user, account: current_account, account_user: account_user }, Contact)
  end

  # Telefone completo que ninguém da conta tem: a lista oferece "Começar conversa com +55 …", para quem cria contato.
  def telefone_novo
    numero = telefone.numero_completo
    return if numero.nil? || !politica_de_contato.create?

    current_account.contacts.exists?(phone_number: numero) ? nil : numero
  end
end
