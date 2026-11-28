require 'rails_helper'

# #3270 — a liberação do agente contratado no super admin: um cartão por modelo do catálogo, sem <select>. Só o super
# admin grava, e só chave do catálogo entra.
RSpec.describe 'Super Admin agentes contratados liberados', type: :request do
  let(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved', Autonomia::Agents::Nicho::NICHO_KEY => 'geral' }) }
  let(:path) { "/super_admin/accounts/#{account.id}" }
  let(:chave) { 'seguro_viagem_universal' }
  let(:liberacao) { Autonomia::Agents::Contratados::Liberacao }

  def caixas(document)
    document.css(%(input[type="checkbox"][name="account[contratados_liberados][]"]))
  end

  context 'with the super admin signed in' do
    before { sign_in(create(:super_admin), scope: :super_admin) }

    it 'mostra um cartão por modelo do catálogo, desmarcado, sem select, com o campo que desliga todos' do
      get "#{path}/edit"

      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      campo = document.at_css('[data-contratados-liberados-form]')
      expect(caixas(document).pluck('value')).to eq(Autonomia::Agents::Contratados::MODELOS.keys)
      expect(caixas(document).none? { |caixa| caixa['checked'] }).to be(true)
      expect(campo.css('select')).to be_empty
      expect(campo.at_css(%(input[type="hidden"][name="account[contratados_liberados][]"]))['value']).to eq('')
      expect(campo.text.squish).to include('Universal Travel Insurance')
    end

    it 'a conta liberada vem marcada' do
      liberacao.atribuir(account, [chave])
      account.save!

      get "#{path}/edit"

      expect(caixas(Nokogiri::HTML(response.body)).find { |caixa| caixa['value'] == chave }['checked']).to be_present
    end

    it 'grava a liberação, só do catálogo, sem mexer no nicho nem nas outras chaves' do
      patch path, params: { account: { name: account.name, contratados_liberados: ['', chave, 'outro_modelo'] } }

      expect(response).to have_http_status(:redirect)
      expect(account.reload.internal_attributes).to include(
        'unrelated' => 'preserved', Autonomia::Agents::Nicho::NICHO_KEY => 'geral', liberacao::CHAVE => [chave]
      )
      expect(liberacao.liberado?(account, chave)).to be(true)
    end

    it 'desmarcar o último desliga (o campo escondido manda a lista vazia)' do
      liberacao.atribuir(account, [chave])
      account.save!

      patch path, params: { account: { name: account.name, contratados_liberados: [''] } }

      expect(response).to have_http_status(:redirect)
      expect(liberacao.liberado?(account.reload, chave)).to be(false)
    end

    it 'a página da conta mostra quem está liberado' do
      get path
      expect(Nokogiri::HTML(response.body).at_css('[data-contratados-liberados]').text.squish).to eq('None')

      liberacao.atribuir(account, [chave])
      account.save!
      get path
      expect(Nokogiri::HTML(response.body).at_css('[data-contratados-liberados]').text.squish).to eq('Universal Travel Insurance')
    end
  end

  it 'sem o super admin, não grava' do
    patch path, params: { account: { contratados_liberados: [chave] } }

    expect(liberacao.liberado?(account.reload, chave)).to be(false)
  end
end
