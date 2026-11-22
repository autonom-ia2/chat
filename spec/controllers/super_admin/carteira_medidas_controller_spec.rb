require 'rails_helper'

# E9 (#2902): a página do uso da carteira de seguros no Super Admin. Só o super admin entra; a tabela tem uma linha
# por conta que usa a carteira e o total; o período troca por link. A tabela é lida pelas marcas `data-conta` e
# `data-medida`, sem procurar texto solto.
RSpec.describe 'Super Admin Carteira Medidas', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { conta_com_carteira(name: 'Corretora Exemplo') }
  let(:pessoa) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:caminho) { '/super_admin/carteira_medida' }
  let(:agora) { Time.zone.parse('2026-11-18 12:00:00') }

  around { |example| travel_to(agora) { example.run } }

  # Upgrade 4.19.1 (#3119): the redesign sidebar also marks its own link with aria-current, so the period is read in its nav.
  def pagina
    Nokogiri::HTML(response.body)
  end

  def numero(conta, medida)
    pagina.at_css("[data-conta='#{conta}'] [data-medida='#{medida}']")&.text&.strip
  end

  it 'exige super admin' do
    get caminho

    expect(response).to have_http_status(:redirect)
  end

  it 'não abre para quem só é administrador de uma conta' do
    sign_in(create(:user, account: account, role: :administrator), scope: :user)

    get caminho

    expect(response).to have_http_status(:redirect)
  end

  context 'with o super admin autenticado' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'mostra a conta com as contagens e o total, sem dado da pessoa nem da apólice', :aggregate_failures do
      criar_apolice(pessoa, origem: 'planilha', numero: 'EX-445566')
      criar_apolice(pessoa, origem: 'pdf').eventos.create!(tipo: 'proposta_pedida', quando: agora, valores: {})

      get caminho

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Corretora Exemplo')
      expect([numero(account.id, 'origem.planilha'), numero(account.id, 'origem.pdf'), numero(account.id, 'cotacao.proposta_pedida')])
        .to eq(%w[1 1 1])
      expect(numero('total', 'origem.planilha')).to eq('1')
      expect(response.body).not_to include('Ana Albuquerino', 'EX-445566')
    end

    it 'troca o período por link, sem lista de escolha', :aggregate_failures do
      criar_apolice(pessoa).eventos.create!(tipo: 'proposta_pedida', quando: Time.zone.parse('2026-10-10 10:00'), valores: {})

      get caminho, params: { periodo: 'mes_passado' }

      expect(numero(account.id, 'cotacao.proposta_pedida')).to eq('1')
      expect(pagina.at_css('nav[aria-label="Período"] a[aria-current="page"]').text.strip).to eq('Mês passado')
      expect(pagina.css('select')).to be_empty
    end

    it 'com um período que não existe, mostra o mês corrente' do
      criar_apolice(pessoa).eventos.create!(tipo: 'proposta_pedida', quando: Time.zone.parse('2026-10-10 10:00'), valores: {})

      get caminho, params: { periodo: 'ano_todo' }

      expect([numero(account.id, 'cotacao.proposta_pedida'), pagina.at_css('nav[aria-label="Período"] a[aria-current="page"]').text.strip])
        .to eq(['0', 'Este mês'])
    end

    it 'sem conta usando a carteira, diz isso' do
      get caminho

      expect(response.body).to include('Nenhuma conta usa a carteira de seguros.')
    end
  end
end
