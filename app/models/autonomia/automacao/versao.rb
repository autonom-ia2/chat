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

  # O desfazer do Guia (#2889): a versão que o Guia acabou de criar sai como se nunca tivesse existido, se nada a usou.
  # Fica, com o motivo do conflito, quando uma execução a usou, quando já há versão mais nova, ou quando ainda é a
  # ativa ao lado de outras (o desfazer não conseguiu voltar a anterior, porque alguém mexeu depois). A única versão da
  # automação que o Guia criou sai, e a automação sai em seguida. Fora daqui a versão continua imutável (`readonly?`).
  # A trava na automação (da mesma conta) faz a corrida com quem salva ou liga no mesmo instante virar conflito.
  def apagar_ao_desfazer
    dona = Autonomia::Automacao::Definicao.find_by(id: automacao_id, account_id: account_id)
    return 'mudou_depois' if dona.nil?

    dona.with_lock do
      motivo = motivo_para_ficar(dona)
      next motivo if motivo

      self.class.where(id: id).delete_all
      nil
    end
  end

  # A receita como sai para a tela. O show, o index e o histórico passam todos por aqui: o que precisar ser escondido
  # de quem só vê (a URL do webhook, #2450) é escondido num lugar só.
  def receita_para_tela
    receita
  end

  private

  # A ativa de uma automação que já foi ligada fica com ela: sem versão, a automação de quem ligou ficaria vazia.
  def motivo_para_ficar(dona)
    return 'versao_ja_executada' if usada?
    return 'versao_mais_nova' if irmas.exists?(['numero > ?', numero])
    return unless dona.versao_ativa_id == id

    dona.ja_ligada? ? 'automacao_ja_ligada' : ('mudou_depois' if irmas.where.not(id: id).exists?)
  end

  def irmas = self.class.where(automacao_id: automacao_id)
  def usada? = Autonomia::Automacao::Execucao.exists?(versao_id: id)

  def da_mesma_conta
    errors.add(:automacao, :invalid) if automacao && automacao.account_id != account_id
    errors.add(:autor, :invalid) if autor && account && !account.account_users.exists?(user_id: autor.id)
  end

  def receita_executavel
    return unless ::Autonomia::Automacao::Receita.esquema_valido?(receita)

    problemas = ::Autonomia::Automacao::Receita.new(receita, conta: account, account_user: autor_na_conta).problemas
    problemas.each { |problema| errors.add(:receita, problema) }
  end

  def autor_na_conta = autor && account&.account_users&.find_by(user_id: autor.id)

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
