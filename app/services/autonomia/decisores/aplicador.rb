# Grava os campos extraídos pelo Decisor (#858) nos destinos que ele declara: contato, empresa e card
# da conversa.
#
# Só PREENCHE, nunca troca o que já existia. O texto é de terceiros: uma assinatura, um nome citado
# ("falar com Maria da XPTO") ou o lead de um portal que manda todos os e-mails do mesmo remetente não
# podem trocar o nome, o e-mail, o telefone ou a empresa de um contato que já tinha. Por isso:
# - nome: só quando o contato não tem nome de verdade — vazio, ou o próprio e-mail/telefone, que é o
#   que a plataforma põe quando não sabe;
# - e-mail e telefone (que identificam o contato no canal), atributo e empresa: só quando vazios;
# - card: só campo vazio, ou o card que os passos desta mesma regra acabaram de criar (`card_novo`).
# Como nada é trocado, não há valor anterior a guardar para desfazer.
#
# Cada campo é gravado sozinho: um telefone fora do formato (a validação do próprio contato recusa)
# não impede o nome de entrar. Só o que de fato gravou volta em `aplicados` e fica na decisão.
#
# O card pode ainda não existir quando o Decisor responde — é comum o passo seguinte ser "criar card".
# Os campos de card sem card voltam em `sem_card`, e quem chamou aplica de novo depois dos passos.
class Autonomia::Decisores::Aplicador
  Resultado = Struct.new(:aplicados, :sem_card, keyword_init: true)
  DO_CONTATO = { 'contato.nome' => :name, 'contato.telefone' => :phone_number, 'contato.email' => :email }.freeze
  DO_CARD = { 'card.titulo' => :title, 'card.descricao' => :description }.freeze

  def initialize(decisor:, conversation:)
    @decisor = decisor
    @conversation = conversation
    @account = conversation.account
  end

  def aplicar(valores, card_novo: false)
    @card_novo = card_novo
    aplicados = {}
    sem_card = {}
    Array(@decisor.campos).each do |campo|
      valor = valores[campo['chave']]
      next if valor.blank?

      case gravar(campo['destino'], valor)
      when :gravado then aplicados[campo['chave']] = valor
      when :sem_card then sem_card[campo['chave']] = valor
      end
    end
    Resultado.new(aplicados: aplicados, sem_card: sem_card)
  end

  private

  def gravar(destino, valor)
    return gravar_no_card(DO_CARD.fetch(destino), valor) if destino.start_with?('card.')
    return gravar_atributo(destino.delete_prefix(Autonomia::Decisor::ATRIBUTO_DE_CONTATO), valor) if atributo?(destino)
    return gravar_empresa(valor) if destino == 'empresa.nome'

    gravar_no_contato(DO_CONTATO.fetch(destino), valor)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    # O valor recusado não pode ficar no contato em memória: o próximo campo tentaria gravá-lo de novo.
    contato&.restore_attributes
    Rails.logger.info("[autonomia][decisor] decisor=#{@decisor.id} destino=#{destino} recusado: #{e.class}")
    nil
  end

  def atributo?(destino)
    destino.start_with?(Autonomia::Decisor::ATRIBUTO_DE_CONTATO)
  end

  def contato
    @contato ||= @conversation.contact
  end

  def gravar_no_contato(atributo, valor)
    return if contato.blank?
    return unless atributo == :name ? nome_provisorio? : contato[atributo].blank?

    contato.update!(atributo => valor)
    :gravado
  end

  # O nome que a plataforma pôs por falta de outro: o e-mail, o começo dele, ou o telefone.
  def nome_provisorio?
    nome = contato.name.to_s.strip
    email = contato.email.to_s
    nome.empty? || nome.casecmp?(email) || nome.casecmp?(email.split('@').first.to_s) || nome == contato.phone_number.to_s
  end

  def gravar_atributo(chave, valor)
    return if contato.blank? || contato.custom_attributes.to_h[chave].present?

    contato.update!(custom_attributes: contato.custom_attributes.to_h.merge(chave => valor))
    :gravado
  end

  # A empresa do contato passa a ser a de mesmo nome na conta, criada se não existir — só para contato
  # sem empresa. Renomear a empresa atual mexeria em todos os outros contatos dela.
  def gravar_empresa(nome)
    return if contato.blank? || !contato.respond_to?(:company=) || contato.company_id.present?

    empresa = Company.where(account_id: @account.id).find_by('LOWER(name) = ?', nome.downcase) ||
              Company.create!(account_id: @account.id, name: nome)
    contato.update!(company: empresa)
    :gravado
  end

  def gravar_no_card(atributo, valor)
    card = Crm::Config.enabled? ? Crm::Cards::ConversationCardFinder.new(account: @account).find(@conversation) : nil
    return :sem_card if card.blank?
    return unless @card_novo || card[atributo].blank?

    card.update!(atributo => valor)
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
    :gravado
  end
end
