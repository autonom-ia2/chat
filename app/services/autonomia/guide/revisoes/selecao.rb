# Quais conversas a revisão lê (#3158, B8b): o filtro que o modelo montou, com a permissão de quem pergunta.
#
# O Guia é de todos (#3117), e o Copilot é só de administrador: aqui, quem não é administrador só revisa as conversas
# que vê na caixa (`Conversations::PermissionFilterService`, com `for_reading`, como a lista de conversas).
#
# O período são dias de calendário no fuso da conta (`de` e `ate` incluídos). Com `notas`, vale a data da nota de
# satisfação; sem, a data em que a conversa começou. A ordem é da mais nova para a mais antiga.
class Autonomia::Guide::Revisoes::Selecao
  Recusado = Class.new(StandardError)

  NOTAS = (1..5)
  STATUS = Conversation.statuses.keys.freeze

  attr_reader :de, :ate

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.to_h.stringify_keys
    ler_datas
  end

  # -> os ids das conversas, até `Revisao::MAX_IDS`.
  def ids
    ids = escopo.order(id: :desc).limit(::Autonomia::Guide::Revisao::MAX_IDS + 1).pluck(:id)
    if ids.size > ::Autonomia::Guide::Revisao::MAX_IDS
      raise Recusado, "Achei mais de #{::Autonomia::Guide::Revisao::MAX_IDS} conversas. Peça um período menor ou um filtro a mais."
    end

    ids
  end

  # O filtro como ficou, para o cartão, o registro e a IA saberem como as conversas foram escolhidas.
  def selecao
    { 'de' => de.iso8601, 'ate' => ate.iso8601, 'notas' => notas.presence, 'etiqueta' => etiqueta,
      'caixa_id' => caixa_id, 'agente_id' => agente_id, 'status' => status }.compact
  end

  private

  def escopo
    escopo = Conversations::PermissionFilterService.new(@account.conversations, @user, @account, for_reading: true).perform
    escopo = notas.present? ? com_nota(escopo) : escopo.where(created_at: inicio...fim)
    escopo = escopo.tagged_with(etiqueta) if etiqueta
    escopo = escopo.where(inbox_id: caixa_id) if caixa_id
    escopo = escopo.where(assignee_id: agente_id) if agente_id
    escopo = escopo.where(status: status) if status
    escopo
  end

  def com_nota(escopo)
    respostas = CsatSurveyResponse.where(account_id: @account.id, rating: notas, created_at: inicio...fim)
    escopo.where(id: respostas.select(:conversation_id))
  end

  def ler_datas
    @de = Date.iso8601(@params['de'].to_s)
    @ate = Date.iso8601(@params['ate'].to_s)
    raise Recusado, 'ate não pode vir antes de de.' if @ate < @de
  rescue Date::Error
    raise Recusado, 'de e ate precisam ser datas no formato AAAA-MM-DD.'
  end

  def fuso = Filters::DateFilterHelper.fuso_da_conta(@account)
  def inicio = de.in_time_zone(fuso)
  def fim = ate.next_day.in_time_zone(fuso)

  def notas
    @notas ||= Array(@params['notas']).map(&:to_i).select { |nota| NOTAS.cover?(nota) }.uniq.sort
  end

  def etiqueta = @params['etiqueta'].to_s.strip.presence
  def caixa_id = inteiro('caixa_id')
  def agente_id = inteiro('agente_id')

  def status
    valor = @params['status'].to_s.presence
    return nil if valor.nil?
    raise Recusado, "status precisa ser um destes: #{STATUS.join(', ')}." unless STATUS.include?(valor)

    valor
  end

  def inteiro(nome)
    valor = @params[nome].to_s.strip
    valor.empty? ? nil : Integer(valor, 10)
  rescue ArgumentError
    raise Recusado, "#{nome} precisa ser o número lido da conta."
  end
end
