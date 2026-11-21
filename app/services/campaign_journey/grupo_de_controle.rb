# #3098: o grupo de controle da campanha com público. Uma parte do público (`grupo_de_controle_pct` do link) é sorteada
# para NÃO receber; a tela de resultado compara quem recebeu com quem ficou sem receber.
#
# O sorteio é fixo: ordena as pessoas pelo hash de "link:contato" e separa as primeiras N (N = público × pct, para
# baixo). Assim a revisão promete "45 de 450 pessoas" e são 45 mesmo, e sortear de novo daria as mesmas pessoas.
# Sorteia uma vez só, quando a campanha é confirmada (CampaignJourney::Medicao); depois o grupo é o que está em
# campaign_control_contacts. Quem entrar no público depois do sorteio recebe.
#
# Quem está no grupo não vira destinatário (AudienceContacts.contacts_for e EmailAudienceRecipients#sync! o tiram):
# não entra em "Puladas" nem em nenhuma outra conta do envio, e a soma do resultado continua fechando com o Público.
class CampaignJourney::GrupoDeControle
  def initialize(link)
    @link = link
  end

  def ativo?
    @link.present? && @link.grupo_de_controle_pct.positive?
  end

  # `contact_ids`: o público inteiro de quem ia receber. Não faz nada se não há grupo ou se já foi sorteado.
  def sortear!(contact_ids)
    return unless ativo?
    return if @link.campaign_control_contacts.exists?

    unicos = contact_ids.compact.uniq
    quantos = unicos.size * @link.grupo_de_controle_pct / 100
    gravar(unicos.sort_by { |id| posicao(id) }.first(quantos))
  end

  # `contatos`: relação de Contact. Devolve a mesma relação sem o grupo.
  def sem_o_grupo(contatos)
    return contatos unless ativo?

    contatos.where.not(id: @link.campaign_control_contacts.select(:contact_id))
  end

  def ids
    return Set.new unless ativo?

    @link.campaign_control_contacts.pluck(:contact_id).to_set
  end

  private

  def posicao(contact_id)
    Digest::SHA256.hexdigest("#{@link.id}:#{contact_id}")
  end

  def gravar(contact_ids)
    return if contact_ids.empty?

    agora = Time.current
    linhas = contact_ids.map do |id|
      { account_id: @link.account_id, campaign_audience_link_id: @link.id, contact_id: id, created_at: agora }
    end
    CampaignControlContact.insert_all(linhas, unique_by: :idx_campaign_control_contacts_link_contact) # rubocop:disable Rails/SkipsModelValidations
  end
end
