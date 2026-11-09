# O "ausente até" da pessoa na conta (#2414 G23, #2737): férias, licença. Vazio é presente; passou a data, volta a ser
# presente sozinho, sem ninguém limpar o campo. A Automação livre lê `ausente?` (Valores, `*.responsavel_ausente`).
#
# Texto que não é data é recusado, em vez de virar vazio calado: vazio apagaria a ausência marcada.
module AusenciaDaPessoa
  extend ActiveSupport::Concern

  included do
    validate :ausente_ate_e_data
  end

  class_methods do
    # A pessoa está ausente nesta conta (e só nela)? Sem pessoa (sem responsável), ninguém está ausente.
    def ausente_na_conta?(conta_id, usuario_id)
      return false if usuario_id.nil?

      find_by(account_id: conta_id, user_id: usuario_id)&.ausente? || false
    end
  end

  def ausente?(agora = Time.current)
    ausente_ate.present? && ausente_ate > agora
  end

  private

  # Só nulo ou texto vazio limpa: espaço, false ou texto sem data viram nulo no cast, e não podem apagar calados.
  def ausente_ate_e_data
    return if ausente_ate.present? || [nil, ''].include?(ausente_ate_before_type_cast)

    errors.add(:ausente_ate, :invalid)
  end
end
