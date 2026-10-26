# "A IA te ajudou" de CRM › Números (#1897, F3 do #1871): as conversas que um agente de IA passou para a pessoa no mês.
# O critério é o mesmo do filtro "Recebidas da IA" da caixa (#1889): a passagem gravada (Crm::Passagem.da_ia_para_equipe)
# somada à marca de espera de pessoa (`bot_handoff_waiting_since`, o robô passou e ninguém pegou ainda) nas conversas
# que estão com ela. As passagens que hoje não ficam gravadas são o #1887.
#
# `viraram`: dessas conversas, quantas têm uma venda do mês creditada à pessoa. `ia`: o nome da IA quando foi uma só.
class Crm::Numeros::IaAjudou
  MAX_CONVERSAS = 2_000

  def initialize(account:, user:, range:, ganhos:)
    @account = account
    @user = user
    @range = range
    @ganhos = ganhos
  end

  def perform
    ids = (passagens.map(&:first) + marcadas).uniq
    return if ids.empty?

    viraram = Crm::Relacao.cards_do_funil(@account).where(id: @ganhos, conversation_id: ids).distinct.count(:conversation_id)
    { ia: nome_da_ia, passou: ids.size, viraram: viraram }
  end

  private

  def passagens
    @passagens ||= Crm::Passagem.da_ia_para_equipe
                                .where(account_id: @account.id, para_type: 'User', para_id: @user.id, em: @range)
                                .pluck(:conversation_id, :de_type, :de_nome)
  end

  def nome_da_ia
    nomes = passagens.filter_map { |_id, de_type, de_nome| de_nome.presence if de_type.present? && de_type != 'User' }.uniq
    nomes.one? ? nomes.first : nil
  end

  # A marca vale a hora em que o robô passou; `additional_attributes` às vezes vem como JSON dentro de string.
  def marcadas
    chave = Conversation::BOT_HANDOFF_WAITING_SINCE_KEY
    @account.conversations.where(assignee_id: @user.id)
            .where('conversations.additional_attributes::text LIKE ?', "%#{Conversation.sanitize_sql_like(chave)}%")
            .limit(MAX_CONVERSAS)
            .pluck(:id, :additional_attributes)
            .filter_map { |id, atributos| id if no_mes?(marca_de(atributos, chave)) }
  end

  def marca_de(atributos, chave)
    atributos = JSON.parse(atributos) if atributos.is_a?(String)
    atributos.is_a?(Hash) ? atributos[chave] : nil
  rescue JSON::ParserError
    nil
  end

  def no_mes?(valor)
    momento = valor.present? && Time.zone.parse(valor.to_s)
    momento.present? && @range.cover?(momento)
  rescue ArgumentError
    false
  end
end
