# Recusa de mensagens ativas gravada no próprio contato (chat#713, chat#737).
#
# Quem recusou não recebe envio ativo (campanhas e follow-ups automáticos). Resposta a quem escreve segue normal.
# A marca é por contato, e o contato pertence a uma conta: a recusa numa conta não vale em outra.
#
# Regras:
# - opt_out! é idempotente e a primeira recusa vale. Se o contato já recusou, por qualquer origem, nada muda:
#   uma recusa manual não é trocada pela da Prospecção, e remover depois a da Prospecção não apaga a manual.
# - opt_in! limpa as três colunas. Com source:, só limpa se a recusa gravada veio daquela origem.
# - transfer_opt_out! troca a origem sem tirar a recusa, quando a origem gravada sai e outra ainda vale.
# - As três gravam sem rodar as validações do contato, para dado antigo (e-mail ou telefone fora do formato)
#   não impedir o registro da recusa. Rodam os callbacks, então o evento de contato atualizado sai normalmente.
# - As colunas não entram na edição comum do contato (ContactsController#permitted_params); só por estes métodos.
# - Contato novo, ou que muda de telefone ou e-mail, herda a recusa viva da conta (Contacts::OptOutInheritance).
module ContactOptOut
  extend ActiveSupport::Concern

  OPT_OUT_SOURCES = %w[prospecting email_unsubscribe manual].freeze

  included do
    belongs_to :opted_out_by, class_name: 'User', optional: true

    validates :opt_out_source, inclusion: { in: OPT_OUT_SOURCES }, allow_nil: true

    scope :opted_out, -> { where.not(opted_out_at: nil) }
    scope :not_opted_out, -> { where(opted_out_at: nil) }

    after_commit :inherit_opt_out_later, on: [:create, :update], if: :opt_out_inheritance_trigger?
  end

  def opted_out?
    opted_out_at.present?
  end

  # Retorna true quando gravou a recusa e false quando o contato já tinha recusado.
  def opt_out!(source:, by: nil)
    source = validated_opt_out_source(source)

    with_lock do
      next false if opted_out?

      assign_attributes(opted_out_at: Time.current, opt_out_source: source, opted_out_by_id: by&.id)
      save!(validate: false)
      log_opt_out_change('opt_out', source, by)
      true
    end
  end

  # Retorna true quando removeu a recusa e false quando não havia recusa (daquela origem, se informada).
  def opt_in!(by: nil, source: nil)
    with_lock do
      next false unless opted_out?
      next false if source.present? && opt_out_source != source.to_s

      removed_source = opt_out_source
      assign_attributes(opted_out_at: nil, opt_out_source: nil, opted_out_by_id: nil)
      save!(validate: false)
      log_opt_out_change('opt_in', removed_source, by)
      true
    end
  end

  # A recusa gravada com a origem from continua, agora com a origem to; a data da recusa fica a original.
  # Retorna false quando a recusa gravada não é da origem from.
  def transfer_opt_out!(from:, to:)
    to = validated_opt_out_source(to)

    with_lock do
      next false unless opted_out? && opt_out_source == from.to_s

      assign_attributes(opt_out_source: to, opted_out_by_id: nil)
      save!(validate: false)
      log_opt_out_change("transfer_from_#{from}", to, nil)
      true
    end
  end

  private

  def validated_opt_out_source(source)
    source = source.to_s
    raise ArgumentError, "origem de recusa desconhecida: #{source}" unless OPT_OUT_SOURCES.include?(source)

    source
  end

  def opt_out_inheritance_trigger?
    return false if opted_out?

    previously_new_record? || saved_change_to_phone_number? || saved_change_to_email?
  end

  def inherit_opt_out_later
    return unless Contacts::OptOutInheritance.possible_for?(self)

    Contacts::OptOutInheritanceJob.perform_later(account, [id])
  end

  def log_opt_out_change(action, source, by)
    Rails.logger.info("[contact_opt_out] #{action} account=#{account_id} contact=#{id} source=#{source} by=#{by&.id}")
  end
end
