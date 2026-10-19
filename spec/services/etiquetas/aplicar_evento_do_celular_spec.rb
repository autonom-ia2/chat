require 'rails_helper'

# #1823, F1b — evento de etiqueta do celular aplicado na plataforma (contrato no WhatsappLabels::AplicarEvento).
RSpec.describe Etiquetas::AplicarEventoDoCelular do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, phone_number: '+5511999990001') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contato, inbox: inbox, source_id: '5511999990001@c.us') }

  def evento(acao, **extra)
    { inbox_id: inbox.id, chat_id: '5511999990001@c.us', contact_phone: '+5511999990001', label_wa_id: '3',
      nome: 'Novo cliente 🔥', color_index: 4, acao: acao, origem: 'celular', at: '2026-10-19T12:00:00Z' }.merge(extra)
  end

  def aplicar(acao, **extra)
    described_class.new(evento(acao, **extra)).perform
  end

  def as(hora)
    "2026-10-19T#{hora}:00Z"
  end

  def conversa(status: :open, contact: contato, ultima: Time.current)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: status,
                          last_activity_at: ultima)
  end

  context 'without the etiquetas_do_celular flag' do
    it 'descarta todo evento, mesmo com a flag do nome livre ligada' do
      account.enable_features!('etiquetas_do_whatsapp')

      %w[criada renomeada vinculada desvinculada apagada].each { |acao| aplicar(acao) }

      expect(Etiquetas::DoCelular.count).to eq(0)
      expect(account.labels.count).to eq(0)
      expect(contato.reload.label_list).to be_empty
    end
  end

  context 'with the flag' do
    before { account.enable_features!('etiquetas_do_celular') }

    describe 'criada' do
      it 'cria a etiqueta com o título técnico do nome e a correspondência com nome e cor do celular' do
        aplicar('criada')

        label = account.labels.sole
        expect(label.title).to eq('novo_cliente')
        expect(Etiquetas::DoCelular.sole).to have_attributes(
          account_id: account.id, inbox_id: inbox.id, label_id: label.id, label_wa_id: '3',
          nome: 'Novo cliente 🔥', color_index: 4, criada_pelo_celular: true
        )
      end

      it 'é idempotente: o mesmo evento duas vezes não duplica' do
        2.times { aplicar('criada') }

        expect(account.labels.count).to eq(1)
        expect(Etiquetas::DoCelular.count).to eq(1)
      end

      it 'reaproveita a etiqueta que já tem o mesmo título, sem dizer que o celular a criou' do
        existente = create(:label, account: account, title: 'novo_cliente')

        aplicar('criada')

        expect(account.labels.count).to eq(1)
        expect(Etiquetas::DoCelular.sole).to have_attributes(label_id: existente.id, criada_pelo_celular: false)
      end

      it 'nome sem letra nem dígito aproveitável vira whatsapp_<id>' do
        aplicar('criada', nome: '🔥 ⭐', label_wa_id: '12')

        expect(account.labels.sole.title).to eq('whatsapp_12')
        expect(Etiquetas::DoCelular.sole.nome).to eq('🔥 ⭐')
      end

      it 'mesma etiqueta do celular em duas caixas: uma correspondência por caixa, um Label só' do
        outra_caixa = create(:inbox, account: account)

        aplicar('criada')
        described_class.new(evento('criada', inbox_id: outra_caixa.id)).perform

        expect(account.labels.count).to eq(1)
        expect(Etiquetas::DoCelular.pluck(:inbox_id)).to contain_exactly(inbox.id, outra_caixa.id)
      end

      it 'caixa que não existe mais: descarta sem erro' do
        expect(described_class.new(evento('criada', inbox_id: 0)).perform).to be_nil
        expect(Etiquetas::DoCelular.count).to eq(0)
      end
    end

    describe 'renomeada' do
      it 'muda só o nome e a cor do celular: o título e o nome livre daqui ficam' do
        aplicar('criada')
        label = account.labels.sole
        Etiquetas::Nome.create!(account: account, label: label, nome: 'Cliente novo')

        aplicar('renomeada', nome: 'Cliente quente', color_index: 7, at: as('13:00'))

        expect(label.reload.title).to eq('novo_cliente')
        expect(Etiquetas::Nome.sole.nome).to eq('Cliente novo')
        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: 'Cliente quente', color_index: 7,
                                                             evento_em: Time.iso8601(as('13:00')))
        expect(account.labels.count).to eq(1)
      end

      it 'renomeada mais velha que a última aplicada é descartada' do
        aplicar('renomeada', nome: 'Nome novo', at: as('13:00'))
        aplicar('renomeada', nome: 'Nome antigo', at: as('11:00'))

        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: 'Nome novo', evento_em: Time.iso8601(as('13:00')))
      end

      it 'nome vazio não apaga o nome guardado; a cor muda' do
        aplicar('criada')

        aplicar('renomeada', nome: '', color_index: 9, at: as('13:00'))
        aplicar('renomeada', nome: nil, color_index: 10, at: as('14:00'))

        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: 'Novo cliente 🔥', color_index: 10)
      end

      it 'corrida em etiqueta_se_faltar: outro evento grava o mesmo título entre a busca e a criação' do
        aplicar('apagada', at: as('12:00')) # marca sem Label
        concorrente = nil
        allow(Label).to receive(:transaction).and_wrap_original do |original, *args, **opcoes, &bloco|
          if concorrente.nil?
            concorrente = :criando
            concorrente = create(:label, account: account, title: 'novo_cliente')
          end
          original.call(*args, **opcoes, &bloco)
        end

        aplicar('criada', at: as('13:00'))

        expect(account.labels.pluck(:id)).to eq([concorrente.id])
        expect(Etiquetas::DoCelular.vivas.sole).to have_attributes(label_id: concorrente.id, criada_pelo_celular: false)
      end

      it 'sem correspondência ainda: cria como em criada' do
        aplicar('renomeada', nome: 'Pago')

        expect(account.labels.sole.title).to eq('pago')
        expect(Etiquetas::DoCelular.sole.nome).to eq('Pago')
      end
    end

    describe 'apagada' do
      it 'a correspondência deixa de valer; a etiqueta daqui fica, inclusive no contato' do
        aplicar('vinculada')
        label = account.labels.sole

        2.times { aplicar('apagada', at: as('13:00')) }

        expect(Etiquetas::DoCelular.vivas.count).to eq(0)
        expect(Etiquetas::DoCelular.sole.apagada_em).to eq(Time.iso8601(as('13:00')))
        expect(Label.exists?(label.id)).to be(true)
        expect(contato.reload.label_list).to eq(['novo_cliente'])
      end

      it 'fora de ordem: apagada (mais nova) antes da criada (mais velha) não cria nada; a vinculada só deixa log' do
        allow(Rails.logger).to receive(:info)
        aplicar('apagada', at: as('13:00'))
        aplicar('criada', at: as('12:00'))
        aplicar('vinculada', at: as('12:30'))

        expect(account.labels.count).to eq(0)
        expect(Etiquetas::DoCelular.vivas.count).to eq(0)
        expect(Etiquetas::DoCelular.sole).to have_attributes(label_id: nil, apagada_em: Time.iso8601(as('13:00')))
        expect(contato.reload.label_list).to be_empty
        expect(Rails.logger).to have_received(:info)
          .with(a_string_including('vinculada de etiqueta apagada no celular', 'label_wa_id=3', 'acao=vinculada'))
      end

      it 'fora de ordem: apagada (mais velha) depois da criada (mais nova) é descartada' do
        aplicar('criada', at: as('13:00'))
        aplicar('apagada', at: as('12:00'))

        expect(Etiquetas::DoCelular.vivas.sole.label.title).to eq('novo_cliente')
      end

      it 'criada de novo depois de apagada (mais nova) volta a valer, com o Label que já existia' do
        aplicar('criada', at: as('12:00'))
        aplicar('apagada', at: as('13:00'))
        aplicar('criada', nome: 'Novo cliente', at: as('14:00'))

        expect(account.labels.count).to eq(1)
        expect(Etiquetas::DoCelular.vivas.sole).to have_attributes(nome: 'Novo cliente', apagada_em: nil)
      end

      it 'apagada que bate no índice único (outro evento criou ao mesmo tempo) espera e apaga o que ele gravou' do
        aplicar('criada', at: as('12:00'))
        servico = described_class.new(evento('apagada', at: as('13:00')))
        primeira = true
        allow(servico).to receive(:correspondencia_travada).and_wrap_original do |original|
          if primeira
            primeira = false
            next nil
          end
          original.call
        end

        servico.perform

        expect(Etiquetas::DoCelular.sole).to have_attributes(apagada_em: Time.iso8601(as('13:00')))
      end

      it 'criada depois de uma apagada que chegou antes (marca sem Label) cria o Label' do
        aplicar('apagada', at: as('12:00'))
        aplicar('criada', at: as('13:00'))

        expect(Etiquetas::DoCelular.vivas.sole).to have_attributes(label: account.labels.sole, criada_pelo_celular: true)
      end
    end

    describe 'vinculada' do
      it 'põe a etiqueta no contato e na conversa aberta mais recente dele nesta caixa' do
        antiga = conversa(ultima: 2.days.ago)
        recente = conversa(ultima: 1.hour.ago)
        resolvida = conversa(status: :resolved, ultima: Time.current)
        adiada = conversa(status: :snoozed, ultima: Time.current)

        aplicar('vinculada')

        expect(contato.reload.label_list).to eq(['novo_cliente'])
        expect(recente.reload.label_list).to eq(['novo_cliente'])
        expect(antiga.reload.label_list).to be_empty
        expect(resolvida.reload.label_list).to be_empty
        expect(adiada.reload.label_list).to be_empty
      end

      it 'conversa pendente (robô atendendo) mais recente também conta como em andamento' do
        aberta = conversa(ultima: 2.hours.ago)
        pendente = conversa(status: :pending, ultima: 1.hour.ago)

        aplicar('vinculada')

        expect(pendente.reload.label_list).to eq(['novo_cliente'])
        expect(aberta.reload.label_list).to be_empty
      end

      it 'sem correspondência: cria a etiqueta antes de aplicar' do
        aplicar('vinculada')

        expect(Etiquetas::DoCelular.sole.label.title).to eq('novo_cliente')
      end

      it 'correspondência criada por vinculada fica com o relógio no piso: a criada mais velha que chega depois vence' do
        aplicar('vinculada', nome: 'Do vínculo', color_index: 1, at: as('10:00'))
        expect(Etiquetas::DoCelular.sole.evento_em).to eq(described_class::PISO_DO_RELOGIO)

        aplicar('criada', nome: 'Da criação', color_index: 6, at: as('05:00'))

        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: 'Da criação', color_index: 6,
                                                             evento_em: Time.iso8601(as('05:00')))
        expect(contato.reload.label_list).to eq(['do_vínculo'])
      end

      it 'é idempotente e mantém as etiquetas que o contato já tinha' do
        contato.update_labels(['vip'])
        recente = conversa

        2.times { aplicar('vinculada') }

        expect(contato.reload.label_list).to contain_exactly('vip', 'novo_cliente')
        expect(recente.reload.label_list).to eq(['novo_cliente'])
      end

      it 'acha o contato pelo chat id (source_id) quando o telefone não bate' do
        aplicar('vinculada', contact_phone: nil)

        expect(contato.reload.label_list).to eq(['novo_cliente'])
      end

      it 'acha o contato pelo chat id guardado pelo conector WAHA (atributos do contato)' do
        contact_inbox.update!(source_id: SecureRandom.uuid)
        contato.update!(custom_attributes: { Waha::ContactChatId::LID => '123456@lid' })

        aplicar('vinculada', contact_phone: '+5511000000000', chat_id: '123456@lid')

        expect(contato.reload.label_list).to eq(['novo_cliente'])
      end

      it 'telefone sem "+" também acha o contato' do
        aplicar('vinculada', contact_phone: '5511999990001', chat_id: nil)

        expect(contato.reload.label_list).to eq(['novo_cliente'])
      end

      it 'não toca contato de outra caixa com o mesmo telefone' do
        outra_caixa = create(:inbox, account: account)
        de_fora = create(:contact, account: account, phone_number: '+5511999990002')
        create(:contact_inbox, contact: de_fora, inbox: outra_caixa)

        aplicar('vinculada', contact_phone: '+5511999990002', chat_id: nil)

        expect(de_fora.reload.label_list).to be_empty
        expect(Etiquetas::DoCelular.count).to eq(1)
      end

      it 'contato não encontrado: guarda a correspondência e não cria contato' do
        expect { aplicar('vinculada', contact_phone: '+5511000000000', chat_id: 'x@c.us') }.not_to change(Contact, :count)

        expect(Etiquetas::DoCelular.count).to eq(1)
      end

      it 'nota na conversa só quando muda: adiciona → 1, repete → nenhuma nova, remove → 1; sem autor falso' do
        account.update!(locale: 'pt_BR')
        recente = conversa
        notas = -> { recente.messages.activity.order(:id).pluck(:content) }

        perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { aplicar('vinculada') }
        expect(notas.call).to eq(['O WhatsApp do celular adicionou a etiqueta Novo cliente 🔥'])

        perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { aplicar('vinculada', at: as('12:30')) }
        expect(notas.call.size).to eq(1)

        perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { aplicar('desvinculada', at: as('13:00')) }
        expect(notas.call.last).to eq('O WhatsApp do celular removeu a etiqueta Novo cliente 🔥')
        expect(notas.call.size).to eq(2)
        expect(Current.executed_by).to be_nil
      end

      it 'nota usa o nome livre, senão o do celular, senão o derivado do título; idioma da conta' do
        recente = conversa
        aplicar('criada')
        Etiquetas::Nome.create!(account: account, label: account.labels.sole, nome: 'Cliente novo')

        perform_enqueued_jobs(only: Conversations::ActivityMessageJob) do
          aplicar('vinculada')
          aplicar('vinculada', label_wa_id: '6', nome: 'Pago ✅')
          aplicar('vinculada', label_wa_id: '7', nome: nil)
        end

        expect(recente.messages.activity.order(:id).pluck(:content))
          .to eq(['WhatsApp on the phone added the label Cliente novo',
                  'WhatsApp on the phone added the label Pago ✅',
                  'WhatsApp on the phone added the label Whatsapp 7'])
      end

      it 'sem conversa em andamento: muda o contato e não cria nota' do
        conversa(status: :resolved)

        perform_enqueued_jobs(only: Conversations::ActivityMessageJob) { aplicar('vinculada') }

        expect(contato.reload.label_list).to eq(['novo_cliente'])
        expect(Message.activity.count).to eq(0)
      end

      it 'vinculada mais velha que a última desvinculada no mesmo contato é descartada' do
        aplicar('desvinculada', at: as('13:00')) # sem correspondência: só log
        aplicar('vinculada', at: as('13:00'))
        aplicar('desvinculada', at: as('14:00'))
        aplicar('vinculada', at: as('13:30'))

        expect(contato.reload.label_list).to be_empty
        expect(Etiquetas::DoCelularNoContato.sole).to have_attributes(vinculada: false, evento_em: Time.iso8601(as('14:00')))
      end

      it 'a ordem é por contato: vinculada atrasada de outro contato não é descartada pela etiqueta' do
        outro = create(:contact, account: account, phone_number: '+5511999990009')
        create(:contact_inbox, contact: outro, inbox: inbox)
        aplicar('renomeada', nome: 'Nome novo', at: as('14:00'))

        aplicar('vinculada', contact_phone: '+5511999990009', chat_id: nil, nome: 'Nome antigo', at: as('13:00'))

        expect(outro.reload.label_list).to eq(['nome_novo'])
        expect(Etiquetas::DoCelular.sole.nome).to eq('Nome novo')
      end

      it 'vinculada mais velha que a renomeada, no mesmo contato: é aplicada, sem mudar o nome e sem log de descarte' do
        aplicar('renomeada', nome: 'Nome novo', at: as('14:00'))
        allow(Rails.logger).to receive(:info)

        aplicar('vinculada', nome: 'Nome antigo', color_index: 1, at: as('13:00'))

        expect(contato.reload.label_list).to eq(['nome_novo'])
        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: 'Nome novo', color_index: 4,
                                                             evento_em: Time.iso8601(as('14:00')))
        expect(Rails.logger).not_to have_received(:info).with(a_string_including('descartado'))
      end

      it 'vinculada e desvinculada mais novas nunca mudam nome, cor nem o relógio da etiqueta' do
        aplicar('criada')

        aplicar('vinculada', nome: 'Outro nome', color_index: 9, at: as('13:00'))
        aplicar('desvinculada', nome: 'Mais outro', color_index: 11, at: as('14:00'))

        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: 'Novo cliente 🔥', color_index: 4,
                                                             evento_em: Time.iso8601(as('12:00')))
      end

      it 'vinculada de etiqueta apagada no celular: não mexe no contato e deixa log' do
        aplicar('criada')
        aplicar('apagada', at: as('13:00'))
        allow(Rails.logger).to receive(:info)

        aplicar('vinculada', at: as('14:00'))

        expect(contato.reload.label_list).to be_empty
        expect(Rails.logger).to have_received(:info)
          .with(a_string_including('vinculada de etiqueta apagada no celular', "inbox=#{inbox.id}", 'label_wa_id=3'))
      end

      it 'falha ao enfileirar a nota depois do commit: o erro sobe, com log' do
        conversa
        allow(Conversations::ActivityMessageJob).to receive(:perform_later).and_raise(RuntimeError, 'fila fora do ar')
        allow(Rails.logger).to receive(:error)

        expect { aplicar('vinculada') }.to raise_error(RuntimeError, 'fila fora do ar')
        expect(Rails.logger).to have_received(:error)
          .with(a_string_including('nota de atividade não enfileirada', 'RuntimeError', 'acao=vinculada'))
        expect(contato.reload.label_list).to eq(['novo_cliente'])
      end

      it 'a nota só vai para a fila depois do commit da transação' do
        conversa
        base = ActiveRecord::Base.connection.open_transactions
        abertas_na_fila = []
        allow(Conversations::ActivityMessageJob).to receive(:perform_later) do
          abertas_na_fila << ActiveRecord::Base.connection.open_transactions
        end

        aplicar('vinculada')

        expect(abertas_na_fila).to eq([base])
      end

      it 'duas etiquetas do celular seguidas no mesmo contato: as duas ficam' do
        recente = conversa

        aplicar('vinculada')
        aplicar('vinculada', label_wa_id: '4', nome: 'Pago', at: as('12:01'))

        expect(contato.reload.label_list).to contain_exactly('novo_cliente', 'pago')
        expect(recente.reload.label_list).to contain_exactly('novo_cliente', 'pago')
      end

      it 'não perde etiqueta gravada por outro processo entre a leitura e a escrita (trava na linha)' do
        aplicar('criada')
        registro = Etiquetas::DoCelular.sole
        obsoleto = Contact.find(contato.id)
        obsoleto.label_list # lido antes de outro processo gravar
        contato.update_labels(['vip'])
        servico = Etiquetas::EtiquetaNoContato.new(registro: registro, evento: evento('vinculada').with_indifferent_access,
                                                   at: Time.iso8601(as('12:00')))
        allow(servico).to receive(:contato_do_evento).and_return(obsoleto)

        expect(servico.aplicar(:adicionar)).to eq(:aplicado)
        expect(contato.reload.label_list).to contain_exactly('vip', 'novo_cliente')
      end

      it 'nome vazio: título whatsapp_<id> e nenhum Label órfão' do
        aplicar('vinculada', nome: nil, label_wa_id: '77')

        expect(account.labels.pluck(:title)).to eq(['whatsapp_77'])
        expect(Etiquetas::DoCelular.sole).to have_attributes(nome: nil, label: account.labels.sole)
        expect(contato.reload.label_list).to eq(['whatsapp_77'])
      end

      it 'se a correspondência não grava, o Label criado junto também não fica' do
        allow(Etiquetas::DoCelular).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Etiquetas::DoCelular.new))

        expect { aplicar('vinculada') }.to raise_error(ActiveRecord::RecordInvalid)
        expect(account.labels.count).to eq(0)
      end

      it 'at inválido não é engolido' do
        expect { aplicar('vinculada', at: 'ontem') }.to raise_error(ArgumentError, /at inválido/)
      end
    end

    describe 'desvinculada' do
      it 'tira a etiqueta do contato e da conversa aberta mais recente, e só ela' do
        recente = conversa
        aplicar('vinculada')
        contato.update_labels(contato.reload.label_list + ['vip'])

        2.times { aplicar('desvinculada', at: as('13:00')) }

        expect(contato.reload.label_list).to eq(['vip'])
        expect(recente.reload.label_list).to be_empty
        expect(Etiquetas::DoCelular.count).to eq(1)
      end

      it 'de etiqueta apagada no celular: não mexe no contato' do
        aplicar('vinculada')
        aplicar('apagada', at: as('13:00'))

        aplicar('desvinculada', at: as('14:00'))

        expect(contato.reload.label_list).to eq(['novo_cliente'])
      end

      it 'sem correspondência: não cria etiqueta nem correspondência e não mexe no contato; só registra no log' do
        contato.update_labels(['novo_cliente'])
        allow(Rails.logger).to receive(:info)

        aplicar('desvinculada')

        expect(account.labels.count).to eq(0)
        expect(Etiquetas::DoCelular.count).to eq(0)
        expect(contato.reload.label_list).to eq(['novo_cliente'])
        expect(Rails.logger).to have_received(:info)
          .with(a_string_including('desvinculada sem correspondência', "inbox=#{inbox.id}", 'label_wa_id=3'))
      end
    end

    it 'ação desconhecida não é engolida' do
      expect { aplicar('arquivada') }.to raise_error(ArgumentError, /arquivada/)
    end
  end

  describe '.titulo_tecnico' do
    it 'segue as regras do formulário do painel, sem regex' do
      expect(described_class.titulo_tecnico('Novo Cliente 🔥')).to eq('novo_cliente')
      expect(described_class.titulo_tecnico('  Orçamento   enviado ')).to eq('orçamento_enviado')
      expect(described_class.titulo_tecnico('-VIP ouro')).to eq('vip_ouro')
      expect(described_class.titulo_tecnico('Pós-venda 2026!')).to eq('pós-venda_2026')
      expect(described_class.titulo_tecnico("Cafe\u0301")).to eq('café')
      expect(described_class.titulo_tecnico('🔥')).to eq('')
    end

    it 'só o espaço separa palavras, como o split(" ") do painel: tab e quebra de linha somem' do
      expect(described_class.titulo_tecnico("a\tb")).to eq('ab')
      expect(described_class.titulo_tecnico("pago\nhoje")).to eq('pagohoje')
      expect(described_class.titulo_tecnico('pago hoje')).to eq('pago_hoje')
    end
  end
end
