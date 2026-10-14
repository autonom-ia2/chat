# Grava os campos extraídos pelo Decisor (#858) nos destinos que ele declara: contato, empresa e card
# do alvo (o card da automação de etapa, ou o card da conversa).
#
# Por padrão só PREENCHE, nunca troca o que já existia. O texto é de terceiros: uma assinatura ou um
# nome citado ("falar com Maria da XPTO") não podem trocar o nome, o telefone ou a empresa de um contato
# que já tinha. Por isso, sem `trocar`:
# - nome: só quando o contato não tem nome de verdade — vazio, ou o próprio e-mail/telefone, que é o
#   que a plataforma põe quando não sabe;
# - telefone, cargo, biografia, atributo e empresa: só quando vazios;
# - card: só campo vazio, ou o card que os passos desta mesma regra acabaram de criar (`card_novo`).
#
# `trocar: true` no campo é a escolha de quem monta a automação (#1000): "mude o nome do contato com o
# que vier no e-mail do formulário". Aí o valor novo entra mesmo com valor antigo. O e-mail do contato
# nunca é trocado: é ele que identifica o contato no canal.
#
# Empresa com `trocar`: a empresa só daquele contato é renomeada; a que tem outros contatos fica como
# está e o contato passa para a empresa do nome novo (a que já existir, ou uma nova). Renomear uma
# empresa de vários contatos mexeria em todos eles.
#
# Telefone: sai no formato que o contato aceita (+5522974049400) pela gem `telephone_number`, com o país
# da conta quando o texto não traz o código do país. Telefone que já é de outro contato não pode ser
# gravado (é único na conta): o motivo fica na decisão e o número vai para a biografia, para não se perder.
#
# Cada campo é gravado sozinho, e o que não gravou volta em `recusados` com o motivo — nada some calado.
#
# O card pode ainda não existir quando o Decisor responde — é comum o passo seguinte ser "criar card".
# Os campos de card sem card voltam em `sem_card`, e quem chamou aplica de novo depois dos passos.
class Autonomia::Decisores::Aplicador
  Resultado = Struct.new(:aplicados, :sem_card, :recusados, keyword_init: true)
  DO_CONTATO = { 'contato.nome' => :name, 'contato.email' => :email }.freeze
  DO_CARD = { 'card.titulo' => :title, 'card.descricao' => :description }.freeze
  CARGO = 'job_title'.freeze
  BIOGRAFIA = 'description'.freeze
  NOTA_DE_TELEFONE = 'Telefone informado: %<numero>s (já cadastrado no contato #%<contato>s)'.freeze

  def initialize(decisor:, conversation: nil, card: nil)
    @decisor = decisor
    @conversation = conversation
    @card = card
    @account = decisor.account
  end

  def aplicar(valores, card_novo: false)
    @card_novo = card_novo
    aplicados = {}
    sem_card = {}
    recusados = {}
    Array(@decisor.campos).each do |campo|
      valor = valores[campo['chave']]
      next if valor.blank?

      @trocar = ActiveModel::Type::Boolean.new.cast(campo['trocar']) == true
      resultado = gravar(campo['destino'], valor)
      case resultado
      when :gravado then aplicados[campo['chave']] = valor
      when :sem_card then sem_card[campo['chave']] = valor
      when String then recusados[campo['chave']] = resultado
      end
    end
    Resultado.new(aplicados: aplicados, sem_card: sem_card, recusados: recusados)
  end

  private

  def gravar(destino, valor)
    return gravar_atributo_do_card(destino.delete_prefix(Autonomia::Decisor::ATRIBUTO_DE_CARD), valor) if atributo_do_card?(destino)
    return gravar_no_card(DO_CARD.fetch(destino), valor) if destino.start_with?('card.')
    return 'sem contato na conversa' if contato.blank?

    gravar_no_contato_ou_empresa(destino, valor)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # O valor recusado não pode ficar no contato em memória: o próximo campo tentaria gravá-lo de novo.
    contato&.restore_attributes
    Rails.logger.info("[autonomia][decisor] decisor=#{@decisor.id} destino=#{destino} recusado: #{e.class}")
    "recusado pela plataforma: #{motivo_do_erro(e)}"
  end

  def gravar_no_contato_ou_empresa(destino, valor)
    case destino
    when 'contato.telefone' then gravar_telefone(valor)
    when 'contato.cargo' then gravar_atributo(CARGO, valor)
    when 'contato.biografia' then gravar_biografia(valor)
    when 'empresa.nome' then gravar_empresa(valor)
    else
      return gravar_atributo(destino.delete_prefix(Autonomia::Decisor::ATRIBUTO_DE_CONTATO), valor) if atributo?(destino)

      gravar_no_contato(DO_CONTATO.fetch(destino), valor)
    end
  end

  def motivo_do_erro(erro)
    return erro.record.errors.full_messages.to_sentence.first(200) if erro.respond_to?(:record) && erro.record

    erro.class.name
  end

  def atributo?(destino)
    destino.start_with?(Autonomia::Decisor::ATRIBUTO_DE_CONTATO)
  end

  def contato
    @contato ||= @card&.contact || @conversation&.contact
  end

  def gravar_no_contato(atributo, valor)
    return 'já tinha valor' unless pode_gravar_no_contato?(atributo)
    return :gravado if contato[atributo].to_s == valor

    contato.update!(atributo => valor)
    :gravado
  end

  def pode_gravar_no_contato?(atributo)
    return contato.email.blank? if atributo == :email
    return true if @trocar

    atributo == :name ? nome_provisorio? : contato[atributo].blank?
  end

  # O nome que a plataforma pôs por falta de outro: o e-mail, o começo dele, ou o telefone.
  def nome_provisorio?
    nome = contato.name.to_s.strip
    email = contato.email.to_s
    nome.empty? || nome.casecmp?(email) || nome.casecmp?(email.split('@').first.to_s) || nome == contato.phone_number.to_s
  end

  def gravar_telefone(valor)
    numero = Autonomia::Decisores::Telefone.new(@account).normalizar(valor)
    return "telefone fora do formato: #{valor}" if numero.blank?
    return :gravado if contato.phone_number == numero
    return 'já tinha valor' unless @trocar || contato.phone_number.blank?

    dono = Contact.where(account_id: @account.id, phone_number: numero).where.not(id: contato.id).pick(:id)
    return telefone_de_outro(numero, dono) if dono

    contato.update!(phone_number: numero)
    :gravado
  end

  # O número existe em outro contato da conta (a pessoa já falou por outro canal). Juntar os dois é
  # outra decisão; aqui o número não se perde: vai para a biografia.
  def telefone_de_outro(numero, dono)
    nota = format(NOTA_DE_TELEFONE, numero: numero, contato: dono)
    atual = contato.additional_attributes.to_h[BIOGRAFIA].to_s
    unless atual.include?(numero)
      contato.update!(additional_attributes: contato.additional_attributes.to_h.merge(BIOGRAFIA => [atual.presence, nota].compact.join("\n")))
    end
    "telefone #{numero} já é do contato ##{dono}; guardado na biografia"
  end

  def gravar_atributo(chave, valor)
    return 'já tinha valor' unless @trocar || contato.custom_attributes.to_h[chave].blank?

    contato.update!(custom_attributes: contato.custom_attributes.to_h.merge(chave => valor))
    :gravado
  end

  def gravar_biografia(valor)
    return 'já tinha valor' unless @trocar || contato.additional_attributes.to_h[BIOGRAFIA].blank?

    contato.update!(additional_attributes: contato.additional_attributes.to_h.merge(BIOGRAFIA => valor))
    :gravado
  end

  def gravar_empresa(nome)
    return 'conta sem empresas' unless contato.respond_to?(:company=)
    return vincular_empresa(nome) if contato.company_id.blank?
    return :gravado if contato.company.name.to_s.casecmp?(nome)
    return 'já tinha empresa' unless @trocar

    trocar_empresa(nome)
  end

  # A empresa de mesmo nome na conta, criada se não existir.
  def vincular_empresa(nome)
    contato.update!(company: empresa_com_nome(nome) || Company.create!(account_id: @account.id, name: nome))
    :gravado
  end

  def trocar_empresa(nome)
    atual = contato.company
    outra = empresa_com_nome(nome)
    if outra.nil? && atual.contacts.where.not(id: contato.id).none?
      atual.update!(name: nome)
    else
      contato.update!(company: outra || Company.create!(account_id: @account.id, name: nome))
    end
    :gravado
  end

  def empresa_com_nome(nome)
    Company.where(account_id: @account.id).find_by('LOWER(name) = ?', nome.downcase)
  end

  def gravar_no_card(atributo, valor)
    card = @card || card_da_conversa
    return :sem_card if card.blank?
    return 'já tinha valor' unless @card_novo || @trocar || card[atributo].blank?

    card.update!(atributo => valor)
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
    :gravado
  end

  def atributo_do_card?(destino)
    destino.start_with?(Autonomia::Decisor::ATRIBUTO_DE_CARD)
  end

  # Campo próprio do card (#1146): o card do gatilho ou o assunto atual da conversa.
  def gravar_atributo_do_card(chave, valor)
    card = @card || card_da_conversa
    return :sem_card if card.blank?
    return 'já tinha valor' unless @card_novo || @trocar || card.custom_attributes.to_h[chave].blank?

    card.with_lock { card.update!(custom_attributes: card.custom_attributes.to_h.merge(chave => valor)) }
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
    :gravado
  end

  def card_da_conversa
    return if @conversation.nil? || !Crm::Config.enabled?

    Crm::Cards::ConversationCardFinder.new(account: @account).find(@conversation)
  end
end
