# Modelo de e-mail das Campanhas na resposta de uma conversa (#1786). Decisão do Rodrigo (18/10): "se o modelo está
# salvo, ele pode usar" — qualquer atendente da conversa usa os modelos salvos da conta (não os da galeria global).
# Entrega o MJML/HTML do modelo e os campos (variáveis Liquid {{ ... }}) já preenchidos com o que se sabe:
#   1. dados do contato e da conta (nome, primeiro nome, e-mail, telefone, empresa, atributos personalizados);
#   2. o que faltar, a IA da conta tenta achar na conversa — só o que estiver escrito lá; senão fica vazio (sem
#      conversa, como na gaveta "Escrever" #1809, a IA não é chamada e o resto vem vazio para a pessoa preencher);
#   3. o atendente confere e muda na tela antes de enviar.
# O rodapé de descadastro sai no navegador, que é quem compila o MJML (mjml-browser); `unsubscribe_url` nunca vira campo.
class ConversaCanal::ModeloDeEmail
  ABRE = '{{'.freeze
  FECHA = '}}'.freeze
  IGNORADAS = %w[unsubscribe_url].freeze
  LIMITE_DE_CAMPOS_PARA_IA = 12
  LIMITE_DA_CONVERSA = 6_000
  # Abrir o modelo é na requisição (15 s do rack-timeout): uma tentativa só, com prazo abaixo do teto. A sugestão fica
  # guardada enquanto o modelo e a conversa não mudam, para reabrir o mesmo modelo não pagar a IA de novo.
  PRAZO_DA_IA = 10
  VALIDADE_DA_SUGESTAO = 30.minutes
  ESQUEMA = {
    name: 'campos_do_modelo',
    schema: {
      type: 'object',
      properties: {
        campos: {
          type: 'array',
          items: {
            type: 'object',
            properties: { chave: { type: 'string' }, valor: { type: 'string' } },
            required: %w[chave valor],
            additionalProperties: false
          }
        }
      },
      required: %w[campos],
      additionalProperties: false
    }
  }.freeze

  def self.da_conta(account)
    EmailCampaignTemplate.where(account: account).order(updated_at: :desc)
  end

  # Nomes das variáveis na ordem em que aparecem, sem repetir. Lê o texto procurando "{{" e "}}" (sem regex);
  # o que vem depois de "|" é filtro do Liquid.
  def self.chaves(texto)
    texto = texto.to_s
    achadas = []
    inicio = texto.index(ABRE)
    while inicio
      fim = texto.index(FECHA, inicio + ABRE.length)
      break unless fim

      nome = texto[(inicio + ABRE.length)...fim].split('|').first.to_s.strip
      achadas << nome if nome.present? && IGNORADAS.exclude?(nome)
      inicio = texto.index(ABRE, fim + FECHA.length)
    end
    achadas.uniq
  end

  # Sem conversa (gaveta "Escrever", #1809): o contato escolhido e a caixa por onde vai sair. A IA não é chamada.
  def initialize(modelo:, user:, conversation: nil, contato: nil, inbox: nil)
    @modelo = modelo
    @conversation = conversation
    @contato = conversation&.contact || contato
    @inbox = conversation&.inbox || inbox
    @account = @inbox.account
    @user = user
  end

  def como_json
    { id: @modelo.id, nome: @modelo.name, mjml: @modelo.body_mjml, html: @modelo.body_html, campos: campos }
  end

  private

  def campos
    chaves = self.class.chaves(@modelo.body_mjml.presence || @modelo.body_html)
    conhecidos = chaves.index_with { |chave| valor_conhecido(chave) }
    sugeridos = sugestoes_da_ia(chaves.select { |chave| conhecidos[chave].blank? })
    chaves.map do |chave|
      if conhecidos[chave].present?
        { chave: chave, valor: conhecidos[chave], origem: 'contato' }
      elsif sugeridos[chave].present?
        { chave: chave, valor: sugeridos[chave], origem: 'ia' }
      else
        { chave: chave, valor: '', origem: 'vazio' }
      end
    end
  end

  def valor_conhecido(chave)
    nome = chave.downcase.delete_prefix('contact.')
    valores_do_contato[nome].presence || atributo_personalizado(nome) || valor_da_conta(chave.downcase)
  end

  def valores_do_contato
    @valores_do_contato ||= nomes_do_contato.merge(canais_do_contato)
  end

  def nomes_do_contato
    nome = @contato&.name.to_s.strip
    partes = nome.split
    sobrenome = partes.drop(1).join(' ')
    { 'name' => nome, 'nome' => nome, 'nome_completo' => nome, 'first_name' => partes.first, 'primeiro_nome' => partes.first,
      'last_name' => sobrenome, 'sobrenome' => sobrenome }
  end

  def canais_do_contato
    return {} if @contato.blank?

    email = @contato.email
    telefone = @contato.phone_number
    empresa = @contato.try(:company).try(:name).presence || @contato.additional_attributes.to_h['company_name']
    { 'email' => email, 'e-mail' => email, 'phone_number' => telefone, 'phone' => telefone, 'telefone' => telefone,
      'company' => empresa, 'company_name' => empresa, 'empresa' => empresa }
  end

  def atributo_personalizado(nome)
    atributos = @contato&.custom_attributes.to_h
    chave = nome.delete_prefix('custom_attributes.')
    atributos[chave].presence&.to_s
  end

  def valor_da_conta(chave)
    {
      'agent.name' => @user&.name, 'atendente' => @user&.name, 'agent.first_name' => @user&.name.to_s.split.first,
      'account.name' => @account.name, 'inbox.name' => @inbox.name
    }[chave].presence
  end

  def sugestoes_da_ia(chaves)
    return {} if @conversation.blank? || chaves.empty? || !credencial.configured?

    chave_do_cache = chave_da_sugestao(chaves)
    Rails.cache.read(chave_do_cache) || perguntar_e_guardar(chaves, chave_do_cache)
  rescue Crm::Ai::ResponsesClient::Error, JSON::ParserError => e
    Rails.logger.warn("[ConversaCanal::ModeloDeEmail] conversation_id=#{@conversation.id} erro=#{e.class.name}")
    {}
  end

  # Só a resposta boa fica guardada: falha da IA pergunta de novo na próxima abertura.
  def perguntar_e_guardar(chaves, chave_do_cache)
    campos = JSON.parse(perguntar_a_ia(chaves.first(LIMITE_DE_CAMPOS_PARA_IA)))['campos'].to_a
    sugestao = campos.to_h { |campo| [campo['chave'], campo['valor'].to_s.strip] }.slice(*chaves)
    Rails.cache.write(chave_do_cache, sugestao, expires_in: VALIDADE_DA_SUGESTAO)
    sugestao
  end

  # Muda o modelo, chega mensagem nova ou muda o que falta: pergunta de novo. A chave é da conta e da conversa, e só
  # leva números e o nome dos campos (nunca o valor sugerido, que tem dados do contato).
  def chave_da_sugestao(chaves)
    ultima = @conversation.messages.maximum(:id)
    ['conversa_canal/modelo_de_email', @conversation.account_id, @conversation.id, @modelo.id, @modelo.updated_at.to_i, ultima,
     chaves.join('|')].join('/')
  end

  def perguntar_a_ia(chaves)
    cliente = Crm::Ai::ResponsesClient.new(credential: credencial.resolve, feature: 'modelo_email', account: @account, max_retries: 0)
    cliente.create(model: Crm::Ai::Config::MODEL_SUMMARY, instructions: INSTRUCOES, input: entrada(chaves).to_json,
                   schema: ESQUEMA, reasoning_effort: 'low', timeout: PRAZO_DA_IA)[:text]
  end

  INSTRUCOES = <<~PROMPT.strip.freeze
    Você preenche as variáveis de um modelo de e-mail que um atendente vai mandar para este cliente.
    Para cada chave pedida, devolva o valor SOMENTE se ele estiver escrito na conversa ou nos dados do contato.
    Se não estiver claro, devolva valor vazio. Nunca invente nome, número, data, valor ou empresa.
    Responda com o texto do valor, sem explicação.
  PROMPT
  private_constant :INSTRUCOES

  # Decisão do Rodrigo (18/10): no modelo de e-mail, a IA pode ver e-mail, telefone e atributos do contato para preencher
  # os campos — exceção à regra de 03/10, só aqui.
  def entrada(chaves)
    {
      chaves: chaves,
      contato: { nome: @contato&.name, email: @contato&.email, telefone: @contato&.phone_number,
                 atributos: @contato&.custom_attributes.to_h },
      conversa: trecho_da_conversa
    }
  end

  def trecho_da_conversa
    mensagens = @conversation.messages.where(private: false, message_type: %i[incoming outgoing]).order(created_at: :desc).limit(12)
    mensagens.reverse.map { |m| "#{m.incoming? ? 'cliente' : 'atendente'}: #{m.content.to_s.squish}" }
             .join("\n").last(LIMITE_DA_CONVERSA)
  end

  def credencial
    @credencial ||= Crm::Ai::CredentialResolver.new(account: @account)
  end
end
