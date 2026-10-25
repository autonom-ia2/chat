# LGPD (#2096): excluir o contato e escolher o que acontece com os cards dele (decisão 1 do protótipo), sem padrão:
# - `cards: 'delete'`: apaga de vez os cards junto, abertos, ganhos ou arquivados;
# - `cards: 'keep'`: mantém os cards sem dado pessoal ("Cliente removido #id"; Crm::Cards::Anonimizador).
# Contato com cards e sem a escolha: 422 contact_cards_choice_required, e nada sai. Nos dois modos, a reunião futura é
# cancelada antes (decisão 10); se o calendário falhar, nada é apagado. Só administrador (também no EE: quem tem
# contact_delete exclui o contato pelo DELETE de sempre, que mantém os cards sem dado pessoal) e com EXCLUIR digitado.
#
# Rota própria, e não um parâmetro no DELETE do contato: assim o Guia não a alcança (Autonomia::Guide::Acoes::SO_NA_TELA).
#
# GET preview: os cards do contato, para a janela perguntar "Apagar também os N cards deste contato?". Só o que a
# janela mostra (funil, etapa, valor, desfecho e a reunião futura), sem título nem dado do cliente.
class Api::V1::Accounts::Crm::Contacts::PermanentDeletionsController < Api::V1::Accounts::Crm::BaseController
  CONFIRMACAO = 'EXCLUIR'.freeze

  before_action :ensure_feature!
  before_action :fetch_contact
  before_action :ensure_admin!
  before_action :ensure_deletable!, only: :create

  def preview
    cards = Current.account.crm_cards.where(contact_id: @contact.id).includes(:pipeline, :stage).order(:id).to_a
    render json: { payload: { contact_id: @contact.id, cards_count: cards.size, cards: cards_da_previa(cards), timezone: fuso_da_conta } }
  end

  def create
    resultado = ::Crm::ExclusaoDefinitiva.contato!(contact: @contact, user: Current.user, modo: modo)
    render json: { payload: resultado.merge(mode: modo) }
  rescue ::Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada => e
    render_error('crm.permanent_delete.meeting_cancel_failed', meeting_id: e.meeting_id, canceled_meeting_ids: e.canceladas)
  rescue ::Crm::ExclusaoDefinitiva::Mudou => e
    render_error("crm.permanent_delete.#{e.motivo}", canceled_meeting_ids: e.canceladas)
  rescue ActiveRecord::Deadlocked
    # Impasse que se repetiu nas retentativas (#2143): nada saiu, e a pessoa tenta de novo, como no DELETE do contato.
    render json: { message: I18n.t('contacts.busy_try_again'), error: 'contact_busy' }, status: :conflict
  end

  private

  # O fuso da conta, para a janela escrever a data da reunião como a conta vê (e não o fuso do navegador).
  def fuso_da_conta
    ::Crm::Timezone::Resolver.new(account: Current.account).zone_or_default.tzinfo.name
  end

  # A rota só existe para a conta com a flag crm_arquivados (#2143): a tela nem aparece sem ela, e o servidor confere.
  def ensure_feature!
    head :not_found unless ::Crm::Cards::Anonimizador.ligado?(Current.account)
  end

  def fetch_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def ensure_admin!
    render_error('crm.permanent_delete.admin_only', status: :forbidden) unless pode_excluir?
  end

  def ensure_deletable!
    return render_error('crm.permanent_delete.confirmation_mismatch') unless params[:confirmation].to_s.strip == CONFIRMACAO
    return render_error('crm.permanent_delete.invalid_cards_mode') if modo.present? && modo_invalido?
    return render_error('crm.permanent_delete.contact_cards_choice_required', cards_count: cards_count) if modo.blank?

    # A mesma trava do DELETE do contato: quem está online agora não é excluído.
    render_error('crm.permanent_delete.contact_online') if ::OnlineStatusTracker.get_presence(Current.account.id, 'Contact', @contact.id)
  end

  # Sem card, não há o que escolher: o contato sai e a auditoria registra o modo 'delete'.
  def modo
    @modo ||= params[:cards].to_s.presence || (cards_count.zero? ? ::Crm::ExclusaoDefinitiva::CARDS_APAGAR : nil)
  end

  def modo_invalido?
    ::Crm::ExclusaoDefinitiva::MODOS_DO_CONTATO.exclude?(modo)
  end

  def cards_count
    @cards_count ||= Current.account.crm_cards.where(contact_id: @contact.id).count
  end

  def cards_da_previa(cards)
    reunioes = proximas_reunioes(cards.map(&:id))
    cards.map do |card|
      {
        id: card.id,
        pipeline: card.pipeline.slice(:id, :name, :status, :counts_as_sale),
        stage_name: card.stage.name,
        # Sem o Crm::ValorDeVenda.ve? e sem ve_o_card?: esta rota é só de administrador (ensure_admin!), que vê todo card
        # e todo valor. Outra função aqui exigiria os dois.
        value_cents: card.value_cents,
        currency: card.currency,
        status: card.status,
        # O desfecho guardado ao arquivar um card fechado (Parte A, #2094: Crm::Card::DESFECHO_ARQUIVADO).
        desfecho: card.metadata.to_h['desfecho_arquivado'],
        upcoming_meeting: reunioes[card.id]
      }
    end
  end

  # A reunião futura mais próxima de cada card: a que será cancelada (com aviso ao cliente no Google e na Microsoft).
  def proximas_reunioes(card_ids)
    ::Crm::Meeting.where(account_id: Current.account.id, card_id: card_ids).upcoming.order(:starts_at, :id)
                  .each_with_object({}) do |meeting, por_card|
      por_card[meeting.card_id] ||= { starts_at: meeting.starts_at, provider: meeting.provider }
    end
  end

  def pode_excluir?
    policy(::Crm::Card).permanent_delete? && policy(@contact).destroy?
  end

  def render_error(code, status: :unprocessable_entity, **details)
    render json: { error: code }.merge(details), status: status
  end
end
