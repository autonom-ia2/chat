# Nome curto da página nova (#1282, #1299): o `<página>` de `/a/<conta>/<página>`. Opcional (página sem nome segue em
# `/book/<uuid>`), gravado em minúsculas e único dentro da conta. As regras de formato moram em
# `Crm::BookingV2::ShortName`; o `<conta>` é o endereço da conta (`Crm::BookingV2::AccountAddress`), que nasce junto
# com a primeira gravação de uma página nova da conta.
#
# Unicidade em duas camadas: a validação dá o erro legível, e o índice único do banco garante quando duas páginas
# pedem o mesmo nome ao mesmo tempo (as duas passam pela validação). Quem perde no índice recebe o mesmo erro de
# validação ("taken"), não um erro de banco.
#
# Quando a página ganha o nome, as pessoas que já atendem nela ganham o apelido do link curto de cada uma
# (`Crm::BookingV2::PersonNames`).
module Crm::BookingShortName
  extend ActiveSupport::Concern

  SHORT_NAME_INDEX = 'index_crm_agent_booking_profiles_on_account_and_short_name'.freeze

  included do
    before_validation :normalize_short_name
    validate :short_name_must_be_usable, if: -> { short_name.present? && will_save_change_to_short_name? }
    around_save :report_short_name_race
    after_save :name_people_in_short_link, if: -> { saved_change_to_short_name? && short_name.present? }
    after_commit :ensure_booking_account_address, on: %i[create update], if: :new_page?
  end

  # O `<conta>` do link curto desta página, ou nil se a conta ainda não tem endereço. Só lê: o endereço da conta nasce
  # quando uma página nova é gravada (criar, salvar, publicar) e no preenchimento do deploy, nunca numa leitura.
  def booking_account_address
    return @booking_account_address if defined?(@booking_account_address)

    @booking_account_address = ::Crm::BookingV2::AccountAddress.name_for_id(account_id)
  end

  def reload(*)
    remove_instance_variable(:@booking_account_address) if defined?(@booking_account_address)
    super
  end

  private

  def normalize_short_name
    self.short_name = ::Crm::BookingV2::ShortName.normalize(short_name)
  end

  def short_name_must_be_usable
    return errors.add(:short_name, 'only_new_pages') unless new_page?

    problem = ::Crm::BookingV2::ShortName.problem(short_name, account_id: account_id, except_id: id)
    errors.add(:short_name, problem) if problem
  end

  # Em transação própria: o erro do índice desfaz só esta gravação, não a transação de quem chamou.
  def report_short_name_race(&)
    self.class.transaction(requires_new: true, &)
  rescue ActiveRecord::RecordNotUnique => e
    raise unless e.message.include?(SHORT_NAME_INDEX)

    errors.add(:short_name, 'taken')
    raise ActiveRecord::RecordInvalid, self
  end

  # Depois do commit da página, fora da transação dela: a gravação da página não espera nem segura a linha do
  # endereço, e duas gravações (ou a página e o preenchimento do deploy) não se travam uma à outra. A página nunca deixa
  # de ser gravada por causa do endereço: se ele não nasce agora (disputa perdida em todas as voltas, trava, banco
  # fora), fica o registro no log, a página segue com o link comprido e a próxima gravação tenta de novo.
  def ensure_booking_account_address
    @booking_account_address = ::Crm::BookingV2::AccountAddress.ensure!(account)
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("[booking_account_address] conta #{account_id}: #{e.message}")
    @booking_account_address = nil
  end

  def name_people_in_short_link
    ::Crm::BookingV2::PersonNames.new(self).assign_missing!
  end
end
