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
  # O começo da vigência que o conector de mentira põe em todos os registros (parte do começo do mês, que não anda dia a
  # dia: o mesmo registro buscado amanhã tem as mesmas datas).
  let(:comeco) { agora.to_date.beginning_of_month.prev_year + 40 }

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

  # Um registro fictício do conector, no formato que o Http entrega.
  def registro(ref:, inicio:, numero: '2001', endosso: nil, premio: 240_000)
    { 'ref' => ref, 'numero' => numero, 'seguradora' => 'Seguradora Azul (exemplo)', 'ramo' => 'Automóvel',
      'inicio_vigencia' => inicio.iso8601, 'fim_vigencia' => (inicio + 1.year).iso8601, 'premio_centavos' => premio,
      'segurado' => { 'nome' => 'Pessoa Exemplo Cinco', 'documento' => '10020030088', 'email' => nil }, 'item' => 'Carro de exemplo',
      'endosso' => endosso, 'parcelas' => nil, 'pdf_ref' => nil }
  end

  # Uma busca de todo dia que já leu estes registros, na ordem dada, pronta para gravar.
  def busca_com(*registros)
    leitura = create(:carteira_leitura, account: account, origem: 'conector', estado: 'trazendo', totais: { 'diaria' => 1 })
    Carteira::Conector::Pedido.criar!(leitura, desde: comeco, ate: agora.to_date)
    Carteira::Conector::Ler.new(leitura).pagina(registros)
    Carteira::Conector::Ler.new(leitura).tipos!
    leitura
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
    # A apólice e o endosso dela são um seguro só: o endosso, mais novo, é o que entra; a apólice fica `repetido`.
    expect(itens.where(estado: %w[trazido repetido]).count + itens.where(estado: 'falhou').count + leitura.totais['ignorados'])
      .to eq(leitura.totais['total'])
    expect(Carteira::Conector::Conferir.new(leitura).call).to include(seguros: 3, repetidos: 1, ignorados: 1, total: 6)
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

  # G1 do #3030: o registro que não muda nada não se liga ao seguro, e a busca do dia seguinte não segura o Desfazer.
  it 'desfazer a busca do dia D depois da busca do dia D+1 tira o seguro que só D criou' do
    dia_d = gravar_a_busca(andar_a_busca(Carteira::Conector::Sincronizar.diaria(account)))
    expect(dia_d.totais['seguros']).to eq(3)
    travel(1.day)

    dia_seguinte = gravar_a_busca(andar_a_busca(Carteira::Conector::Sincronizar.diaria(account)))
    expect(dia_seguinte.itens.where(estado: 'igual').count).to eq(3)
    expect(dia_seguinte.itens.where.not(apolice_id: nil)).to be_empty
    expect(dia_seguinte.totais['seguros']).to eq(0)
    expect(Carteira::Conector::Historico.new(Carteira::Leitura.do_conector.where(account_id: account.id)).call.pluck(:id)).to eq([dia_d.id])

    Carteira::Trazer::Pdfs::Desfazer.new(dia_d, quem: admin).pedir
    perform_enqueued_jobs(only: Carteira::DesfazerPdfsJob)

    expect(dia_d.reload.estado).to eq('desfeita')
    expect(Carteira::Apolice.where(account_id: account.id).count).to eq(0)
  end

  # G2 do #3030: o seguro que veio pela planilha, de uma pessoa sem documento guardado.
  it 'a carteira vinda da planilha: o mesmo seguro não cria pessoa nem seguro em dobro, não é recusado, e o documento fica guardado' do
    pessoa = create(:contact, account: account, name: 'Nome Na Planilha Exemplo')
    da_planilha = criar_apolice(pessoa, seguradora: 'Seguradora Verde (exemplo)', numero: '1002', tipo: 'residencial', origem: 'planilha',
                                        inicio_vigencia: comeco, fim_vigencia: comeco + 1.year)
    leitura = andar_a_busca(Carteira::Conector::Sincronizar.primeira(account, user: admin))
    expect(Carteira::Conector::Conferir.new(leitura).call).to include(seguros: 3, jaNaCarteira: 1, pessoasNovas: 2)

    Carteira::Conector::Trazer.new(leitura).call
    gravar_a_busca(leitura)

    expect(Carteira::Apolice.where(account_id: account.id).count).to eq(3)
    expect(da_planilha.reload).to have_attributes(origem: 'conector', origem_ref: 'mock-ref-2', contact_id: pessoa.id)
    expect(account.contacts.where(name: 'Pessoa Exemplo Dois')).to be_empty
    expect(leitura.reload.totais).not_to include('motivo_apolice_de_outra_pessoa', 'motivo_termo_ambiguo')
    expect(Relacionamentos::Documentos.new(account).donos('40050060007')).to eq([pessoa])
  end

  # G3 do #3030: dois termos da mesma apólice, na mesma busca, em ordem inversa.
  it 'o termo velho entra antes do novo: saem ligados, e o velho não fica esperando renovação' do
    velho_comeca = agora.to_date - 300
    leitura = busca_com(registro(ref: 'ref-termos', inicio: velho_comeca + 1.year), registro(ref: 'ref-termos', inicio: velho_comeca))
    gravar_a_busca(leitura)

    velho = Carteira::Apolice.find_by!(account_id: account.id, inicio_vigencia: velho_comeca)
    novo = Carteira::Apolice.find_by!(account_id: account.id, inicio_vigencia: velho_comeca + 1.year)
    expect(novo.apolice_anterior).to eq(velho)
    expect([velho.origem_ref, novo.origem_ref]).to eq([nil, 'ref-termos'])
    expect(velho.reload.renovado_em).to be_present
    expect(velho.crm_card).to be_nil
    expect(Carteira::Renovacao::EntramHoje.new(account, dias_antes: 90).seguros).not_to include(velho)
  end

  it 'o endosso que chega antes da apólice não é sobrescrito por ela' do
    endosso = { 'numero' => '1', 'data' => (comeco + 30).iso8601 }
    leitura = busca_com(registro(ref: 'ref-endosso', inicio: comeco, endosso: endosso, premio: 260_000), registro(ref: 'ref-endosso', inicio: comeco))
    gravar_a_busca(leitura)

    expect(Carteira::Apolice.where(account_id: account.id).sole.valor_centavos).to eq(260_000)
    expect(leitura.itens.where(estado: 'repetido').count).to eq(1)
  end
end
