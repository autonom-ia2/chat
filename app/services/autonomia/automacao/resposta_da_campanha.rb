# Lote 5 (#2681): a campanha a que a mensagem do cliente responde, para o filtro "respondeu à campanha" do gatilho
# `mensagem.criada` (Valores: `mensagem.campanha`). É o nome da última campanha que o contato recebeu nesta caixa antes
# desta mensagem: quem responde depois do "Pré-Black" responde ao "Pré-Black", até chegar outra campanha.
#
# O prazo da resposta (decisão da Automação sobre o 🟡 da qualidade, #2686): vale a mensagem do cliente depois do
# envio da campanha e antes da próxima campanha que ele recebeu NESTA caixa. A próxima fecha a janela da anterior; a
# de outra caixa não fecha. Não há prazo em dias.
#
# Vale pelo nome, não pelo número: a campanha que a própria automação dispara nasce a cada disparo, com o nome do passo,
# e não existe ainda quando a automação é montada. Recebida quer dizer aceita pela Meta (enviada, entregue ou lida) e
# que não falhou depois: a Meta aceita e avisa a falha mais tarde (mark_failed! guarda o sent_at), e o cliente não a viu.
# Só a mensagem do cliente responde. Sem destinatário de campanha (o OSS não guarda), lê vazio.
class Autonomia::Automacao::RespostaDaCampanha
  def self.titulo(mensagem)
    return unless mensagem.incoming? && defined?(::CampaignRecipient)

    contato = mensagem.conversation&.contact_id
    return if contato.nil?

    ::Campaign.joins(:campaign_recipients)
              .where(campaign_recipients: { contact_id: contato, inbox_id: mensagem.inbox_id, sent_at: ...mensagem.created_at })
              .where.not(campaign_recipients: { status: ::CampaignRecipient.statuses[:failed] })
              .order('campaign_recipients.sent_at DESC').pick(:title)
  end
end
