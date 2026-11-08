require 'rails_helper'

# #2461 — PATCH .../contacts/:id/labels/alterar: põe e tira etiquetas do contato uma a uma, como a #2202 fez na
# conversa. Quem grava por último não apaga mais a etiqueta que outra pessoa ou a automação pôs.
RSpec.describe 'Pôr e tirar etiquetas do contato uma a uma', type: :request do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:headers) { agente.create_new_auth_token }

  def rota(contact = contato, conta = account)
    "/api/v1/accounts/#{conta.id}/contacts/#{contact.id}/labels/alterar"
  end

  def alterar(params, auth: headers, contact: contato)
    patch rota(contact), params: params, headers: auth, as: :json
  end

  before { contato.update_labels(%w[vip retorno]) }

  it 'põe uma etiqueta e devolve a lista final no formato do create' do
    alterar({ por: ['boleto'] })

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload']).to match_array(%w[vip retorno boleto])
    expect(contato.reload.label_list).to match_array(%w[vip retorno boleto])
  end

  it 'tira uma sem mexer nas outras, e põe e tira na mesma chamada' do
    alterar({ tirar: ['vip'] })
    expect(contato.reload.label_list).to eq(['retorno'])

    alterar({ por: [' Boleto '], tirar: ['Retorno'] })
    expect(contato.reload.label_list).to eq(['boleto'])
  end

  it 'a segunda chamada não apaga a etiqueta que a primeira pôs' do
    alterar({ por: ['boleto'] })
    alterar({ por: ['urgente'] })

    expect(contato.reload.label_list).to match_array(%w[vip retorno boleto urgente])
  end

  it 'trava o contato enquanto lê e grava' do
    expect_any_instance_of(Contact).to receive(:with_lock).and_call_original # rubocop:disable RSpec/AnyInstance

    alterar({ por: ['boleto'] })

    expect(response).to have_http_status(:success)
  end

  describe 'recusa' do
    it 'sem login: 401' do
      patch rota, params: { por: ['boleto'] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'contato de outra conta pelo endereço da própria: 404 e nada muda' do
      de_outra = create(:contact, account: create(:account))
      de_outra.update_labels(['dela'])

      patch rota(de_outra), params: { por: ['boleto'] }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(de_outra.reload.label_list).to eq(['dela'])
    end

    it 'conta de que a pessoa não é membro: 401' do
      outra_conta = create(:account)

      patch rota(create(:contact, account: outra_conta), outra_conta), params: { por: ['boleto'] }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    [
      [{}, 'sem nada'],
      [{ por: 'boleto' }, 'texto em vez de lista'],
      [{ por: ['a,b'] }, 'vírgula no nome'],
      [{ por: Array.new(51) { |i| "e#{i}" } }, 'etiquetas demais'],
      [{ por: ['vip'], tirar: ['vip'] }, 'a mesma posta e tirada']
    ].each do |params, caso|
      it "parâmetro inválido (#{caso}): 422 e nada muda" do
        alterar(params)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(contato.reload.label_list).to match_array(%w[vip retorno])
      end
    end
  end
end
