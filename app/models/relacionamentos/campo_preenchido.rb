# == Schema Information
#
# Table name: relacionamentos_campos_preenchidos
#
#  id                     :bigint           not null, primary key
#  campo                  :string           not null
#  devolvido_em           :datetime
#  tipo_anterior          :integer
#  valor_posto_hash       :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  campaign_import_row_id :bigint           not null
#  contact_id             :bigint
#
# Indexes
#
#  idx_rel_campos_preenchidos_linha_campo                  (campaign_import_row_id,campo) UNIQUE
#  index_relacionamentos_campos_preenchidos_on_account_id  (account_id)
#  index_relacionamentos_campos_preenchidos_on_contact_id  (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_import_row_id => campaign_import_rows.id) ON DELETE => cascade
#

# "Trazer minha lista" (#2896): um campo que uma linha da lista preencheu, anotado na hora da gravação
# (Relacionamentos::Trazer::CamposPreenchidos) para o Desfazer devolver só isso (Relacionamentos::Trazer::CampoQueVolta).
#
# A lista só preenche o que estava vazio, então "devolver" é esvaziar o campo, e só quando o valor de hoje ainda é o que
# a lista pôs. Para reconhecer isso sem guardar o valor, a linha guarda o resumo dele com um segredo derivado do
# `secret_key_base` (`resumo`): não dá para voltar do resumo ao valor nem para refazê-lo sem o segredo. O resumo leva
# junto o id da linha da importação e o campo: o mesmo telefone em duas linhas tem resumos diferentes, e nenhuma linha
# serve de dicionário para outra.
#
# Campos: os da ficha (`DA_FICHA`), a cidade, a empresa (o id da empresa a que a lista ligou a pessoa), cliente (a data
# em que a lista marcou a pessoa, com o `tipo_anterior` dela), o telefone da empresa (que fica na empresa da linha, não
# na pessoa) e cada informação da pessoa (`informacao:<chave do atributo>`).
class Relacionamentos::CampoPreenchido < ApplicationRecord
  self.table_name = 'relacionamentos_campos_preenchidos'

  # campo => atributo do contato.
  DA_FICHA = { 'nome' => 'name', 'telefone' => 'phone_number', 'email' => 'email' }.freeze
  CIDADE = 'cidade'.freeze
  EMPRESA = 'empresa'.freeze
  CLIENTE = 'cliente'.freeze
  TELEFONE_DA_EMPRESA = 'telefone_da_empresa'.freeze
  INFORMACAO = 'informacao:'.freeze
  SAL = 'relacionamentos/trazer/campos_preenchidos'.freeze
  # Entre o id da linha, o campo e o valor. O id é um número inteiro e o valor vai em JSON, que escreve o caractere
  # nulo como \u0000; o campo não pode ter o caractere nulo (o banco não o aceita em texto). Nenhuma combinação se
  # confunde com outra.
  SEPARADOR = "\0".freeze

  # A conta e a linha são garantidas pelo banco (NOT NULL e a chave da linha). Sem a validação de presença, marcar o
  # campo como devolvido não relê a conta nem a linha a cada registro.
  belongs_to :account, optional: true
  belongs_to :campaign_import_row, optional: true

  scope :pendentes, -> { where(devolvido_em: nil) }
  scope :da_importacao, lambda { |importacao|
    where(account_id: importacao.account_id, campaign_import_row_id: importacao.campaign_import_rows.select(:id))
  }

  # O valor vai em JSON para texto, número e sim/não terem um caminho só e saírem iguais antes e depois do banco.
  def self.resumo(linha_id, campo, valor)
    OpenSSL::HMAC.hexdigest('SHA256', segredo, [Integer(linha_id), campo, valor.to_json].join(SEPARADOR))
  end

  def self.segredo
    @segredo ||= Rails.application.key_generator.generate_key(SAL, 32)
  end

  def self.da_informacao(chave)
    "#{INFORMACAO}#{chave}"
  end

  # A data de cliente como é comparada: o instante exato que o banco guarda (microssegundos), em UTC.
  def self.instante(quando)
    quando&.utc&.iso8601(6)
  end

  # A chave do atributo, quando o campo é uma informação da pessoa.
  def informacao
    campo.delete_prefix(INFORMACAO) if campo.start_with?(INFORMACAO)
  end

  # O campo fica na empresa da linha, não na pessoa.
  def da_empresa?
    campo == TELEFONE_DA_EMPRESA
  end

  # O valor de hoje ainda é o que a lista pôs. Campo vazio nunca é: a lista não põe vazio.
  def mesmo_valor?(valor)
    !valor.nil? && valor_posto_hash == self.class.resumo(campaign_import_row_id, campo, valor)
  end
end
