require 'rails_helper'

# #2556: o editor da automação mostra quantos contatos ou cards o gatilho de data deixou de fora pela data escrita em
# outro formato, com o nome do campo que a pessoa vê, sem o valor do cliente. Sem a contagem, o aviso não vem.
RSpec.describe 'Api::V1::Accounts::Autonomia::Automacoes datas inválidas', :automacao_motor, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:passos) { [{ 'id' => 'p1', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }] }
  let(:gatilho) { { 'tipo' => 'contato.data', 'campo' => 'aniversario', 'dias' => 0, 'quando' => 'depois', 'hora' => 9 } }
  let(:definicao) { automacao_ligada(account, admin, passos, gatilho: gatilho) }
  let(:avisos) { Autonomia::Automacao::Tempo::DatasInvalidas }

  before do
    account.enable_features!('automacao_editor', 'automacao_gatilhos')
    ligar_motor(account)
    create(:custom_attribute_definition, account: account, attribute_key: 'aniversario', attribute_display_name: 'Aniversário',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'date')
  end

  it 'o editor mostra quantos ficaram de fora e o nome do campo' do
    avisos.gravar(definicao, quantos: 12, tipo: 'contato.data', campo: 'aniversario', dia: Time.current.to_date)

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['datas_invalidas']).to eq('quantos' => 12, 'alvo' => 'contato', 'campo' => 'Aniversário')
  end

  it 'sem nenhum inválido, o aviso não vem' do
    avisos.gravar(definicao, quantos: 12, tipo: 'contato.data', campo: 'aniversario', dia: Time.current.to_date)
    avisos.gravar(definicao, quantos: 0, tipo: 'contato.data', campo: 'aniversario', dia: Time.current.to_date)

    get "#{base}/#{definicao.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).not_to have_key('datas_invalidas')
  end

  it 'salvar a automação devolve o aviso junto, para a tela não perdê-lo' do
    avisos.gravar(definicao, quantos: 3, tipo: 'contato.data', campo: 'aniversario', dia: Time.current.to_date)

    patch "#{base}/#{definicao.id}", params: { nome: 'Parabéns' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['datas_invalidas']).to eq('quantos' => 3, 'alvo' => 'contato', 'campo' => 'Aniversário')
  end
end
