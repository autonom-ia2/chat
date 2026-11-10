# Lote 5 (#2681): a campanha a que a mensagem do cliente responde, para o filtro "respondeu à campanha" do gatilho
# `mensagem.criada` (Valores: `mensagem.campanha`). É o nome da última campanha que o contato recebeu nesta caixa antes
# desta mensagem: quem responde depois do "Pré-Black" responde ao "Pré-Black", até chegar outra campanha.
#
# O prazo da resposta (decisão da Automação sobre o 🟡 da qualidade, #2686): vale a mensagem do cliente depois do
# envio da campanha e antes da próxima campanha que ele recebeu NESTA caixa. A próxima fecha a janela da anterior; a
# de outra caixa não fecha. Não há prazo em dias.
#
# Vale pelo nome, não pelo número: a campanha que a própria automação dispara nasce a cada disparo, com o nome do passo,
# e não existe ainda quando a automação é montada. Recebida quer dizer aceita pela Meta (enviada, entregue ou lida).
# Só a mensagem do cliente responde. Sem destinatário de campanha (o OSS não guarda), lê vazio.
#
# A consulta fica na conta e passa pelos índices que já existem: as campanhas da caixa (campaigns.inbox_id) e, nelas, o
# destinatário do contato (campaign_recipients (campaign_id, contact_id)). Roda em toda mensagem que chega com o filtro.
class Autonomia::Automacao::RespostaDaCampanha
  def self.titulo(mensagem)
    return unless mensagem.incoming? && defined?(::CampaignRecipient)

    contato = mensagem.conversation&.contact_id
    return if contato.nil?

    campanhas = ::Campaign.where(account_id: mensagem.account_id, inbox_id: mensagem.inbox_id).select(:id)
    ::CampaignRecipient.joins(:campaign)
                       .where(account_id: mensagem.account_id, campaign_id: campanhas, contact_id: contato, sent_at: ...mensagem.created_at)
                       .order('campaign_recipients.sent_at DESC').pick('campaigns.title')
  end
end
