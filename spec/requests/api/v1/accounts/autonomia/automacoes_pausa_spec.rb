require 'rails_helper'

# #2572 (F3.7): a automação que o motor pausou porque quem ligou perdeu o acesso aparece pausada, com o motivo, no
# editor e na lista. A desligada à mão, a que voltou a ser ligada e a pausa de antes do último ligar não aparecem.
RSpec.describe 'Api::V1::Accounts::Autonomia::Automacoes pausada', :automacao_motor, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:quem_ligou) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:passos) { [{ 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }] }
  let(:definicao) { automacao_ligada(account, quem_ligou, passos) }
  let(:frase) { I18n.t('autonomia.automacao.motivos.quem_ligou_saiu_da_conta') }

  before do
    account.enable_features!('automacao_editor')
    ligar_motor(account)
  end

  def pausar_pelo_motor
    definicao
    AccountUser.find_by(account: account, user: quem_ligou).destroy!
    comecar(definicao.reload, conversa)
    definicao.reload
  end

  def da_lista = response.parsed_body['automacoes'].find { |item| item['id'] == definicao.id }

  it 'mostra a pausa e o motivo no editor e na lista', :aggregate_failures do
    pausar_pelo_motor
    expect(definicao.ativa).to be(false)

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['pausa']).to eq('motivo' => 'quem_ligou_saiu_da_conta', 'frase' => frase)

    get base, headers: admin.create_new_auth_token, as: :json
    expect(da_lista['pausa']).to eq('motivo' => 'quem_ligou_saiu_da_conta', 'frase' => frase)
  end

  it 'não mostra pausa na desligada à mão' do
    definicao.desligar!

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['pausa']).to be_nil
  end

  it 'esquece a pausa de antes do último ligar', :aggregate_failures do
    pausar_pelo_motor
    travel 1.minute do
      post "#{base}/#{definicao.id}/ligar", params: { versao_id: definicao.versao_ativa_id }, headers: admin.create_new_auth_token,
                                            as: :json
      expect(response.parsed_body['ativa']).to be(true)
      expect(response.parsed_body['pausa']).to be_nil

      definicao.reload.desligar!
      get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['pausa']).to be_nil
    end
  end
end
