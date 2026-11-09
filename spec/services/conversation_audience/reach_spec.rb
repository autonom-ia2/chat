require 'rails_helper'

# #2277: quem da busca pode receber. chat#2733: o contato bloqueado fica de fora, com motivo próprio.
RSpec.describe ConversationAudience::Reach do
  let(:account) { create(:account) }

  it 'dá o motivo de quem não recebe: recusa, depois bloqueio, depois falta de contato' do
    livre = create(:contact, account: account, phone_number: '+5511987654321')
    recusou = create(:contact, account: account, phone_number: '+5521987654321', opted_out_at: 1.day.ago)
    bloqueado = create(:contact, account: account, phone_number: '+5531987654321', blocked: true)
    os_dois = create(:contact, account: account, phone_number: '+5541987654321', blocked: true, opted_out_at: 1.day.ago)
    bloqueado_sem_contato = create(:contact, account: account, blocked: true)
    sem_contato = create(:contact, account: account)

    expect(described_class.left_aside([livre, recusou, bloqueado, os_dois, bloqueado_sem_contato, sem_contato])).to eq(
      recusou.id => 'nao_quer', bloqueado.id => 'bloqueado', os_dois.id => 'nao_quer',
      bloqueado_sem_contato.id => 'bloqueado', sem_contato.id => 'sem_contato'
    )
  end
end
