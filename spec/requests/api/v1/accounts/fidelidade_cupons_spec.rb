require 'rails_helper'

# #3100 — os cupons da conta: o relatório (mandados, usados e quanto venderam pela régua de 7 dias), criar, pausar e
# ligar de novo, conferir o código que o cliente mostrou e marcar como usado. No OSS, `fidelidade_view` e
# `fidelidade_manage` respondem administrator?; marcar como usado é de quem pode mexer no contato (D1), inclusive o
# atendente.
RSpec.describe 'Fidelidade: cupons', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:agora) { Time.zone.parse('2026-11-23 12:00:00') }
  let(:base) { "/api/v1/accounts/#{account.id}/fidelidade" }
  let!(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }

  before { travel_to(agora) }

  def pedir(verbo, caminho, quem: admin, params: {})
    public_send(verbo, "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token, as: :json)
  end

  def criar_cupom(**mudancas)
    Fidelidade::Cupom.create!({ account: account, nome: 'Volta de dezembro', oferta_tipo: 'porcentagem', oferta_valor: 10,
                                moeda: 'BRL', prefixo: 'VOLTA', validade_dias: 15 }.merge(mudancas))
  end

  def mandado(cupom, pessoa, codigo: 'VOLTA-7KD2', **mudancas)
    Fidelidade::CupomCodigo.create!({ account: account, cupom: cupom, contact: pessoa, codigo: codigo, enviado_em: agora - 1.day,
                                      vale_ate: agora + 14.days }.merge(mudancas))
  end

  describe 'criar' do
    let(:dados) { { nome: 'Volta', oferta: { tipo: 'valor', valor: 15 }, prefixo: 'VOLTA', validade_dias: 30 } }

    it 'cria ligado, com o valor em centavos, e devolve no formato do relatório' do
      pedir(:post, 'cupons', params: { cupom: dados })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('nome' => 'Volta', 'ligado' => true, 'mandados' => 0, 'usados' => 0, 'vendas' => [],
                                              'oferta' => include('tipo' => 'valor', 'valor' => 15.0))
      expect(Fidelidade::Cupom.last).to have_attributes(oferta_valor: 1_500, moeda: 'BRL', limite_por_cliente: 1, created_by: admin)
    end

    it 'algo errado responde 422 com o campo, sem gravar' do
      pedir(:post, 'cupons', params: { cupom: dados.merge(prefixo: 'VOL TA', validade_dias: 10) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].keys).to include('prefixo', 'validade_dias')
      expect(Fidelidade::Cupom.count).to eq(0)
    end

    it 'o atendente sem a permissão não cria nem lê o relatório', :aggregate_failures do
      pedir(:post, 'cupons', quem: agente, params: { cupom: dados })
      expect(response).to have_http_status(:unauthorized)

      pedir(:get, 'cupons', quem: agente)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'relatório' do
    let(:sale) { create_crm_pipeline(account: account, user: admin) }

    around do |example|
      with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
    end

    def compra(pessoa, quando:, valor:)
      pipeline, stage = sale
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: pessoa.name, contact: pessoa, status: :won,
                                       value_cents: valor)
      card.update_columns(closed_at: quando) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'conta mandados e usados e soma as vendas de quem usou até 7 dias depois do uso' do
      cupom = criar_cupom
      bia = create(:contact, account: account, name: 'Bia')
      mandado(cupom, ana, usado_em: agora - 10.days)
      mandado(cupom, bia, codigo: 'VOLTA-AB3C')
      Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: create(:contact, account: account), codigo: 'VOLTA-NS9X')
      compra(ana, quando: agora - 8.days, valor: 12_000)
      compra(ana, quando: agora - 1.day, valor: 99_000)
      compra(bia, quando: agora - 1.day, valor: 50_000)

      pedir(:get, 'cupons')

      linha = response.parsed_body.first
      expect(linha).to include('id' => cupom.id, 'mandados' => 2, 'usados' => 1, 'vendas' => [{ 'moeda' => 'BRL', 'total' => 120.0 }])
    end

    it 'sem ver valor de venda, as vendas vêm null' do
      criar_cupom
      allow(Crm::ValorDeVenda).to receive(:ve?).and_return(false)

      pedir(:get, 'cupons')

      expect(response.parsed_body.first).to include('vendas' => nil, 'mandados' => 0)
    end
  end

  it 'pausar e ligar de novo' do
    cupom = criar_cupom

    pedir(:patch, "cupons/#{cupom.id}", params: { ligado: false })
    expect(response.parsed_body).to include('ligado' => false)
    expect(cupom.reload.ligado).to be(false)

    pedir(:patch, "cupons/#{cupom.id}", params: { ligado: true })
    expect(cupom.reload.ligado).to be(true)
  end

  it 'não mexe em cupom de outra conta' do
    outra = create(:account)
    cupom = Fidelidade::Cupom.create!(account: outra, nome: 'De fora', oferta_tipo: 'presente', oferta_texto: 'Brinde',
                                      prefixo: 'FORA', validade_dias: 7)

    pedir(:patch, "cupons/#{cupom.id}", params: { ligado: false })

    expect(response).to have_http_status(:not_found)
    expect(cupom.reload.ligado).to be(true)
  end

  describe 'conferir' do
    let!(:cupom) { criar_cupom }

    it 'código que vale, digitado em minúsculas e com espaços, diz o que dá, de quem é e até quando' do
      codigo = mandado(cupom, ana)

      pedir(:post, 'cupons/conferir', params: { codigo: ' volta- 7kd2 ' })

      expect(response.parsed_body).to include('id' => codigo.id, 'estado' => 'valido', 'cliente' => 'Ana Albuquerino',
                                              'vale_ate' => (agora + 14.days).to_i, 'oferta' => include('tipo' => 'porcentagem'))
    end

    it 'diz se já foi usado, se venceu e se não existe', :aggregate_failures do
      mandado(cupom, ana, usado_em: agora - 1.hour)
      mandado(cupom, create(:contact, account: account), codigo: 'VOLTA-VNC2', vale_ate: agora - 1.day)
      Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: create(:contact, account: account), codigo: 'VOLTA-NS9X')

      estado = lambda do |codigo|
        pedir(:post, 'cupons/conferir', params: { codigo: codigo })
        response.parsed_body['estado']
      end

      expect(estado.call('VOLTA-7KD2')).to eq('usado')
      expect(estado.call('VOLTA-VNC2')).to eq('vencido')
      # O código sorteado num envio que não saiu nunca chegou ao cliente.
      expect(estado.call('VOLTA-NS9X')).to eq('nao_existe')
      expect(estado.call('INVENTADO')).to eq('nao_existe')
    end

    it 'não acha o código de outra conta' do
      outra = create(:account)
      de_fora = Fidelidade::Cupom.create!(account: outra, nome: 'De fora', oferta_tipo: 'porcentagem', oferta_valor: 5,
                                          prefixo: 'VOLTA', validade_dias: 7)
      Fidelidade::CupomCodigo.create!(account: outra, cupom: de_fora, contact: create(:contact, account: outra),
                                      codigo: 'VOLTA-7KD2', enviado_em: agora)

      pedir(:post, 'cupons/conferir', params: { codigo: 'VOLTA-7KD2' })

      expect(response.parsed_body).to include('estado' => 'nao_existe')
    end

    it 'o atendente sem a permissão não confere pela aba' do
      mandado(cupom, ana)

      pedir(:post, 'cupons/conferir', quem: agente, params: { codigo: 'VOLTA-7KD2' })

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'marcar como usado' do
    let!(:cupom) { criar_cupom }

    it 'o atendente marca, com quando e quem; repetir não gasta de novo' do
      codigo = mandado(cupom, ana)

      pedir(:post, "cupom_codigos/#{codigo.id}/usar", quem: agente)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('ja_estava' => false, 'codigo' => include('estado' => 'usado'))
      expect(codigo.reload).to have_attributes(usado_em: agora, usado_por: agente, usos: 1)

      pedir(:post, "cupom_codigos/#{codigo.id}/usar", quem: admin)
      expect(response.parsed_body).to include('ja_estava' => true)
      expect(codigo.reload).to have_attributes(usado_por: agente, usos: 1)
    end

    it 'código vencido responde 422 e não marca' do
      codigo = mandado(cupom, ana, vale_ate: agora - 1.minute)

      pedir(:post, "cupom_codigos/#{codigo.id}/usar")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'vencido')
      expect(codigo.reload.usado_em).to be_nil
    end

    it 'código que não chegou ao cliente não existe' do
      codigo = Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: ana, codigo: 'VOLTA-NS9X')

      pedir(:post, "cupom_codigos/#{codigo.id}/usar")

      expect(response).to have_http_status(:not_found)
    end

    it 'a ficha mostra o cupom da pessoa com o id para marcar' do
      codigo = mandado(cupom, ana)
      Fidelidade::Programa.create!(account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                   premio: 'Uma lavagem grátis', ligado: true, ligado_em: agora - 1.day)

      get "/api/v1/accounts/#{account.id}/relacionamentos/pessoas/#{ana.id}/fidelidade", headers: agente.create_new_auth_token, as: :json

      expect(response.parsed_body['cupons']).to contain_exactly(include('id' => codigo.id, 'codigo' => 'VOLTA-7KD2', 'estado' => 'valido'))
    end
  end
end
