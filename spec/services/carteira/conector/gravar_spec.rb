require 'rails_helper'

# E7 (#2900) — a busca no Agger vira seguros na carteira: pelo gravador único, com a referência do registro, sem
# duplicar quando busca de novo, com o endosso atualizando o mesmo seguro e a renovação feita fora do sistema fechando o
# card da anterior. A pessoa é achada pelo documento, nunca pelo nome. Tudo fictício, com o conector de mentira.
RSpec.describe Carteira::Conector::Gravar, :aggregate_failures do
  include ActiveJob::TestHelper

  # Meio-dia em São Paulo.
  let(:agora) { Time.utc(2026, 11, 12, 15) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  # O começo da vigência que o conector de mentira põe em todos os registros.
  let(:comeco) { agora.to_date.prev_year + 10 }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    travel_to(agora)
    enable_test_encryption!
    sem_pergunta_paga_do_ramo
    conectar_agger!(account)
  end

  def buscar_e_trazer
    leitura = andar_a_busca(Carteira::Conector::Sincronizar.primeira(account, user: admin))
    Carteira::Conector::Trazer.new(leitura).call
    gravar_a_busca(leitura)
  end

  def dono_com_documento(nome, documento, **dados)
    create(:contact, account: account, name: nome, **dados).tap do |pessoa|
      Relacionamentos::Documentos.new(account).guardar(pessoa, documento)
    end
  end

  it 'traz pelo gravador único, com a referência, e a conta fecha com o total do conector' do
    leitura = buscar_e_trazer

    apolices = Carteira::Apolice.where(account_id: account.id)
    expect(apolices.count).to eq(3)
    expect(apolices.pluck(:origem).uniq).to eq(['conector'])
    expect(apolices.pluck(:origem_ref)).to match_array(%w[mock-ref-1 mock-ref-2 mock-ref-4])
    expect(leitura).to have_attributes(estado: 'trazida')
    expect(leitura.totais.values_at('seguros', 'pessoas', 'pessoas_novas', 'nao_entraram')).to eq([3, 3, 3, 0])
    itens = leitura.itens.where.not(estado: 'pedido')
    expect(itens.where(estado: 'trazido').count + itens.where(estado: 'falhou').count + leitura.totais['ignorados'])
      .to eq(leitura.totais['total'])
    expect(apolices.find_by(origem_ref: 'mock-ref-1').eventos.order(:id).first.tipo).to eq('chegou_agger')
  end

  it 'o endosso atualiza o mesmo seguro, e a pessoa nasce sem telefone' do
    buscar_e_trazer

    seguro = Carteira::Apolice.find_by!(account_id: account.id, origem_ref: 'mock-ref-1')
    expect(seguro.valor_centavos).to eq(260_000)
    expect(seguro.contact).to have_attributes(name: 'Pessoa Exemplo Um', email: 'pessoa.um@exemplo.test', phone_number: nil)
  end

  it 'buscar de novo nunca duplica seguro nem pessoa' do
    buscar_e_trazer
    travel(1.day)

    expect do
      diaria = andar_a_busca(Carteira::Conector::Sincronizar.diaria(account))
      gravar_a_busca(diaria)
    end.not_to(change { [Carteira::Apolice.where(account_id: account.id).count, account.contacts.count] })
  end

  it 'liga a busca de todo dia na primeira busca trazida e põe os PDFs na fila só com o id' do
    expect { buscar_e_trazer }.to have_enqueued_job(Carteira::Conector::PdfsJob).with(kind_of(Integer))
    expect(Carteira::Conector::BuscaDiaria.new(account).ligada?).to be(true)
  end

  it 'acha a pessoa pelo documento, nunca pelo nome, e não dá à pessoa nova o e-mail que já é de outra' do
    ja_estava = dono_com_documento('Nome Diferente Exemplo', '40050060007')
    create(:contact, account: account, name: 'Pessoa Exemplo Quatro')
    create(:contact, account: account, name: 'Outra Pessoa Exemplo', email: 'pessoa.um@exemplo.test')

    buscar_e_trazer

    expect(Carteira::Apolice.find_by!(origem_ref: 'mock-ref-2').contact).to eq(ja_estava)
    expect(Carteira::Apolice.find_by!(origem_ref: 'mock-ref-4').contact.name).to eq('Pessoa Exemplo Quatro')
    expect(account.contacts.where(name: 'Pessoa Exemplo Quatro').count).to eq(2)
    expect(Carteira::Apolice.find_by!(origem_ref: 'mock-ref-1').contact.email).to be_nil
  end

  it 'a renovação feita fora do sistema se liga à anterior e fecha o card de renovação dela' do
    pessoa = dono_com_documento('Pessoa Exemplo Dois', '40050060007')
    anterior = criar_apolice(pessoa, seguradora: 'Seguradora Antiga Exemplo', numero: 'AN-000001', tipo: 'residencial',
                                     ramo_original: 'Residencial', inicio_vigencia: comeco - 365, fim_vigencia: comeco)
    card = por_em_renovacao(anterior, escolher_funil_de_renovacao(account, user: admin))

    buscar_e_trazer

    nova = Carteira::Apolice.find_by!(origem_ref: 'mock-ref-2')
    expect(nova.apolice_anterior).to eq(anterior)
    expect(card.reload.status).to eq('won')
    expect(anterior.reload.renovado_em).to be_present
  end

  it 'o registro sem documento e sem seguro guardado não entra, e os outros seguem' do
    leitura = andar_a_busca(Carteira::Conector::Sincronizar.primeira(account, user: admin))
    item = leitura.itens.where(estado: 'lido').order(:posicao).last
    item.update!(campos: item.campos.except('segurado_documento'))
    Carteira::Conector::Trazer.new(leitura).call
    gravar_a_busca(leitura)

    expect(item.reload.estado).to eq('nao_entrou')
    expect(leitura.reload.totais).to include('motivo_sem_pessoa' => 1, 'nao_entraram' => 1, 'seguros' => 2)
  end

  it 'desfazer a busca tira os seguros e as pessoas que ela trouxe e em que ninguém mexeu' do
    leitura = buscar_e_trazer

    Carteira::Trazer::Pdfs::Desfazer.new(leitura, quem: admin).pedir
    perform_enqueued_jobs(only: Carteira::DesfazerPdfsJob)

    expect(leitura.reload.estado).to eq('desfeita')
    expect(Carteira::Apolice.where(account_id: account.id).count).to eq(0)
    expect(account.contacts.count).to eq(0)
  end
end
