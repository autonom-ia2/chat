require 'rails_helper'

# #1715: localização e contato (chat#1473; o "+" do atendente, #1702) vão com `content` vazio e o dado em
# `content_attributes.rich_message`. Com a Fase 2, o histórico leva um resumo ("Localização: ...", "Contato: ...") na
# moldura ou no papel de quem enviou; o telefone do contato nunca vai. Sem a Fase 2, igual à main (item vazio).
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza', display_name: 'Ana') }
  let(:historicos) { [] }
  let(:contextos) { [] }
  let(:marca) { Autonomia::Agents::Operate::MolduraDaEquipe.marca(conversation) }
  let(:localizacao) do
    { 'rich_message' => { 'type' => 'location', 'latitude' => -23.5489, 'longitude' => -46.6388,
                          'name' => 'Unidade Centro', 'address' => 'Rua das Flores, 123 - Centro' } }
  end
  let(:contato) do
    { 'rich_message' => { 'type' => 'contact', 'name' => 'Recepção da Unidade Centro', 'phone' => '+55 11 4000-0473',
                          'wa_id' => '551140000473' } }
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |history:, **kwargs|
      historicos << history
      contextos << kwargs[:contexto_do_turno]
      resultado = Autonomia::Agents::AnswerResult.new(reply: 'Certo!', confidence: 0.9, handoff: { should: false, reason: nil },
                                                      used_knowledge: [], answered_from_knowledge: false)
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def escreve(tipo, texto, sender: nil, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto,
                     sender: sender, **extras)
  end

  def moldura_da_ana = "#{marca} Ana, da equipe, escreveu ao cliente. Não foi o cliente nem você."
  def moldura_do_celular = "#{marca} Alguém da equipe, pelo celular, escreveu ao cliente. Não foi o cliente nem você."

  def responder(ultima)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  # O histórico de um turno com `rica` entre a pergunta do cliente e a resposta dele.
  def historico_com(rica_sender: ana, **rica)
    escreve(:incoming, 'Onde fica a loja e com quem eu falo?')
    escreve(:outgoing, '', sender: rica_sender, **rica)
    ultima = escreve(:incoming, 'Obrigado!')
    responder(ultima)
    historicos.sole
  end

  describe 'com a Fase 2 ligada' do
    it 'a localização da Ana chega com a moldura dela e com nome e endereço, e traz a regra do turno' do
      historico = historico_com(content_attributes: localizacao)

      expect(historico.second).to eq(
        role: 'user', content: "#{moldura_da_ana}\nLocalização: Unidade Centro — Rua das Flores, 123 - Centro"
      )
      expect(contextos.sole).to include(marca)
    end

    it 'o contato da Ana chega com a moldura dela e só o nome, sem telefone nem wa_id' do
      historico = historico_com(content_attributes: contato)

      expect(historico.second).to eq(role: 'user', content: "#{moldura_da_ana}\nContato: Recepção da Unidade Centro")
      expect(historico.second[:content]).not_to include('4000', '551140000473')
    end

    it 'o contato mandado pelo celular (eco) chega com a moldura do celular' do
      escreve(:incoming, 'Com quem eu falo?')
      # O eco do celular: outgoing sem remetente (o trait), como no responder_eco_do_celular_spec.
      create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox, content: '',
                                     status: :delivered, content_attributes: contato.merge('external_echo' => true))
      responder(escreve(:incoming, 'Obrigado!'))
      historico = historicos.sole

      expect(historico.second).to eq(role: 'user', content: "#{moldura_do_celular}\nContato: Recepção da Unidade Centro")
    end

    it 'a localização que a própria IA mandou chega como fala dela (assistant), sem moldura' do
      historico = historico_com(rica_sender: agent_bot, content_attributes: localizacao.merge('autonomia_agent_id' => agent.id))

      expect(historico.second).to eq(role: 'assistant', content: 'Localização: Unidade Centro — Rua das Flores, 123 - Centro')
    end

    # #1691 + #1715: o envio automático (aqui, follow-up em nome da Ana) é do atendimento, não da IA nem da Ana.
    it 'o contato de um envio automático em nome da Ana chega com a moldura automática e traz a regra dela' do
      historico = historico_com(content_attributes: contato.merge('crm_follow_up_id' => 7))
      moldura = Autonomia::Agents::Operate::MolduraDaEquipe

      expect(historico.second).to eq(role: 'user',
                                     content: "#{moldura.automatica('x', marca).delete_suffix('x')}Contato: Recepção da Unidade Centro")
      expect(contextos.sole).to include(moldura::CABECALHO_AUTOMATICA)
    end

    it 'a localização de uma automação (sem remetente) chega com a moldura automática' do
      escreve(:incoming, 'Onde fica a loja?')
      # Sem remetente e sem `external_echo` (o trait): a saída de uma automação.
      create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox, content: '',
                                     status: :delivered, content_attributes: localizacao)
      responder(escreve(:incoming, 'Obrigado!'))
      historico = historicos.sole

      expect(historico.second[:role]).to eq('user')
      expect(historico.second[:content]).to start_with("#{marca} Mensagem automática do canal")
      expect(historico.second[:content]).to end_with("\nLocalização: Unidade Centro — Rua das Flores, 123 - Centro")
    end

    it 'localização sem nome nem endereço diz só que foi uma localização, sem as coordenadas' do
      sem_nome = { 'rich_message' => { 'type' => 'location', 'latitude' => -23.5489, 'longitude' => -46.6388 } }
      historico = historico_com(content_attributes: sem_nome)

      expect(historico.second).to eq(role: 'user', content: "#{moldura_da_ana}\nLocalização (sem nome nem endereço)")
      expect(historico.second[:content]).not_to include('-23.5489')
    end

    it 'content vazio sem rich_message continua vazio e sai do que vai ao modelo, sem regra do turno' do
      historico = historico_com

      expect(historico.pluck(:content)).to eq(['Onde fica a loja e com quem eu falo?', '', 'Obrigado!'])
      ao_modelo = Autonomia::Agents::PromptParts::Historico.mensagens(historico)
      expect(ao_modelo.flat_map { |item| item[:content] }.pluck(:text)).to eq(['Onde fica a loja e com quem eu falo?', 'Obrigado!'])
      expect(contextos.sole).to be_nil
    end

    it 'mensagem com texto e formato segue com o texto (o resumo é só para content vazio)' do
      pedido = { 'rich_message' => { 'type' => 'location_request' } }
      escreve(:incoming, 'Oi')
      escreve(:outgoing, 'Me manda onde você está?', sender: ana, content_attributes: pedido)
      responder(escreve(:incoming, 'Ok'))

      expect(historicos.sole.second).to eq(role: 'user', content: "#{moldura_da_ana}\nMe manda onde você está?")
    end

    it 'localização da Ana que falhou no envio não ganha moldura e sai do histórico' do
      historico = historico_com(content_attributes: localizacao, status: :failed)

      expect(historico.second).to eq(role: 'user', content: '')
      expect(contextos.sole).to be_nil
    end
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'o histórico fica igual ao da main: localização e contato vão vazios' do
      escreve(:incoming, 'Oi')
      escreve(:outgoing, '', sender: ana, content_attributes: localizacao)
      escreve(:outgoing, '', sender: agent_bot, content_attributes: contato)
      responder(escreve(:incoming, 'Obrigado!'))

      expect(historicos.sole).to eq(
        [{ role: 'user', content: 'Oi' },
         { role: 'assistant', content: '' },
         { role: 'assistant', content: '' },
         { role: 'user', content: 'Obrigado!' }]
      )
      expect(contextos.sole).to be_nil
    end
  end
end
