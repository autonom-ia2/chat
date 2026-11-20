# A aba Empresas da Lista nova de Relacionamentos (#2894): busca por nome, domínio e CNPJ, e os grupos da tela. O CNPJ
# mora em additional_attributes; quantos clientes a empresa tem não é coluna e sai por subconsulta.
#
# #3078 — paridade com a lista de Empresas de hoje: as cinco ordens dela (nome, site, quando chegou, última conversa e
# número de pessoas), cada uma nos dois sentidos, e os filtros da gaveta "Mais filtros" (cidade e quando chegou, como
# na aba Pessoas). A foto da linha vem junto, sem uma consulta por empresa.
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
  CIDADE = "companies.additional_attributes->>'city'".freeze
  CHEGOU_EM = Relacionamentos::ConsultaDePessoas::CHEGOU_EM

  # Um texto da empresa como o nome ordena (Consulta.por_nome), no sentido pedido ('ASC' ou 'DESC'). Texto vazio conta
  # como ausente e vai para o fim nos dois sentidos. Tudo aqui é SQL escrito no código.
  def self.por_texto(expressao, direcao)
    "#{SearchService::SemAcento.sql("NULLIF(#{expressao}, '')")} COLLATE \"C\" #{direcao} NULLS LAST, companies.id"
  end

  # As ordens da lista de Empresas de hoje que a aba soma às de Consulta (última conversa, nome e mais novos). O empate
  # sai pela ordem de chegada.
  ORDENS_A_MAIS = {
    'conversa_mais_antiga' => 'companies.last_activity_at ASC NULLS LAST, companies.id',
    'nome_z_a' => "#{SearchService::SemAcento.sql('companies.name')} COLLATE \"C\" DESC, companies.id",
    'site_a_z' => por_texto('companies.domain', 'ASC'),
    'site_z_a' => por_texto('companies.domain', 'DESC'),
    'mais_antigos' => 'companies.created_at ASC, companies.id',
    'mais_pessoas' => 'companies.contacts_count DESC, companies.id',
    'menos_pessoas' => 'companies.contacts_count ASC, companies.id'
  }.freeze

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

  def ordens
    @ordens ||= super.merge(ORDENS_A_MAIS)
  end

  def consultados
    buscados(@account.companies, textos: TEXTOS, numeros: NUMEROS).where(da_cidade).where(que_chegou)
  end

  def com_o_que_a_linha_usa(empresas)
    self.class.com_clientes_contados(empresas).preload(avatar_attachment: :blob)
  end

  # Filtro vazio quer dizer "qualquer".
  def filtro(chave)
    @pedido.dig(:filtros, chave).presence
  end

  def da_cidade
    ["#{CIDADE} = ?", filtro(:cidade)] if filtro(:cidade)
  end

  def que_chegou
    ['companies.created_at >= ?', @agora - CHEGOU_EM.fetch(filtro(:chegou_em))] if filtro(:chegou_em)
  end

  def conferir_pedido
    super
    recusar("chegou_em desconhecido: #{filtro(:chegou_em)}") unless filtro(:chegou_em).nil? || CHEGOU_EM.key?(filtro(:chegou_em))
  end
end
