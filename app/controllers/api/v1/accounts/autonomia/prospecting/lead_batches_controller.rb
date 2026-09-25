# Descartar e criar contatos em lote (#732, item 10). As rotas ficam em leads/ (POST leads/discard e leads/contacts) e
# pedem a prospecção (prospecting_manage), como as outras ações do lead; os leads vêm do que a pessoa vê (leads_scope).
class Api::V1::Accounts::Autonomia::Prospecting::LeadBatchesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  # Descartar, no painel e em lote, sempre com motivo. Devolve os leads como GET leads/:id devolve para essa pessoa:
  # sem o bloco técnico da nota para quem não é administrador (#732, item 9).
  def discard
    result = ::Autonomia::Prospecting::LeadDiscard.new(
      account: Current.account, user: Current.user, lead_ids: params[:lead_ids], reason: params[:reason], leads_scope: leads_scope
    ).perform
    leads = leads_scope.includes(*lead_preloads).where(id: result.leads.map(&:id))
    render json: { payload: { leads: leads.map { |lead| visible_lead_payload(lead_payload_builder.build(lead)) },
                              missing_lead_ids: result.missing_lead_ids } }
  rescue ::Autonomia::Prospecting::LeadDiscard::Error => e
    render_batch_error('discard', 'lead_discard', e.message, max: ::Autonomia::Prospecting::LeadDiscard::MAX_LEADS)
  end

  # O mesmo contato do lead avulso (ContactConverter), com resumo por lead.
  def contacts
    result = ::Autonomia::Prospecting::ContactBatch.new(
      account: Current.account, user: Current.user, lead_ids: params[:lead_ids], leads_scope: leads_scope
    ).perform
    render json: { payload: { created: result.created, existing: result.existing, failed: result.failed } }
  rescue ::Autonomia::Prospecting::ContactBatch::Error => e
    render_batch_error('contact_batch', 'contact_batch', e.message, max: ::Autonomia::Prospecting::ContactBatch::MAX_LEADS)
  end

  private

  # Recusa do lote inteiro: a frase do I18n em `error`, o código de máquina em `code`.
  def render_batch_error(code_scope, i18n_scope, reason, max:)
    render json: { error: I18n.t("autonomia.prospecting.#{i18n_scope}.errors.#{reason}", max: max), code: "prospecting.#{code_scope}.#{reason}" },
           status: :unprocessable_entity
  end
end
