# A aba Empresas da Lista nova de Relacionamentos (#2894): busca por nome, domínio e CNPJ, e os grupos da tela. O CNPJ
# mora em additional_attributes; quantos clientes a empresa tem não é coluna e sai por subconsulta.
class Relacionamentos::ConsultaDeEmpresas < Relacionamentos::Consulta
  # Só gente da mesma conta da empresa: contato de outra conta apontando para ela não conta.
  CLIENTES = <<~SQL.squish.freeze
    FROM contacts WHERE contacts.company_id = companies.id AND contacts.account_id = companies.account_id
      AND contacts.contact_type = #{Contact.contact_types[:customer]}
  SQL
  GRUPOS = {
    'todas' => 'TRUE',
    'com_clientes' => "EXISTS (SELECT 1 #{CLIENTES})",
    'sem_pessoas' => 'companies.contacts_count = 0',
    'sem_conversa_3_meses' => 'companies.last_activity_at IS NULL OR companies.last_activity_at < :sumiu'
  }.freeze
  TEXTOS = %w[companies.name companies.domain].freeze
  NUMEROS = ["companies.additional_attributes->>'cnpj'"].freeze

  # As empresas com o número de clientes de cada uma, que a linha da lista e a ficha da empresa (#2895) leem.
  def self.com_clientes_contados(empresas)
    empresas.select("companies.*, (SELECT COUNT(*) #{CLIENTES}) AS customers_count")
  end

  private

  def tabela
    'companies'
  end

  def grupos
    GRUPOS
  end

  def consultados
    buscados(@account.companies, textos: TEXTOS, numeros: NUMEROS)
  end

  def com_o_que_a_linha_usa(empresas)
    self.class.com_clientes_contados(empresas)
  end
end
