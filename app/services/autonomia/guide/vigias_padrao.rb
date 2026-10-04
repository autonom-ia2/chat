# As vigias padrão do Guia (#935), de `lib/operator_guide/vigias-padrao.yml`.
#
# Plantadas na primeira pergunta de um administrador, em nome dele. A conta guarda QUAIS já recebeu
# (pelo nome): vigia padrão nova chega também às contas antigas, e a que a pessoa apagou não volta.
module Autonomia::Guide::VigiasPadrao
  ARQUIVO = Rails.root.join('lib/operator_guide/vigias-padrao.yml')
  # Marca do primeiro plantio (#935), de antes de a conta guardar os nomes.
  MARCA = 'guia_vigias_padrao_em'.freeze
  PLANTADAS = 'guia_vigias_padrao_plantadas'.freeze

  module_function

  def todas
    @todas ||= YAML.safe_load(ARQUIVO.read).freeze
  end

  def plantar(account, account_user)
    return unless account_user&.administrator?

    ja = ja_plantadas(account)
    novas = todas.reject { |dados| ja.include?(dados['nome']) }
    return if novas.empty?

    ActiveRecord::Base.transaction do
      novas.each do |dados|
        ::Autonomia::Guide::Vigia.create!(dados.except('nova_em').merge('account' => account, 'criado_por' => account_user.user,
                                                                        'origem' => 'padrao'))
      end
      marcar(account, ja + novas.pluck('nome'))
    end
  rescue ActiveRecord::RecordInvalid => e
    # Conta no teto de vigias, ou leitura que não existe nesta conta: o Guia abre do mesmo jeito.
    Rails.logger.warn("[autonomia][guide][vigias_padrao] account=#{account.id} #{e.message}")
  end

  # Conta do primeiro plantio, sem a lista: recebeu todas as que não são `nova_em`.
  def ja_plantadas(account)
    lista = account.internal_attributes[PLANTADAS]
    return Array(lista) if lista
    return [] if account.internal_attributes[MARCA].blank?

    todas.reject { |dados| dados['nova_em'] }.pluck('nome')
  end

  # A marca não é configuração da conta: vai direto, sem os callbacks da conta.
  def marcar(account, nomes)
    atributos = account.internal_attributes.merge(PLANTADAS => nomes, MARCA => account.internal_attributes[MARCA] || Time.current.iso8601)
    account.update_columns(internal_attributes: atributos) # rubocop:disable Rails/SkipsModelValidations
  end
end
