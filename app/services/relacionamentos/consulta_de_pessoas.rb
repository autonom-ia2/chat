# A aba Pessoas da Lista nova de Relacionamentos (#2894): a mesma base da lista de contatos de hoje, com a busca (nome,
# e-mail, empresa, telefone e CPF), os filtros da gaveta (empresa, etiqueta, cidade e quando chegou) e os grupos.
# "Falou" é o last_activity_at como ele é: só mensagem que a pessoa mandou. Vale para a conta inteira.
#
# Na conta que tem a carteira de seguros, a lista ganha o grupo "Só tem um seguro" e a busca pelo número da apólice e
# pelo bem segurado (Carteira::NaListaDePessoas). Nas outras, nada muda: nem grupo, nem condição, nem consulta a mais.
#
# #3062 — paridade com a lista de contatos de hoje: o grupo "No site agora" (quem está com o chat do site aberto, a
# mesma leitura de ContactsController#active, que lê a conta inteira e por isso mostra o visitante anônimo), as sete
# ordens dela, cada uma nos dois sentidos, e a consulta inteira
# para "Baixar planilha" (Account::ContactsExportJob).
class Relacionamentos::ConsultaDePessoas < Relacionamentos::Consulta
  GRUPOS = {
    'todos' => 'TRUE',
    'clientes' => "contacts.contact_type = #{Contact.contact_types[:customer]}",
    'falou_ha_pouco' => 'contacts.last_activity_at >= :falou_ha_pouco',
    'sumiu_1_a_3_meses' => 'contacts.last_activity_at < :falou_ha_pouco AND contacts.last_activity_at >= :sumiu',
    'sumiu_mais_de_3_meses' => 'contacts.last_activity_at < :sumiu',
    'nunca_conversou' => 'contacts.last_activity_at IS NULL',
    'nao_quer_mensagens' => 'contacts.opted_out_at IS NOT NULL',
    'ativos_agora' => 'contacts.id IN (:ativos_agora)'
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

  # Um texto da pessoa (e-mail, empresa, cidade, país) como o nome ordena (Consulta.por_nome), no sentido pedido ('ASC' ou
  # 'DESC'). Texto vazio conta como ausente e vai para o fim nos dois sentidos. Tudo aqui é SQL escrito no código.
  def self.por_texto(expressao, direcao)
    "#{SearchService::SemAcento.sql("NULLIF(#{expressao}, '')")} COLLATE \"C\" #{direcao} NULLS LAST, contacts.id"
  end

  # As ordens da lista de contatos de hoje que a aba Pessoas soma às de Consulta (última conversa, nome e mais novos).
  # Texto vazio ou ausente vai para o fim nos dois sentidos, como na lista de hoje; o empate sai pela ordem de chegada.
  ORDENS_A_MAIS = {
    'conversa_mais_antiga' => 'contacts.last_activity_at ASC NULLS LAST, contacts.id',
    'nome_z_a' => "#{SearchService::SemAcento.sql('contacts.name')} COLLATE \"C\" DESC, contacts.id",
    'email_a_z' => por_texto('contacts.email', 'ASC'),
    'email_z_a' => por_texto('contacts.email', 'DESC'),
    'empresa_a_z' => por_texto("contacts.additional_attributes->>'company_name'", 'ASC'),
    'empresa_z_a' => por_texto("contacts.additional_attributes->>'company_name'", 'DESC'),
    'pais_a_z' => por_texto("contacts.additional_attributes->>'country'", 'ASC'),
    'pais_z_a' => por_texto("contacts.additional_attributes->>'country'", 'DESC'),
    'cidade_a_z' => por_texto("contacts.additional_attributes->>'city'", 'ASC'),
    'cidade_z_a' => por_texto("contacts.additional_attributes->>'city'", 'DESC'),
    'mais_antigos' => 'contacts.created_at ASC, contacts.id'
  }.freeze

  # O grupo "No site agora" conta sobre a conta inteira, como a lista dele; os outros, sobre a base de hoje.
  # Sem ninguém no site agora, não há o que contar: a contagem continua sendo uma consulta só.
  def contagens
    da_base = grupos.except('ativos_agora').transform_values { |condicao| com_os_cortes(condicao) }
    Relacionamentos::ContagemPorGrupo.call(consultados(self.class.base(@account)), da_base)
                                     .merge('ativos_agora' => contar_no_site_agora)
  end

  # A consulta inteira, para "Marcar todas as N": só o que as ações em grupo leem de cada pessoa. As etiquetas vão junto
  # para "Tirar etiquetas" mostrar quantas das marcadas têm cada uma.
  def todos
    etiquetas = etiquetas_de(do_grupo)
    ordenados.pluck(:id, :name, :phone_number, :blocked, :opted_out_at).map do |id, name, phone_number, blocked, opted_out_at|
      { id: id, name: name, phone_number: phone_number, blocked: blocked, opted_out_at: opted_out_at&.to_i,
        labels: etiquetas.fetch(id, []) }
    end
  end

  # A consulta inteira, na ordem da tela e sem página, para "Baixar planilha" (Account::ContactsExportJob).
  def para_exportar
    ordenados
  end

  private

  def tabela
    'contacts'
  end

  def ordens
    @ordens ||= super.merge(ORDENS_A_MAIS)
  end

  def grupos
    @grupos ||= GRUPOS.merge(carteira.grupos)
  end

  def cortes
    @cortes ||= super.merge(carteira.cortes).merge(ativos_agora: ativos_agora)
  end

  # Quem está com o chat do site aberto agora (a presença que o widget renova). Lista vazia vira `IN (NULL)`: ninguém.
  def ativos_agora
    ::OnlineStatusTracker.get_available_contact_ids(@account.id).map(&:to_i)
  end

  # "No site agora" lê a conta inteira (ContactsController#active): o visitante do chat do site, ainda sem e-mail nem
  # telefone, aparece nele. Os outros grupos leem a base da lista de contatos de hoje.
  def contar_no_site_agora
    return 0 if cortes[:ativos_agora].empty?

    consultados(@account.contacts).where(com_os_cortes(GRUPOS['ativos_agora'])).count
  end

  # As etiquetas de cada pessoa do escopo, numa consulta só, como a linha lê (etiqueta com dono não é da pessoa).
  def etiquetas_de(escopo)
    ActsAsTaggableOn::Tagging.joins(:tag)
                             .where(taggable_type: 'Contact', context: 'labels', tagger_id: nil, taggable_id: escopo.select('contacts.id'))
                             .pluck(:taggable_id, 'tags.name')
                             .group_by(&:first).transform_values { |pares| pares.map(&:last) }
  end

  def consultados(base = grupo == 'ativos_agora' ? @account.contacts : self.class.base(@account))
    carteira.buscados(buscados(base, textos: TEXTOS, numeros: NUMEROS), base, @pedido[:busca])
            .where(da_empresa).where(com_a_etiqueta).where(da_cidade).where(que_chegou)
  end

  def carteira
    @carteira ||= Carteira::NaListaDePessoas.new(@account)
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
