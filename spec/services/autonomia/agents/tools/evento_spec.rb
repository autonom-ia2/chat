require 'rails_helper'

# O EVENTO DA EXECUÇÃO (PR C): o slot adquirido no banco e o que o modelo lê. O turno em si está em
# `evento_job_spec`; o desfecho escolhido em cada estado, em `encerramento_spec`.
RSpec.describe Autonomia::Agents::Tools::Evento do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:run) do
    Autonomia::Agents::ToolRun.open!(agent: agent, slug: 'consultar_cotacao', arguments: {},
                                     scope: { conversation_id: conversation.id })
                              .tap { |r| r.promote!(expected_chunks: 0, notify_customer: true, expires_at: 3.minutes.from_now) }
  end

  before { register_async_tool(build_async_tool) }

  describe '.disparar' do
    it 'o comeco e o fecho tem slots proprios: um de cada, e o segundo fecho nao sai' do
      expect(described_class.disparar(run, 'cotacao_comecou')).to be(true)
      expect(described_class.disparar(run.reload, 'falta_dado')).to be(true)
      expect(described_class.disparar(run.reload, 'falhou')).to be(false)
      expect(described_class.disparar(run.reload, 'cotacao_comecou')).to be(false)

      expect(eventos_disparados(run)).to eq(%w[cotacao_comecou falta_dado])
      expect(run.reload.handle).to include(described_class::COMECO_KEY => 'cotacao_comecou', described_class::FECHO_KEY => 'falta_dado')
    end

    it 'o tipo fora da lista fechada nao dispara nem toma o slot' do
      expect(described_class.disparar(run, 'frase pronta')).to be(false)

      expect(eventos_disparados(run)).to be_empty
      expect(run.reload.handle).not_to have_key(described_class::FECHO_KEY)
    end

    it 'a linha que ja nao roda nao dispara' do
      run.finish!('done')

      expect(described_class.disparar(run, 'concluida')).to be(false)
      expect(eventos_disparados(run)).to be_empty
    end

    it 'leva os tokens de depois_de ao turno' do
      described_class.disparar(run, 'concluida', depois_de: ['t-1', nil, ''])

      job = enqueued_jobs.find { |item| item[:job] == Autonomia::Agents::Operate::EventoJob }
      expect(job[:args]).to eq([run.id, 'concluida', 0, 0, ['t-1']])
    end

    it 'as marcas dos slots sao do motor: a ferramenta nao as ve' do
      expect(Autonomia::Agents::Tools::AsyncRunJob::MARCAS).to include(described_class::COMECO_KEY, described_class::FECHO_KEY)
    end
  end

  describe 'o que o modelo le' do
    it 'a nota do sistema diz que nao e a pessoa, o que aconteceu, e traz os fatos da ferramenta' do
      nota = described_class.new(run: run, tipo: 'valores_guardados').nota_do_sistema

      expect(nota).to include('AVISO DO SISTEMA', 'Isto não é mensagem da pessoa',
                              described_class::DESCRICOES['valores_guardados'], 'Fatos: fatos do dublê: valores_guardados')
    end

    it 'sem fatos (a ferramenta levanta, ou nao tem), a nota sai so com a descricao' do
      tool = build_async_tool
      tool.define_singleton_method(:fatos_do_evento) { |_tipo, _run| raise 'banco fora' }
      register_async_tool(tool)

      nota = described_class.new(run: run, tipo: 'falhou').nota_do_sistema

      expect(nota).to include(described_class::DESCRICOES['falhou'])
      expect(nota).not_to include('Fatos:')
    end

    it 'toda descricao existe para todo tipo, sem travessao nem numero' do
      expect(described_class::DESCRICOES.keys).to match_array(described_class::TIPOS)
      described_class::DESCRICOES.each_value do |texto|
        expect(texto).not_to include('—')
        expect(texto.each_char.none? { |caractere| caractere.between?('0', '9') }).to be(true)
      end
    end
  end

  describe '#publicado?' do
    it 've a mensagem, publica ou privada, pela marca exata' do
      evento = described_class.new(run: run, tipo: 'falhou')
      outro = Autonomia::Agents::ToolRun.new(id: "1#{run.id}".to_i)
      create(:message, conversation: conversation, account: account, inbox: inbox, private: true,
                       content_attributes: { described_class::CHAVE => "#{outro.id}:falhou" })
      expect(evento.publicado?(conversation)).to be(false)

      create(:message, conversation: conversation, account: account, inbox: inbox, private: true,
                       content_attributes: { described_class::CHAVE => evento.marca })
      expect(evento.publicado?(conversation)).to be(true)
    end
  end
end
