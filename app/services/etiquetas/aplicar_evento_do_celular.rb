# Aplica na plataforma um evento de etiqueta do app WhatsApp Business do celular (#1823, F1b). Contrato do evento no
# WhatsappLabels::AplicarEvento. Regras (decisões do Rodrigo):
# - Sem a flag `etiquetas_do_celular` na conta da caixa: descarta.
# - criada / renomeada: grava a correspondência (Etiquetas::DoCelular) com o nome e a cor do celular. Sem correspondência,
#   cria o `Label` com o título técnico derivado do nome ("Novo cliente 🔥" vira `novo_cliente`) ou reaproveita o que já
#   tem esse título. Renomear não muda o título nem o nome livre daqui: só o nome do celular, que a tela mostra quando não
#   há nome livre.
# - apagada: some a correspondência; o `Label` fica, com tudo em que já está.
# - vinculada / desvinculada: põe ou tira a etiqueta do contato (pelo telefone; na falta, pelo chat id) e da conversa
#   não resolvida mais recente dele nesta caixa (aberta ou pendente). Vinculada sem correspondência cria como em criada;
#   desvinculada sem correspondência não cria nada (só log). Contato não encontrado: fica só a correspondência e o log.
# Repetir o evento não duplica nada. Erro não é engolido: sobe para o job (e a fila tenta de novo).
class Etiquetas::AplicarEventoDoCelular
  ACOES = %w[criada renomeada apagada vinculada desvinculada].freeze
  FLAG = 'etiquetas_do_celular'.freeze
  LOG = '[etiquetas_do_celular]'.freeze
  SEPARADOR = '_'.freeze
  ACEITOS_ALEM_DE_LETRA = (('0'..'9').to_a + [SEPARADOR, '-']).freeze
  TAMANHO_MINIMO_DO_TITULO = 2 # a validação do Label pede ao menos dois caracteres
  PREFIXO_SEM_TITULO = 'whatsapp'.freeze
  CONVERSA_EM_ANDAMENTO = %i[open pending].freeze
  CHAVES_DO_CHAT_ID = [Waha::ContactChatId::CHAT_ID, Waha::ContactChatId::JID, Waha::ContactChatId::LID].freeze

  def initialize(evento)
    @evento = evento.to_h.with_indifferent_access
  end

  def perform
    acao = @evento[:acao].to_s
    raise ArgumentError, "#{LOG} ação desconhecida: #{acao.inspect}" unless ACOES.include?(acao)

    @inbox = Inbox.find_by(id: @evento[:inbox_id])
    return descartar('caixa não existe mais') if @inbox.nil?
    return descartar('flag desligada na conta') unless conta.feature_enabled?(FLAG)

    aplicar(acao)
  end

  # Título técnico de um nome do celular, pelas mesmas regras do formulário (`tituloTecnicoDoNome` no painel), sem regex:
  # minúsculo, palavras unidas por "_", só letra (de qualquer alfabeto com maiúscula e minúscula), dígito, "_" e "-",
  # e sem separador no começo.
  def self.titulo_tecnico(nome)
    palavras = nome.to_s.unicode_normalize(:nfc).downcase.split
    titulo = palavras.map { |palavra| palavra.each_char.select { |ch| caractere_aceito?(ch) }.join }
                     .compact_blank.join(SEPARADOR)
    titulo = titulo[1..] while titulo.start_with?(SEPARADOR, '-')
    titulo
  end

  def self.caractere_aceito?(caractere)
    caractere.downcase != caractere.upcase || ACEITOS_ALEM_DE_LETRA.include?(caractere)
  end

  private

  def aplicar(acao)
    case acao
    when 'criada', 'renomeada' then correspondencia!
    when 'apagada' then apagar_correspondencia
    when 'vinculada' then trocar_no_contato(correspondencia!.label, :adicionar)
    when 'desvinculada' then desvincular
    end
  end

  def conta
    @inbox.account
  end

  def label_wa_id
    @evento[:label_wa_id].to_s
  end

  # Acha ou cria a correspondência e deixa o nome e a cor iguais aos do celular. Dois eventos da mesma etiqueta ao mesmo
  # tempo: o segundo bate no índice único (inbox_id, label_wa_id) e lê o que o primeiro gravou.
  def correspondencia!(tentar_de_novo: true)
    existente = Etiquetas::DoCelular.find_by(inbox: @inbox, label_wa_id: label_wa_id)
    return atualizar(existente) if existente

    label, criada = etiqueta_para_o_nome
    Etiquetas::DoCelular.create!(account: conta, inbox: @inbox, label: label, label_wa_id: label_wa_id,
                                 nome: @evento[:nome], color_index: @evento[:color_index], criada_pelo_celular: criada)
  rescue ActiveRecord::RecordNotUnique
    raise unless tentar_de_novo

    correspondencia!(tentar_de_novo: false)
  end

  def atualizar(registro)
    registro.update!(nome: @evento[:nome], color_index: @evento[:color_index])
    registro
  end

  # O `Label` com o título técnico do nome: o que já existe na conta ou um novo. Devolve [label, criada_agora].
  def etiqueta_para_o_nome
    titulo = titulo_do_evento
    existente = conta.labels.find_by(title: titulo)
    return [existente, false] if existente

    [conta.labels.create!(title: titulo), true]
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Outro evento criou o mesmo título no meio do caminho: reaproveita. Qualquer outro motivo sobe.
    existente = conta.labels.find_by(title: titulo)
    raise if existente.nil?

    [existente, false]
  end

  # Nome sem letra nem dígito aproveitável ("🔥", "A"): o título vira `whatsapp_<id da etiqueta no celular>`.
  def titulo_do_evento
    titulo = self.class.titulo_tecnico(@evento[:nome])
    return titulo if titulo.length >= TAMANHO_MINIMO_DO_TITULO

    [PREFIXO_SEM_TITULO, self.class.titulo_tecnico(label_wa_id)].compact_blank.join(SEPARADOR)
  end

  def desvincular
    existente = Etiquetas::DoCelular.find_by(inbox: @inbox, label_wa_id: label_wa_id)
    return descartar("#{self.class.name}: desvinculada sem correspondência label_wa_id=#{label_wa_id}") if existente.nil?

    trocar_no_contato(existente.label, :remover)
  end

  def apagar_correspondencia
    Etiquetas::DoCelular.where(inbox: @inbox, label_wa_id: label_wa_id).delete_all
  end

  def trocar_no_contato(label, operacao)
    contato = contato_do_evento
    return descartar("contato não encontrado (label_wa_id=#{label_wa_id})") if contato.nil?

    em_nome_do_sistema(label) do
      trocar_etiqueta(contato, label.title, operacao)
      conversa = conversa_aberta_de(contato)
      trocar_etiqueta(conversa, label.title, operacao) if conversa
    end
  end

  # Na conversa, a nota de atividade sai como "Sistema de Automação" em vez de um nome em branco.
  def em_nome_do_sistema(autor)
    anterior = Current.executed_by
    Current.executed_by = autor
    yield
  ensure
    Current.executed_by = anterior
  end

  def trocar_etiqueta(registro, titulo, operacao)
    atuais = registro.label_list.to_a
    novas = operacao == :adicionar ? atuais | [titulo] : atuais - [titulo]
    registro.update_labels(novas) unless novas.sort == atuais.sort
  end

  # A mais recente não resolvida: aberta ou pendente (robô atendendo). Adiada e resolvida ficam fora.
  def conversa_aberta_de(contato)
    @inbox.conversations.where(contact: contato, status: CONVERSA_EM_ANDAMENTO)
          .order(last_activity_at: :desc, id: :desc).first
  end

  def contato_do_evento
    contato_pelo_telefone || contato_pelo_chat_id
  end

  def contatos_da_caixa
    conta.contacts.joins(:contact_inboxes).where(contact_inboxes: { inbox_id: @inbox.id }).order(:id)
  end

  def contato_pelo_telefone
    telefone = @evento[:contact_phone].to_s.strip
    return if telefone.empty?

    telefone = "+#{telefone}" unless telefone.start_with?('+')
    contatos_da_caixa.find_by(phone_number: telefone)
  end

  # O source_id do ContactInbox (provedor que guarda o JID nele) e, na caixa WAHA, os atributos onde o conector guarda o
  # chat id do contato (Waha::ContactChatId).
  def contato_pelo_chat_id
    chat_id = @evento[:chat_id].to_s.strip
    return if chat_id.empty?

    contatos_da_caixa.find_by(contact_inboxes: { source_id: chat_id }) ||
      CHAVES_DO_CHAT_ID.lazy.filter_map do |chave|
        contatos_da_caixa.find_by('contacts.custom_attributes ->> :chave = :valor', chave: chave, valor: chat_id)
      end.first
  end

  def descartar(motivo)
    Rails.logger.info("#{LOG} evento descartado: #{motivo} inbox=#{@evento[:inbox_id]} acao=#{@evento[:acao]}")
    nil
  end
end
