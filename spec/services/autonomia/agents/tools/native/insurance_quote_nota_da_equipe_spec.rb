require 'rails_helper'

# NINGUÉM ACEITOU, E O MOTIVO VAI PARA A EQUIPE (chat#612, decisão do CEO de 23/09/2026). A Lia não fala de recusa do
# risco: o desfecho sem proposta é `sem_aceitacao`, com fato neutro, e o que cada seguradora escreveu no portal vira
# nota interna da conversa. Dados sintéticos, na forma do `Connector::Http`.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: described_class.slug, arguments: { 'item' => 'Nivus' },
                                     scope: { conversation_id: conversation.id })
  end
  let(:tool) { described_class.new(agent: agent, params: {}, run: run) }
  let(:veiculo) { 'Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida' }

  before do
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
  end

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def recusou(code, name, kind: 'risco', text: 'Tipo de veículo não aceito.', status: 'declined')
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status, 'reason' => { 'kind' => kind, 'text' => text } }
  end

  def cotou(code, name)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => 2119.18, 'currency' => 'BRL', 'basis' => 'total' } }
  end

  def handle_com(ofertas)
    { described_class::RESULTADO_KEY => Autonomia::Insurance::ResultadoPorSeguradora.unir({}, ofertas) }
  end

  describe '#sem_aceitacao?' do
    it 'nenhuma com preço e alguma recusou escrevendo: verdade' do
      handle = handle_com([recusou('19', 'Sancor'), recusou('13', 'Mitsui', kind: 'passageiro', text: 'Serviço indisponível')])

      expect(tool.sem_aceitacao?(handle)).to be(true)
    end

    it 'com preço de alguma: falso' do
      expect(tool.sem_aceitacao?(handle_com([cotou('8', 'Porto Seguro'), recusou('19', 'Sancor')]))).to be(false)
    end

    # Só instabilidade ou só credencial da corretora não é "ninguém aceitou": é falha, e o desfecho continua `falhou`.
    it 'sem recusa escrita (instabilidade, credencial, nada guardado): falso' do
      instavel = handle_com([recusou('13', 'Mitsui', kind: 'passageiro')])
      credencial = handle_com([recusou('4', 'Hdi', kind: 'credencial', status: 'auth_required')])

      expect([tool.sem_aceitacao?(instavel), tool.sem_aceitacao?(credencial), tool.sem_aceitacao?({})]).to all(be(false))
    end
  end

  describe '#nota_da_equipe' do
    # chat#638: a equipe recebe o motivo de TODA seguradora sem proposta, porque a Lia não fala de nenhuma delas.
    it 'uma linha por seguradora sem proposta, com o motivo de cada uma; quem cotou fica de fora' do
      handle = handle_com([cotou('8', 'Porto Seguro'), recusou('19', 'Sancor', text: veiculo), recusou('7', 'Zurich', kind: 'outro'),
                           recusou('13', 'Mitsui', kind: 'passageiro', text: 'Serviço indisponível'),
                           recusou('4', 'Hdi', kind: 'credencial', status: 'auth_required'),
                           { 'insurer' => { 'code' => '47', 'name' => 'Justos' }, 'status' => 'running' }])

      linhas = tool.nota_da_equipe(handle).split("\n")

      expect(linhas.first).to eq(format(described_class::CABECALHO, cotacao: 'auto, Nivus', run: run.id))
      expect(linhas.drop(1)).to contain_exactly(
        "- Sancor: #{format(described_class::RECUSOU, texto: veiculo)}",
        "- Zurich: #{format(described_class::RECUSOU, texto: 'Tipo de veículo não aceito.')}",
        "- Mitsui: #{described_class::INSTAVEL}", "- Hdi: #{described_class::SEM_MOTIVO}",
        "- Justos: #{described_class::SEM_RESPOSTA}"
      )
    end

    # O prazo da rodada 1 (24/09/2026): ninguém recusou por escrito, e ainda assim a equipe precisa saber quem ficou de
    # fora, porque a Lia não fala disso.
    it 'sem recusa escrita, a nota sai com quem não respondeu ou estava instável' do
      handle = handle_com([cotou('8', 'Porto Seguro'), recusou('13', 'Mitsui', kind: 'passageiro'),
                           { 'insurer' => { 'code' => '47', 'name' => 'Justos' }, 'status' => 'running' }])

      expect(tool.nota_da_equipe(handle).split("\n").drop(1))
        .to contain_exactly("- Mitsui: #{described_class::INSTAVEL}", "- Justos: #{described_class::SEM_RESPOSTA}")
    end

    it 'todas com preço, ou nada guardado: nil' do
      expect(tool.nota_da_equipe(handle_com([cotou('8', 'Porto Seguro')]))).to be_nil
      expect(tool.nota_da_equipe({})).to be_nil
    end
  end

  # O evento neutro: o fato não fala de recusa nem de motivo, manda encaminhar à equipe (o gatilho da passagem no CRM)
  # e não oferece cotar de novo.
  it 'os fatos de sem_aceitacao não falam de motivo e encaminham à equipe' do
    fatos = described_class.fatos_do_evento('sem_aceitacao', run)

    expect(fatos).to include('nenhuma seguradora trouxe proposta desta vez', 'Não fale de recusa, de risco',
                             'vai encaminhar para alguém da equipe', 'não ofereça cotar de novo')
    expect(fatos).not_to include('Tipo de veículo')
  end

  # DE PONTA A PONTA, COM A FERRAMENTA DE VERDADE: a conclusão de quem terminou sem proposta dispara o evento neutro, e a
  # nota interna leva à equipe o que o portal escreveu. Ao cliente não sai texto nenhum daqui.
  it 'a conclusão sem proposta dispara sem_aceitacao e deixa a nota interna' do
    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: 1.minute.ago)
    run.merge_handle!(handle_com([recusou('19', 'Sancor', text: veiculo)]).merge('quote_id' => 'abc:1'))
    register_async_tool(described_class)

    Autonomia::Agents::Tools::Encerramento.new(run: run.reload, native: described_class) { raise 'nao publica' }.concluir

    nota = conversation.messages.reload.where(private: true).sole
    expect(eventos_disparados(run)).to eq(['sem_aceitacao'])
    expect(nota.content).to include("- Sancor: #{format(described_class::RECUSOU, texto: veiculo)}")
    expect(conversation.messages.where(private: false)).to be_empty
  end
end
