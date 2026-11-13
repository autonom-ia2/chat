require 'rails_helper'

# E4 (#2897), parte 7 — quem vê os seguros pelo painel da conversa. Seguro é dado da base, do nível das notas do contato:
# a função personalizada sem a chave de contatos não vê os seguros nem do contato de uma conversa que ela atende (401),
# embora continue com o que vem com a conversa (a origem do contato, #1849). O agente sem função, o administrador e a
# função com contact_view veem. O painel lê de `pessoas/:id/seguros`; a gaveta, de `seguros/:id`. Tudo fictício.
RSpec.describe 'Carteira de seguros: quem vê pelo painel da conversa', type: :request do
  let(:account) { conta_com_carteira }
  let(:caixa) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:seguro) { guardar_pdf_na(criar_apolice(marina, numero: 'EX-001234', bem: 'Carro Exemplo 2022')) }
  let(:leituras_da_gaveta) { ["seguros/#{seguro.id}", "seguros/#{seguro.id}/historia", "seguros/#{seguro.id}/pdf"] }

  before { seguro }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    create(:inbox_member, user: user, inbox: caixa)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def conversa_com_a_marina(quem_atende)
    contact_inbox = create(:contact_inbox, contact: marina, inbox: caixa)
    create(:conversation, account: account, inbox: caixa, contact: marina, contact_inbox: contact_inbox, assignee: quem_atende)
  end

  def ler(caminho, quem)
    get "#{base}/#{caminho}", headers: quem.create_new_auth_token
  end

  def seguros_no_painel(quem)
    ler("relacionamentos/pessoas/#{marina.id}/seguros", quem)
  end

  describe 'a função sem a chave de contatos, atendendo a conversa da pessoa' do
    let(:atendente) { pessoa_com(%w[conversation_participating_manage]) }

    before { conversa_com_a_marina(atendente) }

    it 'não vê os seguros dela: 401, sem nada do seguro na resposta' do
      seguros_no_painel(atendente)

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include('EX-001234')
      expect(response.body).not_to include('Carro Exemplo')
    end

    it 'não abre o seguro, a história nem o PDF, e nenhum link de PDF é emitido' do
      leituras_da_gaveta.each do |caminho|
        ler("relacionamentos/#{caminho}", atendente)

        expect(response).to have_http_status(:unauthorized), caminho
        expect(response.body).not_to include('"url"'), caminho
      end
    end

    it 'continua com o que vem com a conversa: a origem do contato' do
      get "#{base}/campaign_journey/contact_origins/#{marina.id}", headers: atendente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  it 'a função que só lê a caixa também não vê os seguros do contato da conversa' do
    leitora = pessoa_com(%w[conversation_view])
    conversa_com_a_marina(nil)

    seguros_no_painel(leitora)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'o agente sem função, o administrador e a função com contact_view veem os seguros do contato da conversa' do
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: caixa)
    conversa_com_a_marina(agente)
    quem_ve = [agente, create(:user, account: account, role: :administrator), pessoa_com(%w[conversation_participating_manage contact_view])]

    quem_ve.each do |quem|
      seguros_no_painel(quem)

      expect(response).to have_http_status(:ok), quem.id.to_s
      expect(response.parsed_body.pluck('numero')).to eq(%w[EX-001234]), quem.id.to_s
    end
  end

  it 'quem só vê contatos abre o seguro e o PDF pela gaveta do painel, sem poder mudar nada' do
    so_ve = pessoa_com(%w[conversation_participating_manage contact_view])
    conversa_com_a_marina(so_ve)

    leituras_da_gaveta.each do |caminho|
      ler("relacionamentos/#{caminho}", so_ve)

      expect(response).to have_http_status(:ok), caminho
    end
    post "#{base}/relacionamentos/seguros/#{seguro.id}/cancelar", headers: so_ve.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(seguro.reload.cancelado_em).to be_nil
  end
end
