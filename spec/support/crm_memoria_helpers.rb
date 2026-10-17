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
end

RSpec.configure { |config| config.include CrmMemoriaHelpers }
