# A receita de uma automação num salvamento (#2414, F2 #2452). Imutável: depois de gravada, não muda nem sai pelo
# modelo. Quem já está no meio de uma execução termina na versão em que entrou (D10).
#
# `digest` é o SHA-256 da receita com as chaves ordenadas, para comparar receitas sem depender da ordem.
# A receita é conferida ao salvar (F3, #2459): o formato pelo esquema e, com ele certo, o que só o código sabe (ação
# permitida, corpo da ação, caminhos de valor) por Autonomia::Automacao::Receita. O autor é da conta.
class Autonomia::Automacao::Versao < ApplicationRecord
  self.table_name = 'autonomia_automacao_versoes'

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao', inverse_of: :versoes
  belongs_to :autor, class_name: 'User', optional: true

  validates :numero, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :automacao_id }
  validates :receita, json_schema: { schema: ::Autonomia::Automacao::Receita::ESQUEMA }
  validate :receita_executavel
  validate :da_mesma_conta

  before_validation :calcular_digest, on: :create

  def readonly?
    persisted? || super
  end

  private

  def da_mesma_conta
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
    errors.add(:autor, :invalid) if autor && account && !account.account_users.exists?(user_id: autor.id)
  end

  def receita_executavel
    return unless ::Autonomia::Automacao::Receita.esquema_valido?(receita)

    ::Autonomia::Automacao::Receita.new(receita, conta: account).problemas.each { |problema| errors.add(:receita, problema) }
  end

  def calcular_digest
    self.digest = Digest::SHA256.hexdigest(ordenada(receita).to_json)
  end

  def ordenada(valor)
    case valor
    when Hash then valor.to_h { |chave, item| [chave.to_s, ordenada(item)] }.sort.to_h
    when Array then valor.map { |item| ordenada(item) }
    else valor
    end
  end
end
