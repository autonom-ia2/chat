# Lote 5 (#2681): a campanha a que a mensagem do cliente responde, para o filtro "respondeu à campanha" do gatilho
# `mensagem.criada` (Valores: `mensagem.campanha`). É o nome da última campanha que o contato recebeu nesta caixa antes
# desta mensagem: quem responde depois do "Pré-Black" responde ao "Pré-Black", até chegar outra campanha.
#
# Vale pelo nome, não pelo número: a campanha que a própria automação dispara nasce a cada disparo, com o nome do passo,
# e não existe ainda quando a automação é montada. Recebida quer dizer aceita pela Meta (enviada, entregue ou lida).
# Só a mensagem do cliente responde. Sem destinatário de campanha (o OSS não guarda), lê vazio.
class Autonomia::Automacao::RespostaDaCampanha
  def self.titulo(mensagem)
    return unless mensagem.incoming? && defined?(::CampaignRecipient)

    contato = mensagem.conversation&.contact_id
    return if contato.nil?

    ::Campaign.joins(:campaign_recipients)
              .where(campaign_recipients: { contact_id: contato, inbox_id: mensagem.inbox_id, sent_at: ...mensagem.created_at })
              .order('campaign_recipients.sent_at DESC').pick(:title)
  end
end
