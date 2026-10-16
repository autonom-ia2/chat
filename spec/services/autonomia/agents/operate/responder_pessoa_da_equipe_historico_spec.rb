require 'rails_helper'

# #1669 (a): a Ana, da equipe, responde o cliente sem se atribuir, e a IA segue na conversa. O que a Ana escreveu
# chegava ao modelo como `assistant`, e a IA lia como se fosse dela. Com a Fase 2, vai como item `user` marcado com o
# nome que o painel mostra; a mensagem do robô segue igual; a marca nunca sai ao cliente. Sem a Fase 2, igual à main.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot)
  end
  let(:ana) do
    create(:user, account: account, role: :agent, name: 'Ana Souza', display_name: 'Ana',
                  email: 'ana.souza@exemplo.com.br')
  end
  let(:historicos) { [] }
  let(:marca_da_ana) { '[Ana, da equipe, escreveu ao cliente. Não foi o cliente nem você.]' }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before { conversation.update!(ai_assignee: agent_bot) }

  def escreve(tipo, texto, sender: nil, **extras)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: tipo, content: texto,
                     sender: sender, **extras)
  end

  # A IA dublada: guarda o histórico que recebeu e devolve `reply`.
  def ia_responde!(reply = 'Pode deixar, já confiro.')
    allow(Autonomia::Agents::Answerer).to receive(:new) do |history:, **|
      historicos << history
      resultado = Autonomia::Agents::AnswerResult.new(reply: reply, confidence: 0.9, handoff: { should: false, reason: nil },
                                                      used_knowledge: [], answered_from_knowledge: false)
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def responder(ultima)
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  def conversa_com_a_ana
    escreve(:incoming, 'Meu boleto venceu, e agora?')
    escreve(:outgoing, 'Olá! Sou a Clara, posso ajudar.', sender: agent_bot)
    escreve(:outgoing, 'Te mando a segunda via ainda hoje.', sender: ana)
    escreve(:outgoing, 'Nota interna: cliente antigo.', sender: ana, private: true)
    escreve(:incoming, 'Obrigado! E o valor muda?')
  end

  describe 'com a Fase 2 ligada' do
    it 'a mensagem da Ana chega ao modelo como item do usuário, marcada com o nome do painel' do
      ia_responde!
      responder(conversa_com_a_ana)

      item = historicos.sole.find { |linha| linha[:content].to_s.include?('segunda via') }
      expect(item).to eq(role: 'user', content: "#{marca_da_ana}\nTe mando a segunda via ainda hoje.")
      expect(item[:content]).not_to include('ana.souza@exemplo.com.br')
    end

    it 'a mensagem do robô e a do cliente seguem como hoje, e a nota privada não entra' do
      ia_responde!
      responder(conversa_com_a_ana)

      expect(historicos.sole).to eq(
        [{ role: 'user', content: 'Meu boleto venceu, e agora?' },
         { role: 'assistant', content: 'Olá! Sou a Clara, posso ajudar.' },
         { role: 'user', content: "#{marca_da_ana}\nTe mando a segunda via ainda hoje." },
         { role: 'user', content: 'Obrigado! E o valor muda?' }]
      )
    end

    it 'no pedido ao modelo, a mensagem da Ana vai como texto de entrada, nunca como fala dele (output_text)' do
      item = { role: 'user', content: "#{marca_da_ana}\nTe mando a segunda via." }
      montado = Autonomia::Agents::PromptParts::Historico.mensagens([item]).sole

      expect(montado).to eq(role: 'user', content: [{ type: 'input_text', text: item[:content] }])
    end

    it 'sem nome de exibição, usa o nome; nunca o e-mail' do
      ana.update!(display_name: nil)
      ia_responde!
      responder(conversa_com_a_ana)

      expect(historicos.sole.third[:content]).to start_with('[Ana Souza, da equipe, escreveu ao cliente.')
    end

    it 'a marca que o modelo imitou no começo da resposta não sai ao cliente' do
      ia_responde!("#{marca_da_ana}\nO valor não muda, fica o mesmo.")
      resultado = responder(conversa_com_a_ana)

      expect(resultado.message.content).to eq('O valor não muda, fica o mesmo.')
      expect(resultado.message.content).not_to include(Autonomia::Agents::Operate::PessoaDaEquipe::CHAVE_DA_MARCA)
    end

    it 'a marca imitada com o nome da própria IA, na mesma linha, também sai' do
      ia_responde!('[Clara, da equipe, escreveu ao cliente] O valor não muda.')
      resultado = responder(conversa_com_a_ana)

      expect(resultado.message.content).to eq('O valor não muda.')
    end

    it 'resposta que era só a marca vira silêncio, e nada é postado' do
      ia_responde!(marca_da_ana)
      ultima = conversa_com_a_ana

      expect { responder(ultima) }.not_to(change { conversation.messages.outgoing.where(sender_type: 'AgentBot').count })
    end

    it 'texto do modelo com colchetes que não são a marca fica como está' do
      ia_responde!('[Importante] O valor não muda.')
      resultado = responder(conversa_com_a_ana)

      expect(resultado.message.content).to eq('[Importante] O valor não muda.')
    end
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'o histórico fica igual ao da main: a mensagem da Ana vai como assistant, sem marca' do
      ia_responde!
      responder(conversa_com_a_ana)

      expect(historicos.sole).to eq(
        [{ role: 'user', content: 'Meu boleto venceu, e agora?' },
         { role: 'assistant', content: 'Olá! Sou a Clara, posso ajudar.' },
         { role: 'assistant', content: 'Te mando a segunda via ainda hoje.' },
         { role: 'user', content: 'Obrigado! E o valor muda?' }]
      )
    end

    it 'a resposta do modelo não é mexida' do
      ia_responde!("#{marca_da_ana}\nO valor não muda.")
      resultado = responder(conversa_com_a_ana)

      expect(resultado.message.content).to eq("#{marca_da_ana}\nO valor não muda.")
    end
  end
end
