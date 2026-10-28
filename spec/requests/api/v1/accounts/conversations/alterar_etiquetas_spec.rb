require 'rails_helper'

# #2202 (PR 3) — PATCH .../conversations/:id/labels/alterar: põe e tira etiquetas uma a uma, sem mandar a lista
# inteira. Quem grava por último não apaga mais a etiqueta que outra janela, aba ou pessoa pôs.
RSpec.describe 'Pôr e tirar etiquetas da conversa uma a uma', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:headers) { agente.create_new_auth_token }

  def rota(conversation = conversa, conta = account)
    "/api/v1/accounts/#{conta.id}/conversations/#{conversation.display_id}/labels/alterar"
  end

  def alterar(params, auth: headers, conversation: conversa)
    patch rota(conversation), params: params, headers: auth, as: :json
  end

  before do
    create(:inbox_member, inbox: inbox, user: agente)
    conversa.update_labels(%w[vip retorno])
  end

  describe 'quem opera a conversa' do
    it 'põe uma etiqueta e devolve a lista final no formato do create' do
      alterar({ por: ['boleto'] })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to match_array(%w[vip retorno boleto])
      expect(conversa.reload.label_list).to match_array(%w[vip retorno boleto])
    end

    it 'tira uma etiqueta sem mexer nas outras' do
      alterar({ tirar: ['vip'] })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq(['retorno'])
      expect(conversa.reload.label_list).to eq(['retorno'])
    end

    it 'põe e tira na mesma chamada' do
      alterar({ por: ['boleto'], tirar: ['retorno'] })

      expect(response).to have_http_status(:success)
      expect(conversa.reload.label_list).to match_array(%w[vip boleto])
    end

    it 'é idempotente: pôr a que já está e tirar a que não está não muda nada' do
      expect { alterar({ por: ['vip'], tirar: ['nao-tem'] }) }.not_to(change { conversa.reload.updated_at })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to match_array(%w[vip retorno])
    end

    it 'não duplica quando a etiqueta chega com maiúscula ou espaço' do
      alterar({ por: [' VIP '], tirar: ['Retorno'] })

      expect(conversa.reload.label_list).to eq(['vip'])
    end

    it 'grava pelo caminho de sempre: o evento de mudança de etiquetas sai' do
      expect { alterar({ por: ['boleto'] }) }.to have_enqueued_job(Conversations::ActivityMessageJob)
    end

    it 'trava a conversa enquanto lê e grava' do
      expect_any_instance_of(Conversation).to receive(:with_lock).and_call_original # rubocop:disable RSpec/AnyInstance

      alterar({ por: ['boleto'] })

      expect(response).to have_http_status(:success)
    end
  end

  describe 'duas janelas, abas ou pessoas que viram a mesma lista' do
    # Antes (#2290, achados 1, 2 e 7): cada uma mandava a lista inteira que tinha na tela, e a última apagava a
    # etiqueta da outra. Agora cada uma manda só a intenção dela, e as duas valem.
    it 'a segunda não apaga a etiqueta que a primeira pôs' do
      alterar({ por: ['boleto'] })
      alterar({ por: ['urgente'] })

      expect(conversa.reload.label_list).to match_array(%w[vip retorno boleto urgente])
    end

    it 'uma tira e a outra põe: as duas valem, em qualquer ordem' do
      alterar({ tirar: ['vip'] })
      expect(response.parsed_body['payload']).to eq(['retorno'])
      alterar({ por: ['boleto'] })

      expect(response.parsed_body['payload']).to match_array(%w[retorno boleto])
    end

    it 'mudança feita por fora no meio-tempo (outra pessoa, pela rota de sempre) não se perde' do
      conversa.update_labels(%w[vip retorno pago])
      alterar({ tirar: ['retorno'] })

      expect(conversa.reload.label_list).to match_array(%w[vip pago])
    end
  end

  describe 'recusa' do
    it 'sem login: 401' do
      patch rota, params: { por: ['boleto'] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'agente sem acesso à caixa: 401 e nada muda' do
      de_fora = create(:user, account: account, role: :agent)

      alterar({ por: ['boleto'] }, auth: de_fora.create_new_auth_token)

      expect(response).to have_http_status(:unauthorized)
      expect(conversa.reload.label_list).to match_array(%w[vip retorno])
    end

    it 'conversa de outra conta pelo endereço da própria: 404' do
      outra_conta = create(:account)
      outra_caixa = create(:inbox, account: outra_conta)
      # Número maior que qualquer conversa desta conta, para não cair numa daqui por coincidência.
      de_outra = create_list(:conversation, conversa.display_id + 1, account: outra_conta, inbox: outra_caixa).last
      de_outra.update_labels(['dela'])

      patch "/api/v1/accounts/#{account.id}/conversations/#{de_outra.display_id}/labels/alterar",
            params: { por: ['boleto'] }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(de_outra.reload.label_list).to eq(['dela'])
    end

    it 'conta que não é a dela: 401' do
      outra_conta = create(:account)
      de_outra = create(:conversation, account: outra_conta, inbox: create(:inbox, account: outra_conta))

      patch rota(de_outra, outra_conta), params: { por: ['boleto'] }, headers: headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    [
      [{}, 'sem nada'],
      [{ por: [], tirar: [] }, 'listas vazias'],
      [{ por: 'boleto' }, 'texto em vez de lista'],
      [{ por: [1] }, 'número em vez de nome'],
      [{ por: [''] }, 'nome vazio'],
      [{ por: ['a' * 256] }, 'nome comprido demais'],
      [{ por: ['a,b'] }, 'vírgula no nome'],
      [{ por: ['"x,y"'] }, 'aspas e vírgula no nome'],
      [{ tirar: ["d'agua"] }, 'apóstrofo no nome'],
      [{ por: Array.new(51) { |i| "e#{i}" } }, 'etiquetas demais'],
      [{ por: ['vip'], tirar: ['vip'] }, 'a mesma posta e tirada']
    ].each do |params, caso|
      it "parâmetro inválido (#{caso}): 422 e nada muda" do
        alterar(params)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(conversa.reload.label_list).to match_array(%w[vip retorno])
      end
    end
  end
end
