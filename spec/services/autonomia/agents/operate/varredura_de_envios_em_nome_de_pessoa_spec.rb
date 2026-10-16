require 'rails_helper'

# GUARDA DE ARQUITETURA (#1669): todo envio de mensagem com remetente (ou com remetente invisível, "a revisar") em app,
# lib e enterprise/app tem a marca de envio automático no valor de content_attributes/additional_attributes, ou está em
# REVISADOS com o motivo. Um envio automático novo em nome de pessoa, sem marca, reprova. A varredura mora em
# spec/support/varredura_de_envios_em_nome_de_pessoa{,_marca,_revisados}.rb (a lista de revisados, com o motivo, também).
RSpec.describe VarreduraDeEnviosEmNomeDePessoa do
  def envios_do(codigo)
    arvore = Prism.parse(codigo).value
    described_class.envios_em(arvore, 'x.rb').map { |envio| [envio.tipo, described_class.marcado?(envio, arvore)] }
  end

  it 'acha os envios marcados que já conhecemos (senão a varredura não está olhando)' do
    ids = described_class.envios.map(&:id)

    conhecidos = ['app/services/crm/follow_ups/message_sender.rb#Crm::FollowUps::MessageSender#create_session_message',
                  'app/services/crm/booking_v2/notices/delivery.rb#Crm::BookingV2::Notices::Delivery#build',
                  'app/services/whatsapp_api_campaigns/conversation_recorder.rb#' \
                  'WhatsappApiCampaigns::ConversationRecorder#create_message!']
    expect(ids).to include(*conhecidos)
  end

  it 'todo envio com remetente tem a marca, ou está revisado com motivo' do
    sem_marca = described_class.sem_marca(described_class::REVISADOS)

    aviso = 'envio com remetente sem marca: grave uma marca de MARCAS_DE_ENVIO_AUTOMATICO em content_attributes ou revise'
    expect(sem_marca.map { |envio| "#{envio.arquivo}:#{envio.linha} #{envio.id} (#{envio.tipo})" }).to be_empty, aviso
  end

  it 'a lista de revisados não guarda envio que sumiu' do
    expect(described_class::REVISADOS.keys - described_class.envios.map(&:id)).to be_empty
  end

  describe 'um follow-up novo em nome de pessoa' do
    it 'pelo builder, sem marca: reprova; com crm_follow_up_id em content_attributes: passa' do
      sem = envios_do(<<~RUBY)
        class Lembrete
          def enviar(user, conversa)
            Messages::MessageBuilder.new(user, conversa, ActionController::Parameters.new(content: 'oi')).perform
          end
        end
      RUBY
      com = envios_do(<<~RUBY)
        class Lembrete
          def enviar(user, conversa)
            Messages::MessageBuilder.new(user, conversa,
                                         ActionController::Parameters.new(content: 'oi', content_attributes: { crm_follow_up_id: 1 })).perform
          end
        end
      RUBY

      expect([sem, com]).to eq([[[:com_remetente, false]], [[:com_remetente, true]]])
    end

    it 'por messages.create!(sender:), sem marca: reprova; com marca no método que monta os atributos: passa' do
      sem = envios_do(<<~RUBY)
        class Lembrete
          def enviar(user, conversa)
            conversa.messages.create!(sender: user, message_type: :outgoing, content: 'oi')
          end
        end
      RUBY
      com = envios_do(<<~RUBY)
        class Lembrete
          def enviar(user, conversa)
            conversa.messages.create!(sender: user, message_type: :outgoing, content: 'oi', content_attributes: atributos)
          end

          def atributos
            marcas = { crm_follow_up_id: 1 }
            marcas
          end
        end
      RUBY

      expect([sem, com]).to eq([[[:com_remetente, false]], [[:com_remetente, true]]])
    end

    it 'por sender_type: User com sender_id, sem marca: reprova; sender_type AgentBot não conta como envio de pessoa' do
      sem = envios_do(<<~RUBY)
        class Lembrete
          def enviar(user, conversa)
            Messages::MessageBuilder.new(nil, conversa,
                                         ActionController::Parameters.new(content: 'oi', sender_type: 'User', sender_id: user.id)).perform
          end
        end
      RUBY
      robo = envios_do(<<~RUBY)
        class Lembrete
          def enviar(bot, conversa)
            Messages::MessageBuilder.new(nil, conversa,
                                         ActionController::Parameters.new(content: 'oi', sender_type: 'AgentBot', sender_id: bot.id)).perform
          end
        end
      RUBY

      expect([sem, robo]).to eq([[[:com_remetente, false]], []])
    end

    it 'atributos em variável ou **attrs não passam calados: viram "a revisar"' do
      variavel = envios_do(<<~RUBY)
        class Lembrete
          def enviar(attrs, conversa)
            conversa.messages.create!(attrs)
          end
        end
      RUBY
      splat = envios_do(<<~RUBY)
        class Lembrete
          def enviar(attrs, conversa)
            conversa.messages.create!(content: 'oi', **attrs)
          end
        end
      RUBY

      expect([variavel, splat].map { |lista| lista.map(&:first) }).to eq([[:revisar], [:revisar]])
    end

    it 'a marca fora de content_attributes (ex.: num hash de log) não vale' do
      envio = envios_do(<<~RUBY)
        class Lembrete
          def enviar(user, conversa)
            Rails.logger.info({ crm_follow_up_id: 1 }.to_s)
            conversa.messages.create!(sender: user, message_type: :outgoing, content: 'oi')
          end
        end
      RUBY

      expect(envio).to eq([[:com_remetente, false]])
    end

    it 'o mesmo nome de método em outra classe do arquivo não empresta a marca' do
      envio = envios_do(<<~RUBY)
        class Outro
          def atributos
            { crm_follow_up_id: 1 }
          end
        end

        class Lembrete
          def enviar(user, conversa)
            conversa.messages.create!(sender: user, message_type: :outgoing, content_attributes: atributos)
          end

          def atributos
            { tipo: 'lembrete' }
          end
        end
      RUBY

      expect(envio).to eq([[:com_remetente, false]])
    end
  end
end
