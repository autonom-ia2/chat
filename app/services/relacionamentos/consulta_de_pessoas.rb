# A aba Pessoas da Lista nova de Relacionamentos (#2894): a mesma base da lista de contatos de hoje, com a busca (nome,
# e-mail, empresa, telefone e CPF), os filtros da gaveta (empresa, etiqueta, cidade e quando chegou) e os grupos.
# "Falou" é o last_activity_at como ele é: só mensagem que a pessoa mandou. Vale para a conta inteira.
class Relacionamentos::ConsultaDePessoas < Relacionamentos::Consulta
  GRUPOS = {
    'todos' => 'TRUE',
    'clientes' => "contacts.contact_type = #{Contact.contact_types[:customer]}",
    'falou_ha_pouco' => 'contacts.last_activity_at >= :falou_ha_pouco',
    'sumiu_1_a_3_meses' => 'contacts.last_activity_at < :falou_ha_pouco AND contacts.last_activity_at >= :sumiu',
    'sumiu_mais_de_3_meses' => 'contacts.last_activity_at < :sumiu',
    'nunca_conversou' => 'contacts.last_activity_at IS NULL',
    'nao_quer_mensagens' => 'contacts.opted_out_at IS NOT NULL'
  }.freeze
  TEXTOS = ['contacts.name', 'contacts.email', "contacts.additional_attributes->>'company_name'"].freeze
  NUMEROS = ['contacts.phone_number', "contacts.custom_attributes->>'cpf'"].freeze
  CHEGOU_EM = { 'ultimos_7' => 7.days, 'ultimos_30' => 30.days, 'ultimos_90' => 90.days }.freeze
  # A etiqueta pelo nome exato, sem o tagged_with (que parte o texto nas vírgulas). Etiqueta com dono não é da pessoa.
  COM_A_ETIQUETA = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM taggings INNER JOIN tags ON tags.id = taggings.tag_id
            WHERE taggings.taggable_type = 'Contact' AND taggings.taggable_id = contacts.id
              AND taggings.context = 'labels' AND taggings.tagger_id IS NULL AND tags.name = ?)
  SQL
  # O que a linha de uma pessoa lê além da própria pessoa (_pessoa.json.jbuilder): as etiquetas e a foto.
  O_QUE_A_LINHA_USA = { label_taggings: :tag, avatar_attachment: :blob }.freeze

  # Quem aparece na lista de contatos de hoje (ContactsController#resolved_contacts).
  def self.base(account)
    account.contacts.resolved_contacts(use_crm_v2: account.feature_enabled?('crm_v2'))
  end

  # A consulta inteira, para "Marcar todas as N": só o que as ações em grupo leem de cada pessoa.
  def todos
    ordenados.pluck(:id, :name, :phone_number, :blocked, :opted_out_at).map do |id, name, phone_number, blocked, opted_out_at|
      { id: id, name: name, phone_number: phone_number, blocked: blocked, opted_out_at: opted_out_at&.to_i }
    end
  end

  private

  def tabela
    'contacts'
  end

  def grupos
    GRUPOS
  end

  def consultados
    buscados(self.class.base(@account), textos: TEXTOS, numeros: NUMEROS)
      .where(da_empresa).where(com_a_etiqueta).where(da_cidade).where(que_chegou)
  end

  # Etiquetas e foto vêm juntas: sem isso, cada pessoa da página faria as suas consultas.
  def com_o_que_a_linha_usa(pessoas)
    pessoas.preload(O_QUE_A_LINHA_USA)
  end

  # Filtro vazio quer dizer "qualquer".
  def filtro(chave)
    @pedido.dig(:filtros, chave).presence
  end

  def empresa_id
    Integer(filtro(:empresa).to_s, 10, exception: false)
  end

  def da_empresa
    { company_id: empresa_id } if filtro(:empresa)
  end

  def com_a_etiqueta
    [COM_A_ETIQUETA, filtro(:etiqueta)] if filtro(:etiqueta)
  end

  def da_cidade
    ["contacts.additional_attributes->>'city' = ?", filtro(:cidade)] if filtro(:cidade)
  end

  def que_chegou
    ['contacts.created_at >= ?', @agora - CHEGOU_EM.fetch(filtro(:chegou_em))] if filtro(:chegou_em)
  end

  def conferir_pedido
    super
    recusar("chegou_em desconhecido: #{filtro(:chegou_em)}") unless filtro(:chegou_em).nil? || CHEGOU_EM.key?(filtro(:chegou_em))
    recusar("empresa inválida: #{filtro(:empresa)}") unless filtro(:empresa).nil? || empresa_id
  end
end
