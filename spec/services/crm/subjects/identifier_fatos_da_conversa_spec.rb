require 'rails_helper'

# IA entende a conversa F1: a IA de assunto lê a hora e quem falou, e a frase que explica isso vai ao Jev e ao modelo
# maior, só com a flag `crm_ia_fatos_da_conversa`. Sem ela, a pergunta e a entrada são as de sempre.
RSpec.describe Crm::Subjects::Identifier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Funil').first }
  let(:nosso_robo) { create(:agent_bot, account: account) }
  let(:frase) { Crm::Ai::FatosDaConversa::INSTRUCAO_DO_ASSUNTO }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    Autonomia::Agents::AgentInbox.create!(account: account, inbox: inbox, agent_bot: nosso_robo,
                                          agent: Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'sdr'))
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: pipeline.stages.first, created_by: admin)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    resposta = { resposta: Crm::Subjects::Question::SEM_ASSUNTO, titulo: '', seguro: true, motivo: 'ok' }
    allow(cliente).to receive(:create).and_return(text: resposta.to_json)
  end

  def falar(tipo, sender, conteudo)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, sender: sender, content: conteudo)
  end

  def identificador
    falar(:incoming, contact, 'Quero saber o preço')
    described_class.new(conversation: conversation, message: falar(:outgoing, nosso_robo, 'Escolha uma opção'))
  end

  def revisar(leitor)
    jev = TypesafeAi::Decisor::Resultado.new(resposta: Crm::Subjects::Question::SEM_ASSUNTO, certeza: 0.1)
    Crm::Subjects::Reviewer.new(leitor.send(:question)).revisar(leitor.send(:estado), jev)
  end

  context 'with the flag on' do
    before { account.enable_features!(Crm::Ai::FatosDaConversa::FLAG) }

    it 'a conversa leva quem falou e a pergunta leva a frase, no Jev e no modelo maior', :aggregate_failures do
      leitor = identificador
      question = leitor.send(:question)

      expect(leitor.send(:estado).conversa[:messages].last).to end_with('Our assistant (AI): Escolha uma opção')
      expect(question.instrucoes).to end_with(frase)
      revisar(leitor)
      expect(cliente).to have_received(:create).with(hash_including(instructions: a_string_ending_with(frase)))
    end
  end

  it 'sem a flag, a pergunta e a conversa são as de sempre', :aggregate_failures do
    leitor = identificador
    question = leitor.send(:question)

    expect(leitor.send(:estado).conversa[:messages].last).to eq('Team: Escolha uma opção')
    expect(question.instrucoes).to eq(Crm::Subjects::Question::INSTRUCOES)
    revisar(leitor)
    expect(cliente).to have_received(:create).with(hash_including(instructions: Crm::Subjects::Reviewer::INSTRUCOES))
  end
end
