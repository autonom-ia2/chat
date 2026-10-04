# As vigias padrão do Guia (#935), de `lib/operator_guide/vigias-padrao.yml`.
#
# Plantadas uma vez por conta, na primeira vez que um administrador abre o Guia, em nome dele. A marca
# fica na conta: quem apagar uma vigia padrão não a vê voltar na próxima abertura.
module Autonomia::Guide::VigiasPadrao
  ARQUIVO = Rails.root.join('lib/operator_guide/vigias-padrao.yml')
  MARCA = 'guia_vigias_padrao_em'.freeze

  module_function

  def todas
    @todas ||= YAML.safe_load(ARQUIVO.read).freeze
  end

  def plantar(account, account_user)
    return unless account_user&.administrator? && account.internal_attributes[MARCA].blank?

    ActiveRecord::Base.transaction do
      todas.each do |dados|
        ::Autonomia::Guide::Vigia.create!(dados.merge('account' => account, 'criado_por' => account_user.user, 'origem' => 'padrao'))
      end
      # A marca não é configuração da conta: vai direto, sem os callbacks da conta.
      account.update_columns(internal_attributes: account.internal_attributes.merge(MARCA => Time.current.iso8601)) # rubocop:disable Rails/SkipsModelValidations
    end
  rescue ActiveRecord::RecordInvalid => e
    # Conta no teto de vigias, ou leitura que não existe nesta conta: o Guia abre do mesmo jeito.
    Rails.logger.warn("[autonomia][guide][vigias_padrao] account=#{account.id} #{e.message}")
  end
end
