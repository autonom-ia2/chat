# Excluir de vez cards arquivados (#2096, Parte C), um ou vários. Só administrador, só card arquivado e com a palavra
# EXCLUIR digitada. Apaga o card e todo o histórico dele; a conversa do cliente fica (Crm::Cards::Excluidor).
# Tudo ou nada: um card que não pode sair recusa o pedido inteiro, e nada é apagado. O serviço confere o arquivado de
# novo, sob a trava: um card restaurado no meio do caminho não é apagado (422 not_archived).
# Em todo 422 depois de começar, `canceled_meeting_ids` diz quais reuniões futuras já tinham sido canceladas no calendário
# (o cliente já foi avisado; o card tem a atividade "reunião cancelada").
class Api::V1::Accounts::Crm::Cards::PermanentDeletionsController < Api::V1::Accounts::Crm::BaseController
  CONFIRMACAO = 'EXCLUIR'.freeze
  MAX_CARDS = ::Crm::Cards::BulkAction::MAX_IDS

  before_action :ensure_administrator!
  before_action :ensure_card_ids!

  def create
    return render_error('crm.permanent_delete.not_archived', card_ids: nao_arquivados) if nao_arquivados.any?
    return render_error('crm.permanent_delete.confirmation_mismatch') unless params[:confirmation].to_s.strip == CONFIRMACAO

    render json: { payload: { deleted_ids: excluir!(cards.map(&:id)) } }
  rescue ::Crm::Cards::Excluidor::ReuniaoNaoCancelada => e
    render_error('crm.permanent_delete.meeting_cancel_failed', meeting_id: e.meeting_id, canceled_meeting_ids: e.canceladas)
  rescue ::Crm::ExclusaoDefinitiva::Mudou => e
    # Restaurado (ou apagado por outro pedido) enquanto este esperava o calendário ou a trava: nada saiu.
    render_error("crm.permanent_delete.#{e.motivo}", canceled_meeting_ids: e.canceladas)
  end

  private

  def ensure_administrator!
    render_error('crm.permanent_delete.admin_only', status: :forbidden) unless policy(::Crm::Card).permanent_delete?
  end

  def ensure_card_ids!
    return render_error('crm.permanent_delete.no_cards') if card_ids.empty?

    render_error('crm.permanent_delete.too_many_cards', max: MAX_CARDS) if card_ids.size > MAX_CARDS
  end

  # Card de outra conta, ou que a pessoa não vê, é 404 para o pedido inteiro.
  def cards
    @cards ||= policy_scope(::Crm::Card).where(id: card_ids).to_a.tap do |encontrados|
      raise ActiveRecord::RecordNotFound if encontrados.size != card_ids.size
    end
  end

  def nao_arquivados
    cards.reject(&:archived?).map(&:id).sort
  end

  def excluir!(ids)
    ::Crm::Cards::Excluidor.new(account: Current.account, card_ids: ids).perform do |apagados|
      ::Crm::ExclusaoDefinitiva.auditar!(account: Current.account, user: Current.user, alvo: 'cards', card_ids: apagados)
    end
  end

  # Ids inteiros e únicos; o que não for número é ignorado (e um pedido só com isso fica vazio).
  def card_ids
    @card_ids ||= Array(params[:card_ids]).filter_map { |id| Integer(id.to_s, 10, exception: false) }.uniq
  end

  def render_error(code, status: :unprocessable_entity, **details)
    render json: { error: code }.merge(details), status: status
  end
end
