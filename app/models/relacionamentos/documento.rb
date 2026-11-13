# O CPF de uma pessoa ou o CNPJ de uma empresa (épico #1240, decisão R1): tabela própria do fork, com o número cifrado
# e busca por valor exato. O dono é a pessoa (`contact`) OU a empresa (`company`), nunca os dois; cada dono tem no
# máximo um CPF e um CNPJ (índices únicos do banco). O mesmo número pode estar em mais de um dono da conta: a base real
# tem a mesma pessoa cadastrada duas vezes, e quem casa pessoa por documento recebe todos e decide.
#
# `valor` é a forma de comparação do número (Relacionamentos::NumeroDeDocumento#canonico). Com as chaves do Active
# Record Encryption na instalação, vai cifrado de forma determinística: o mesmo número vira sempre o mesmo texto
# cifrado, e `where(valor: ...)` e o índice [account_id, tipo, valor] acham por valor exato. Sem as chaves fica em texto
# puro, como as outras colunas cifradas do fork, e tudo funciona igual. Busca por pedaço do número não existe aqui.
#
# O número inteiro não vai para log, erro, cache nem argumento de job: use `mascarado`. O `inspect` e o JSON do model
# saem sem ele, e as mensagens de validação não repetem valor. Quem precisa do número pede `valor` ou `formatado`.
#
# Quem apaga: o banco, em cascata, quando a pessoa ou a empresa sai (inclusive por caminho sem callback); a exclusão
# da conta apaga antes do DELETE da conta (Autonomia::ExclusaoDaConta).
# Quem grava e quem procura passa por Relacionamentos::Documentos.
class Relacionamentos::Documento < ApplicationRecord
  self.table_name = 'relacionamentos_documentos'

  TIPOS = [Relacionamentos::NumeroDeDocumento::CPF, Relacionamentos::NumeroDeDocumento::CNPJ].freeze

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :valor, deterministic: true if Chatwoot.encryption_configured?
  # O número nunca aparece em `inspect`, com ou sem a cifra.
  self.filter_attributes += [:valor]

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :company, optional: true

  validates :tipo, inclusion: { in: TIPOS }
  validate :numero_que_confere
  validate :um_dono_da_conta, if: -> { new_record? || will_save_change_to_contact_id? || will_save_change_to_company_id? }

  scope :da_conta, ->(account) { where(account_id: account.id) }
  scope :do_dono, ->(dono) { where(coluna_do(dono) => dono.id) }

  def self.coluna_do(dono)
    case dono
    when Contact then :contact_id
    when Company then :company_id
    else raise ArgumentError, 'o dono de um documento é uma pessoa (Contact) ou uma empresa (Company)'
    end
  end

  def dono
    contact || company
  end

  def numero
    Relacionamentos::NumeroDeDocumento.new(valor)
  end

  delegate :formatado, :mascarado, to: :numero

  # O JSON do model (as_json, to_json) é o que acaba em payload, cache e evento: vai sem o número.
  def serializable_hash(options = nil)
    super.except('valor')
  end

  private

  # O que se guarda é a forma de comparação de um número que confere, do tipo declarado.
  def numero_que_confere
    errors.add(:valor, :invalid) unless numero.valido? && numero.tipo == tipo && numero.canonico == valor
  end

  # O banco garante um dono só (CHECK) e que ele existe (chave), não de quem ele é: documento de uma conta apontando
  # para a pessoa de outra apareceria na busca errada.
  def um_dono_da_conta
    return errors.add(:base, :invalid) unless [contact_id, company_id].compact.one?

    errors.add(contact_id ? :contact : :company, :invalid) if dono.nil? || dono.account_id != account_id
  end
end
