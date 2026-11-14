require 'rails_helper'

# E4 (#2897) — o "Desfazer" de uma lista que trouxe seguros, pelas rotas de sempre (a prévia e o clique, com o job). Sai só
# o seguro que a lista criou e em que ninguém mexeu; o que ela só completou num seguro que já existia volta ao que era; o
# resto fica. A prévia promete o que o job faz. As regras de "ninguém mexeu", uma a uma, estão em
# spec/services/carteira/trazer/seguros_da_lista_spec.rb. Todos os dados são inventados.
RSpec.describe 'Trazer minha lista: desfazer a lista que trouxe seguros (Relacionamentos)', :aggregate_failures, type: :request do
  include_context 'with planilha de seguros'

  let(:job) { Relacionamentos::Trazer::DesfazerJob }
  let(:telefone_da_ana) { '+5511987650001' }
  let(:telefone_do_bruno) { '+5511987650002' }

  def pedir_previa(importacao, quem: admin, conta: account)
    get "/api/v1/accounts/#{conta.id}/relacionamentos/trazer/listas/#{importacao.id}/previa_do_desfazer", headers: cabecalhos(quem)
    response.parsed_body
  end

  # O clique e o job, um depois do outro.
  def desfazer(importacao, quem: admin)
    post "#{base}/listas/#{importacao.id}/desfazer", headers: cabecalhos(quem)
    perform_enqueued_jobs(only: job)
    importacao.reload
  end

  def pessoa_do(telefone)
    account.contacts.find_by(phone_number: telefone)
  end

  # A Ana que a conta já tinha antes da lista, ainda sem ser cliente.
  def ana_que_ja_estava
    create(:contact, account: account, name: 'Ana A.', phone_number: telefone_da_ana)
  end

  describe 'a lista em que ninguém mexeu' do
    it 'a prévia conta os seguros que saem sem gravar nada, e o Desfazer tira os seguros e as pessoas que só a lista trouxe' do
      importacao = trazer_tudo(planilha_de(seguros_bons))

      expect(pedir_previa(importacao)).to include('tira' => 2, 'ficam' => 0, 'seguros' => { 'saem' => 4, 'ficam' => 0, 'voltam' => 0 })
      expect([apolices.count, account.contacts.count, importacao.reload.undo_status]).to eq([4, 2, 'pending'])

      expect(desfazer(importacao).undo_status).to eq('completed')
      expect([apolices.count, Carteira::ApoliceEvento.count, account.contacts.count]).to eq([0, 0, 0])
    end

    it 'a parte dos seguros rodar de novo não repete nada' do
      importacao = trazer_tudo(planilha_de(seguros_bons))
      desfazer(importacao)
      de_depois = criar_apolice(create(:contact, account: account), seguradora: 'Seguradora Exemplo', numero: 'EX-001234')

      Carteira::Trazer::DesfazerSeguros.new(importacao.reload).call

      expect(apolices.pluck(:id)).to eq([de_depois.id])
      # Desfeita, a lista não tem mais nada na carteira, mas continua sendo a lista que trouxe seguros.
      lista = Carteira::Trazer::SegurosDaLista.new(importacao)
      expect([lista.tem?, lista.trouxe_seguros?]).to eq([false, true])
    end

    it 'quem já estava na base e virou cliente pelos seguros da lista deixa de ser cliente quando todos saem' do
      ja_estava = ana_que_ja_estava
      importacao = trazer_tudo(planilha_de(seguros_bons))
      expect(ja_estava.reload.contact_type).to eq('customer')

      expect(pedir_previa(importacao))
        .to include('tira' => 1, 'ficam' => 0, 'devolve' => 1, 'seguros' => { 'saem' => 4, 'ficam' => 0, 'voltam' => 0 })
      desfazer(importacao)

      # A data de cliente dela veio do seguro mais antigo, numa linha de baixo: mesmo assim a marca volta.
      expect(ja_estava.reload).to have_attributes(contact_type: 'lead', customer_since: nil, email: nil)
      expect([apolices.count, pessoa_do(telefone_do_bruno)]).to eq([0, nil])
    end
  end

  describe 'o seguro em que alguém mexeu' do
    it 'fica o que foi corrigido, o que ganhou PDF e o cancelado; a pessoa deles continua na base, e cliente' do
      importacao = trazer_tudo(planilha_de(seguros_bons))
      apolice('EX-001234').update!(bem: 'Carro Corrigido', corrigido_a_mao: ['bem'])
      guardar_pdf_na(apolice('EX-005678'))
      apolice('VD-000042').update!(cancelado_em: Time.current)

      expect(pedir_previa(importacao)).to include('tira' => 1, 'ficam' => 1, 'seguros' => { 'saem' => 1, 'ficam' => 3, 'voltam' => 0 })
      desfazer(importacao)

      expect(apolices.order(:numero).pluck(:numero)).to eq(%w[EX-001234 EX-005678 VD-000042])
      expect(apolice('EX-001234')).to have_attributes(bem: 'Carro Corrigido', campaign_import_id: importacao.id)
      expect(apolice('EX-001234').eventos.pluck(:tipo)).to eq(%w[chegou_planilha])
      expect(apolice('EX-005678').pdf).to be_attached
      expect(pessoa_do(telefone_da_ana).contact_type).to eq('customer')
      expect(pessoa_do(telefone_do_bruno)).to be_nil
    end

    it 'com um seguro que fica, quem já estava na base continua cliente' do
      ja_estava = ana_que_ja_estava
      importacao = trazer_tudo(planilha_de(seguros_bons))
      guardar_pdf_na(apolice('VD-000042'))

      desfazer(importacao)

      expect(apolices.pluck(:numero)).to eq(['VD-000042'])
      expect(ja_estava.reload.contact_type).to eq('customer')
    end
  end

  describe 'o seguro que devia sair e a escrita falhou' do
    # O apagar de todo seguro dá erro: nenhum sai. Quem tem seguro na carteira não pode sair da base, senão o seguro iria
    # junto com a pessoa, sem conferência nenhuma.
    before do
      allow_any_instance_of(Carteira::Apolice).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed) # rubocop:disable RSpec/AnyInstance
    end

    it 'o seguro fica, a pessoa dele fica na base, e quem já era da base continua cliente' do
      ja_estava = ana_que_ja_estava
      importacao = trazer_tudo(planilha_de(seguros_bons))

      expect(desfazer(importacao).undo_status).to eq('completed')

      expect(apolices.count).to eq(4)
      expect(pessoa_do(telefone_do_bruno)).to be_present
      expect(ja_estava.reload.contact_type).to eq('customer')
    end
  end

  describe 'o seguro que já existia e a lista só completou' do
    # A Ana já tinha o seguro do carro (sem o bem e com outro valor) e o da casa (com outro valor).
    def seguros_que_ja_estavam(pessoa)
      carro = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-001234', inicio_vigencia: Date.new(2026, 3, 10),
                                    fim_vigencia: Date.new(2027, 3, 10), valor_centavos: 100_000)
      casa = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-005678', tipo: 'residencial',
                                   inicio_vigencia: Date.new(2025, 6, 1), fim_vigencia: Date.new(2026, 6, 1), valor_centavos: 50_000)
      [carro, casa]
    end

    it 'volta ao que era o que ninguém mudou depois; o que alguém mudou fica como está' do
      carro, casa = seguros_que_ja_estavam(ana_que_ja_estava)
      importacao = trazer_tudo(planilha_de(seguros_bons))
      expect([carro.reload.valor_centavos, carro.bem, casa.reload.valor_centavos]).to eq([341_000, 'Carro Exemplo ABC1D23', 89_050])
      # Depois da lista, alguém acertou o valor do seguro da casa.
      casa.update!(valor_centavos: 70_000)

      expect(pedir_previa(importacao)['seguros']).to eq('saem' => 2, 'ficam' => 1, 'voltam' => 1)
      desfazer(importacao)

      expect(apolices.order(:numero).pluck(:numero)).to eq(%w[EX-001234 EX-005678])
      expect(carro.reload).to have_attributes(valor_centavos: 100_000, bem: nil)
      expect(carro.eventos.where(campaign_import_id: importacao.id)).to be_empty
      expect(casa.reload.valor_centavos).to eq(70_000)
      expect(casa.eventos.where(campaign_import_id: importacao.id).pluck(:tipo)).to eq(%w[chegou_de_novo])
    end

    it 'o que teve o card da renovação tirado do quadro depois da lista não volta' do
      carro, = seguros_que_ja_estavam(ana_que_ja_estava)
      importacao = trazer_tudo(planilha_de(seguros_bons))
      carro.reload.update!(renovacao_card_removido_em: Time.current)

      expect(pedir_previa(importacao)['seguros']).to eq('saem' => 2, 'ficam' => 1, 'voltam' => 1)
      desfazer(importacao)

      expect(carro.reload).to have_attributes(valor_centavos: 341_000, bem: 'Carro Exemplo ABC1D23')
      expect(carro.eventos.where(campaign_import_id: importacao.id).pluck(:tipo)).to eq(%w[chegou_de_novo])
    end

    it 'o que foi cancelado depois da lista não volta nem sai' do
      carro, = seguros_que_ja_estavam(ana_que_ja_estava)
      importacao = trazer_tudo(planilha_de(seguros_bons))
      carro.reload.update!(cancelado_em: Time.current)

      expect(pedir_previa(importacao)['seguros']).to eq('saem' => 2, 'ficam' => 1, 'voltam' => 1)
      desfazer(importacao)

      expect(carro.reload).to have_attributes(valor_centavos: 341_000, bem: 'Carro Exemplo ABC1D23')
    end
  end

  describe 'quem pode e de quem é' do
    it 'não toca no seguro de outra conta, nem com o mesmo número, e a outra conta não vê esta lista' do
      outra = conta_com_carteira
      dono = create(:user, account: outra, role: :administrator)
      de_fora = criar_apolice(create(:contact, account: outra), seguradora: 'Seguradora Exemplo', numero: 'EX-001234')
      importacao = trazer_tudo(planilha_de(seguros_bons))

      pedir_previa(importacao, quem: dono, conta: outra)
      expect(response).to have_http_status(:not_found)

      desfazer(importacao)

      expect(apolices.count).to eq(0)
      expect(Carteira::Apolice.where(account_id: outra.id).pluck(:id, :numero)).to eq([[de_fora.id, 'EX-001234']])
    end

    it 'recusa quem não pode importar contatos: a prévia não diz nada dos seguros e nada sai' do
      importacao = trazer_tudo(planilha_de(seguros_bons))

      [agente, agente(permissoes: ['contact_view'])].each do |quem|
        pedir_previa(importacao, quem: quem)
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include('seguros')
        expect { post "#{base}/listas/#{importacao.id}/desfazer", headers: cabecalhos(quem) }.not_to have_enqueued_job(job)
        expect(response).to have_http_status(:unauthorized)
      end
      expect([apolices.count, importacao.reload.undo_status]).to eq([4, 'pending'])
    end
  end
end
