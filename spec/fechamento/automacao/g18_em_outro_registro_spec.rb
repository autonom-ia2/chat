require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G18 (#2671): agir em outro registro ligado ao alvo. Provado nos pedaços dos
# exemplos que dependem dela, montados e ligados pela API da tela, com o gatilho chegando pelo despacho da plataforma e a
# mensagem parando no receptor do WhatsApp oficial:
# - exemplo 11, passo 7: "Card do João ganho: manda à Maria 'O João virou cliente!'" e "põe na Maria a etiqueta";
# - exemplo 16, passo 4: a resposta "fala do motivo da perda gravado no card antigo", na conversa em que o cliente
#   escreveu.
# Os dois exemplos inteiros ficam no pendentes_spec até as outras lacunas deles fecharem.
RSpec.describe 'Fechamento #2414 · G18: agir em outro registro', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Lu Dona') }
  let(:funil) { create_crm_pipeline(account: account, user: dona).first }

  def contato(nome, telefone) = create(:contact, account: account, name: nome, phone_number: "+55#{telefone}")

  def conversa_de(contato)
    contact_inbox = ContactInbox.find_by(inbox: inbox, contact: contato) ||
                    create(:contact_inbox, inbox: inbox, contact: contato, source_id: contato.phone_number.delete('+'))
    create(:conversation, account: account, inbox: inbox, contact: contato, contact_inbox: contact_inbox, status: :open)
  end

  def card_de(contato, conversa, **atributos)
    account.crm_cards.create!(pipeline: funil, stage: funil.stages.first, inbox: inbox, contact: contato, primary_conversation: conversa,
                              currency: 'BRL', **atributos)
  end

  def em_outro(registro, *passos) = { id: 'outro', tipo: 'em_outro_registro', registro: registro, passos: passos }

  def mensagem(id, *texto) = { id: id, tipo: 'mensagem', texto: texto }

  def ligada(receita)
    automacao = montar_automacao(dona, account, nome: 'Em outro registro', receita: receita)
    ligar_automacao(dona, account, automacao)
    clear_enqueued_jobs
    automacao
  end

  # Um job por vez, como no Sidekiq, com o do evento do card e o que abre as filhas no meio.
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def execucoes(automacao) = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).order(:id)

  def filhas(automacao) = execucoes(automacao).where('evento LIKE ?', 'em:%')

  def inicio_da(filha) = Autonomia::Automacao::Registro.find_by!(execucao: filha, passo: 'inicio').dados

  def saidas(conversa) = conversa.messages.outgoing.pluck(:content)

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    create(:inbox_member, user: dona, inbox: inbox)
    receptor_whatsapp_cloud
  end

  after { Current.reset }

  describe 'exemplo 11: o card do João, ganho, age na Maria, que o indicou' do
    let(:maria) { contato('Maria', '11900000011') }
    let(:joao) { contato('João', '11900000012') }
    let!(:conversa_da_maria) { conversa_de(maria) }
    let!(:conversa_do_joao) { conversa_de(joao) }
    let!(:card_do_joao) { card_de(joao, conversa_do_joao, title: 'Banho do Rex', custom_attributes: { 'indicado_por' => maria.id }) }

    let(:receita) do
      { gatilho: { tipo: 'card.ganho', funil_id: funil.id },
        passos: [em_outro({ de: 'contato_do_campo', campo: { '$valor' => 'card.atributos.indicado_por' }, usar: 'conversa' },
                          mensagem('presente', 'Oi, ', { '$valor' => 'contato.nome' }, '! O João virou cliente. O próximo banho é por nossa conta.'),
                          { id: 'etiqueta', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Indicou e fechou',
                            caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['indicou_e_fechou'] } })] }
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_display_name: 'Indicado por',
                                           attribute_model: :card_attribute, attribute_display_type: :number)
      create(:label, account: account, title: 'indicou_e_fechou', description: 'Indicou e o amigo fechou')
      create(:message, conversation: conversa_da_maria, account: account, inbox: inbox, message_type: :incoming, sender: maria,
                       content: 'Indiquei o João!')
    end

    it 'manda a mensagem na conversa da Maria e põe a etiqueta nela; o João fica como estava', :aggregate_failures do
      automacao = ligada(receita)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      expect(saidas(conversa_da_maria)).to eq(['Oi, Maria! O João virou cliente. O próximo banho é por nossa conta.'])
      expect(chamadas_para('graph.facebook.com').map { |chamada| chamada.corpo['to'] }).to eq(['5511900000011'])
      expect(maria.reload.label_list).to eq(['indicou_e_fechou'])
      expect(saidas(conversa_do_joao)).to be_empty
      expect(joao.reload.label_list).to be_empty

      filha = filhas(automacao).sole
      expect(filha).to have_attributes(alvo: conversa_da_maria, estado: 'concluida', cadeia: execucoes(automacao).first.cadeia)
      expect(inicio_da(filha)).to include('conversa_id' => conversa_da_maria.display_id, 'conversa_de' => 'registro')
      expect(historico_de(automacao)).to eq([['outro', 'ok', nil], %w[inicio ok em_outro_registro], ['presente', 'ok', nil], ['etiqueta', 'ok', nil]])
    end

    it 'o card sem quem indicou não abre filha: o passo pula com o motivo', :aggregate_failures do
      card_do_joao.update!(custom_attributes: {})
      automacao = ligada(receita)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      expect(historico_de(automacao)).to eq([%w[outro pulado faltou_valor]])
      expect(filhas(automacao)).to be_empty
    end
  end

  describe 'exemplo 16: a resposta lê o card perdido do mesmo contato' do
    let(:paulo) { contato('Paulo', '11900000016') }
    let(:perdido_mais_recente) { { de: 'cards_do_contato', situacao: ['lost'], mais_recente: true } }
    let!(:conversa_antiga) { conversa_de(paulo) }
    let!(:conversa) { conversa_de(paulo) }
    let!(:card_perdido) { card_de(paulo, conversa_antiga, title: 'Seguro 2025', status: :lost, lost_reason: 'achou caro') }

    let(:resposta) { mensagem('resposta', 'Da outra vez pesou: ', { '$valor' => 'card.motivo_da_perda' }, '. Este ano consigo melhor.') }
    let(:recebida) { [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }] }

    def receita(registro, filtros: recebida) = { gatilho: { tipo: 'mensagem.criada', filtros: filtros }, passos: [em_outro(registro, resposta)] }

    it 'responde na conversa em que o cliente escreveu, com o motivo do card antigo', :aggregate_failures do
      automacao = ligada(receita(perdido_mais_recente))

      cliente_escreve(conversa, 'Quero uma cotação')

      expect(saidas(conversa)).to eq(['Da outra vez pesou: achou caro. Este ano consigo melhor.'])
      expect(saidas(conversa_antiga)).to be_empty
      filha = filhas(automacao).sole
      expect(filha).to have_attributes(alvo: card_perdido, estado: 'concluida')
      expect(inicio_da(filha)).to include('mae_id' => execucoes(automacao).first.id, 'conversa_id' => conversa.display_id, 'conversa_de' => 'mae')
    end

    it 'uma execução por registro, sem teto, e nunca duas para o mesmo registro', :aggregate_failures do
      outro_perdido = card_de(paulo, conversa_antiga, title: 'Seguro 2024', status: :lost, lost_reason: 'fechou com outro')
      card_de(paulo, conversa_antiga, title: 'Seguro ativo', status: :won)
      automacao = ligada(receita({ de: 'cards_do_contato', situacao: ['lost'] }))

      cliente_escreve(conversa, 'Quero uma cotação')
      mae = execucoes(automacao).first
      Autonomia::Automacao::EmOutroRegistroJob.perform_now(account.id + 1, mae.id, 'outro', paulo.id)
      Autonomia::Automacao::EmOutroRegistroJob.perform_now(account.id, mae.id, 'outro', paulo.id)
      drenar

      expect(filhas(automacao).map(&:alvo)).to contain_exactly(card_perdido, outro_perdido)
      pulados = Autonomia::Automacao::Registro.find_by!(execucao: mae, motivo: 'filhas_puladas')
      expect(pulados).to have_attributes(passo: 'outro', resultado: 'pulado', dados: { 'ja_aberta' => 2 })
      expect(saidas(conversa)).to contain_exactly('Da outra vez pesou: achou caro. Este ano consigo melhor.',
                                                  'Da outra vez pesou: fechou com outro. Este ano consigo melhor.')
    end

    it 'sem filtro, a mensagem que a filha manda não redispara a automação: a filha leva a cadeia da mãe', :aggregate_failures do
      automacao = ligada(receita(perdido_mais_recente, filtros: []))

      cliente_escreve(conversa, 'Quero uma cotação')

      expect(saidas(conversa).size).to eq(1)
      expect(execucoes(automacao).count).to eq(2)
      expect(filhas(automacao).sole.cadeia).to eq(["automacao:#{automacao['id']}"])
    end

    it 'quem ligou sem a chave de funis: o passo que lê cards pausa a automação e não abre filha', :aggregate_failures do
      automacao = ligada(receita(perdido_mais_recente))
      allow(Autonomia::Automacao::RegraDoFunil).to receive(:chave?).and_return(false)

      cliente_escreve(conversa, 'Quero uma cotação')

      expect(historico_de(automacao)).to eq([%w[outro falhou sem_chave_de_funis]])
      expect(Autonomia::Automacao::Definicao.find(automacao['id']).ativa).to be(false)
      expect(filhas(automacao)).to be_empty
      expect(saidas(conversa)).to be_empty
    end

    it 'a chave tirada depois de a filha abrir pausa a filha no card antes de agir', :aggregate_failures do
      automacao = ligada(receita(perdido_mais_recente))

      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: paulo, content: 'Oi')
      drenar_ate_abrir_filha
      allow(Autonomia::Automacao::RegraDoFunil).to receive(:chave?).and_return(false)
      drenar

      expect(historico_de(automacao).last).to eq(%w[inicio pulado sem_chave_de_funis])
      expect(filhas(automacao).sole.estado).to eq('parada')
      expect(saidas(conversa)).to be_empty
    end
  end

  # Roda os jobs até o que abre as filhas (inclusive), deixando a primeira rodada da filha na fila.
  def drenar_ate_abrir_filha
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| FechamentoAutomacao::JOBS.include?(item[:job]) }
      raise 'a filha não abriu' unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      return if job[:job] == Autonomia::Automacao::EmOutroRegistroJob
    end
  end
end
