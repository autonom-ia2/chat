require 'rails_helper'

# Ordenar por um campo que empata, sem desempate, deixa a página 2 repetir ou pular registros da página 1
# (CI do #961: a tarefa longa do Guia pegou os contatos 26–50 em vez de 1–25). O desempate é o id.
RSpec.describe 'Ordem estável na paginação', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:mesmo_instante) { 2.days.ago.change(usec: 0) }

  it 'contatos empatados na última atividade saem por id, página após página' do
    contatos = Array.new(20) do |indice|
      create(:contact, account: account, email: "c#{indice}@exemplo.com", last_activity_at: mesmo_instante)
    end
    ids = (1..2).flat_map do |pagina|
      get "/api/v1/accounts/#{account.id}/contacts", params: { sort: '-last_activity_at', page: pagina },
                                                     headers: admin.create_new_auth_token, as: :json
      response.parsed_body['payload'].pluck('id')
    end

    expect(ids).to eq(contatos.map(&:id).sort.first(ids.size))
  end

  it 'conversas empatadas na última atividade desempatam por id na mesma direção' do
    inbox = create(:inbox, account: account)
    conversas = Array.new(3) { create(:conversation, account: account, inbox: inbox) }
    Conversation.where(id: conversas.map(&:id)).update_all(last_activity_at: mesmo_instante) # rubocop:disable Rails/SkipsModelValidations

    ordenadas = Conversations::SortService.apply(Conversation.where(id: conversas.map(&:id)), 'last_activity_at_desc')

    expect(ordenadas.map(&:id)).to eq(conversas.map(&:id).sort.reverse)
  end
end
