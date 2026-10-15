require 'rails_helper'

# "Um turno, uma ordem" (#1606): a posse do turno é do job_id do settle. No deploy o Sidekiq devolve à fila o job em
# curso (e o retry repete o job) com o mesmo job_id: o mesmo settle rodando de novo responde, outro settle não.
RSpec.describe Autonomia::Agents::Operate::PosseDoTurno, :um_turno do
  include_context 'with crm responsible agent'

  let(:responder) { instance_double(Autonomia::Agents::Operate::Responder, perform: nil) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    allow(Autonomia::Agents::Operate::Responder).to receive(:new).and_return(responder)
  end

  def settle_job(mensagem)
    Autonomia::Agents::Operate::ReplyJob.new(conversation.id, mensagem.id, 'settle')
  end

  it 'o mesmo settle rodado duas vezes (mesmo job_id) responde as duas; outro job_id segue barrado' do
    mensagem = cliente_escreve('oi')
    gatilho(mensagem)
    job = settle_job(mensagem)

    job.perform_now
    job.perform_now # devolvido à fila no deploy: o mesmo job_id
    expect(responder).to have_received(:perform).twice

    linhas = linhas_do_log { settle_job(mensagem).perform_now }

    expect(responder).to have_received(:perform).twice
    expect(linhas.grep(/\[autonomia\]\[turno\] turno_em_curso conv=#{conversation.id} msg=#{mensagem.id}/).size).to eq(1)
  end

  it 'a posse repassada pelo ReenfileirarTurno não é confundida com a de um settle' do
    expect(described_class.tomar?(conversation.id, 10, vinculo_da_porta.id)).to be(true)
    expect(described_class.tomar?(conversation.id, 10, vinculo_da_porta.id)).to be(false)
    expect(described_class.tomar?(conversation.id, 10, vinculo_da_porta.id, dono: 'job-1')).to be(false)
  end

  it 'o settle passa ao Responder o valor da posse: o job_id, ou a posse repassada' do
    mensagem = cliente_escreve('oi')
    gatilho(mensagem)
    job = settle_job(mensagem)
    job.perform_now
    expect(Autonomia::Agents::Operate::Responder).to have_received(:new).with(hash_including(posse: job.job_id))

    settle(mensagem, vinculo_da_porta.id)
    expect(Autonomia::Agents::Operate::Responder).to have_received(:new).with(hash_including(posse: described_class::REPASSADA))
  end

  it 'fora da Fase 2 não lê nem grava a chave' do
    Autonomia::Agents::Fase2.desligar!(account)

    expect(described_class.assumir?(conversation: conversation.reload, agent_inbox: vinculo_da_porta, message_id: 10,
                                    job_id: 'j')).to be(true)
    expect(Redis::Alfred.exists?(described_class.chave(conversation.id, 10, vinculo_da_porta.id))).to be(false)
  end
end
