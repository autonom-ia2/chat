# Memória das IAs (#1601): liga a flag `memoria_ia` na conta (o único ponto de leitura é Crm::Memoria.ligada?).
module CrmMemoriaHelpers
  def ligar_memoria!(conta)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    conta.enable_features!(Crm::Memoria::FLAG)
    conta.reload
  end

  # Mensagem com created_at controlado, na conversa e conta dadas.
  def mensagem!(conversa, tipo = :incoming, **attrs)
    create(:message, { conversation: conversa, account: conversa.account, inbox: conversa.inbox, message_type: tipo }.merge(attrs))
  end

  # Limpeza dos specs de concorrência real (sem a transação do teste): tudo o que a conta criou, na ordem das FKs.
  # Sem isto, um WorkingHour órfão quebra o WorkingHour.today de outro spec.
  def limpar_conta!(conta)
    caixas = Inbox.where(account_id: conta.id).select(:id)
    limpar_registros!(conta, caixas)
    [WorkingHour, InboxMember].each { |modelo| modelo.where(inbox_id: caixas).delete_all }
    Inbox.where(account_id: conta.id).delete_all
    usuarios = AccountUser.where(account_id: conta.id).pluck(:user_id)
    AccountUser.where(account_id: conta.id).delete_all
    User.where(id: usuarios).delete_all
    Account.where(id: conta.id).delete_all
  end

  def limpar_registros!(conta, caixas)
    %w[Crm::MemoriaFato Crm::FollowUp Message Crm::Passagem Conversation Crm::Card Crm::Activity Contact]
      .filter_map(&:safe_constantize).each do |modelo|
        ContactInbox.where(inbox_id: caixas).delete_all if modelo == Contact
        conta.crm_pipelines.destroy_all if modelo == Contact
        modelo.where(account_id: conta.id).delete_all
      end
  end
end

RSpec.configure { |config| config.include CrmMemoriaHelpers }
