require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G18 (#2671): agir em outro registro ligado ao alvo. Provado nos pedaços dos
# exemplos que dependem dela, montados e ligados pela API da tela, com o gatilho chegando pelo despacho da plataforma e a
# mensagem parando no receptor do WhatsApp oficial:
# - exemplo 11, passo 7: "Card do João ganho: manda à Maria 'O João virou cliente! O próximo banho do Thor é por nossa
#   conta', com o link da agenda", e "põe na Maria a etiqueta" (passo 8). Os nomes vêm de valores: o do João, do
#   registro de origem (o card ganho), que a filha lê com `origem.contato.nome` (G65, #2842); o do Thor, do contato da
#   Maria, que é a dona dele;
# - exemplo 16, passo 4: "a IA escreve uma resposta que fala do motivo da perda gravado no card antigo", na conversa em
#   que o cliente escreveu.
# - exemplo 11, passo 3: "com 'indicado por Maria' gravado no card", num campo do card do tipo Contato (decisão 16):
#   o card só guarda contato da conta, e o "em outro registro" só aceita esse tipo de campo.
# Os dois exemplos inteiros ficam no pendentes_spec até as outras lacunas deles fecharem.
RSpec.describe 'Fechamento #2414 · G18: agir em outro registro', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run } }

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
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
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
    let(:pagina_da_lu) { create_booking_profile(account: account, host: dona) }
    let(:indicado_por) { { '$valor' => 'card.atributos.indicado_por' } }

    # A filha, na conversa da Maria, manda o presente com o nome do João (lido no card ganho, o registro de origem), o do
    # pet dela e o link da agenda de quem a atende, e põe a etiqueta nela.
    let(:receita) do
      { gatilho: { tipo: 'card.ganho', funil_id: funil.id },
        passos: [em_outro({ de: 'contato_do_campo', campo: indicado_por, usar: 'conversa' },
                          mensagem('presente', 'O ', { '$valor' => 'origem.contato.nome' },
                                   ' virou cliente! O próximo banho do ', { '$valor' => 'contato.atributos.nome_do_pet' },
                                   ' é por nossa conta: ', { '$valor' => 'conversa.link_da_agenda' }),
                          { id: 'etiqueta', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Indicou e fechou',
                            caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['indicou_e_fechou'] } })] }
    end

    # Só o "em outro registro", para ver o que a mãe registra quando a ligação não acha onde rodar.
    let(:so_o_presente) do
      { gatilho: { tipo: 'card.ganho', funil_id: funil.id },
        passos: [em_outro({ de: 'contato_do_campo', campo: indicado_por, usar: 'conversa' }, mensagem('presente', 'Parabéns!'))] }
    end

    before do
      create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_display_name: 'Indicado por',
                                           attribute_model: :card_attribute, attribute_display_type: :contato)
      create(:custom_attribute_definition, account: account, attribute_key: 'nome_do_pet', attribute_display_name: 'Nome do pet',
                                           attribute_model: :contact_attribute, attribute_display_type: :text)
      maria.update!(custom_attributes: { 'nome_do_pet' => 'Thor' })
      conversa_da_maria.update!(assignee: dona)
      pagina_da_lu
      create(:label, account: account, title: 'indicou_e_fechou', description: 'Indicou e o amigo fechou')
      create(:message, conversation: conversa_da_maria, account: account, inbox: inbox, message_type: :incoming, sender: maria,
                       content: 'Indiquei o João!')
    end

    it 'passo 7: manda à Maria "O João virou cliente! O próximo banho do Thor é por nossa conta", com o link da agenda, e põe a etiqueta nela',
       :aggregate_failures do
      automacao = ligada(receita)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      link = Crm::BookingV2::ShortLink.url_for(pagina_da_lu)
      expect(saidas(conversa_da_maria)).to eq(["O João virou cliente! O próximo banho do Thor é por nossa conta: #{link}"])
      expect(chamadas_para('graph.facebook.com').map { |chamada| chamada.corpo['to'] }).to eq(['5511900000011'])
      expect(maria.reload.label_list).to eq(['indicou_e_fechou'])
      expect(saidas(conversa_do_joao)).to be_empty
      expect(joao.reload.label_list).to be_empty

      filha = filhas(automacao).sole
      expect(filha).to have_attributes(alvo: conversa_da_maria, estado: 'concluida', cadeia: execucoes(automacao).first.cadeia)
      expect(inicio_da(filha)).to include('conversa_id' => conversa_da_maria.display_id, 'conversa_de' => 'registro')
      expect(historico_de(automacao)).to eq([['outro', 'ok', nil], %w[inicio ok em_outro_registro], ['presente', 'ok', nil],
                                             ['etiqueta', 'ok', nil]])
    end

    it 'o card sem quem indicou não abre filha: o passo pula com o motivo', :aggregate_failures do
      card_do_joao.update!(custom_attributes: {})
      automacao = ligada(receita)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      expect(historico_de(automacao)).to eq([%w[outro pulado faltou_valor]])
      expect(filhas(automacao)).to be_empty
    end

    it 'quem indicou foi apagado: nenhuma filha, e a mãe diz por quê', :aggregate_failures do
      apagada = contato('Bia', '11900000014')
      card_do_joao.update!(custom_attributes: { 'indicado_por' => apagada.id })
      apagada.destroy!
      automacao = ligada(so_o_presente)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      expect(historico_de(automacao)).to eq([['outro', 'ok', nil], %w[outro pulado contato_ligado_sumiu]])
      expect(filhas(automacao)).to be_empty
      expect(chamadas_para('graph.facebook.com')).to be_empty
    end

    it 'quem indicou não tem conversa: nenhuma filha, e a mãe diz por quê', :aggregate_failures do
      sem_conversa = contato('Bia', '11900000013')
      card_do_joao.update!(custom_attributes: { 'indicado_por' => sem_conversa.id })
      automacao = ligada(so_o_presente)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      expect(historico_de(automacao)).to eq([['outro', 'ok', nil], %w[outro pulado contato_ligado_sem_conversa]])
      expect(filhas(automacao)).to be_empty
      expect(chamadas_para('graph.facebook.com')).to be_empty
    end

    # Decisão 16: o "indicado por Maria" é um campo do card do tipo Contato, gravado pela tela (a API do card). A equipe
    # escolhe a Maria numa lista; o card guarda o id dela e recusa contato de outra conta, para um engano nunca mandar a
    # mensagem do passo 7 a outro cliente.
    it 'passo 3: "indicado por Maria" fica gravado no card do João num campo do tipo Contato, só com contato da conta',
       :aggregate_failures do
      card_do_joao.update!(custom_attributes: {})
      de_outra_conta = create(:contact, account: create(:account), name: 'Maria de fora')
      url = "/api/v1/accounts/#{account.id}/crm/cards/#{card_do_joao.id}"

      patch url, params: { card: { custom_attributes: { indicado_por: maria.id.to_s } } }, headers: dona.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(card_do_joao.reload.custom_attributes).to eq('indicado_por' => maria.id)

      patch url, params: { card: { custom_attributes: { indicado_por: de_outra_conta.id } } }, headers: dona.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card_do_joao.reload.custom_attributes).to eq('indicado_por' => maria.id)
    end

    # Quem ligou perdeu o funil do João (o card ganho) entre a mãe e a filha: a filha não manda os dados dele à Maria. O
    # passo que lê a origem pula com o motivo próprio; o que não lê (a etiqueta) segue.
    it 'quem ligou perdeu o acesso ao card do João depois de a filha abrir: o presente não sai, com o motivo', :aggregate_failures do
      automacao = ligada(receita)
      perde_o_card_quando_a_filha_abre(card_do_joao)

      Crm::Cards::Closer.new(card: card_do_joao, actor: dona, result: 'won').perform
      drenar

      expect(saidas(conversa_da_maria)).to be_empty
      expect(chamadas_para('graph.facebook.com')).to be_empty
      expect(historico_de(automacao)).to eq([['outro', 'ok', nil], %w[inicio ok em_outro_registro], %w[presente pulado origem_fora_do_alcance],
                                             ['etiqueta', 'ok', nil]])
      expect(maria.reload.label_list).to eq(['indicou_e_fechou'])
    end
  end

  describe 'exemplo 16: a resposta lê o card perdido do mesmo contato' do
    let(:paulo) { contato('Paulo', '11900000016') }
    let(:perdido_mais_recente) { { de: 'cards_do_contato', situacao: ['lost'], mais_recente: true } }
    let!(:conversa_antiga) { conversa_de(paulo) }
    let!(:conversa) { conversa_de(paulo) }
    let!(:card_perdido) { card_de(paulo, conversa_antiga, title: 'Seguro 2025', status: :lost, lost_reason: 'achou caro') }

    let(:resposta) { mensagem('resposta', 'Da outra vez pesou: ', { '$valor' => 'card.motivo_da_perda' }, '. Este ano consigo melhor.') }
    let(:texto_da_ia) { 'Paulo, da outra vez o preço pesou; este ano consigo melhor. Posso cotar?' }
    # Passo 4 à risca: a IA escreve a resposta, lendo o card antigo (com o motivo da perda) e a conversa.
    let(:escrita_pela_ia) do
      { id: 'resposta', tipo: 'escrever', le: %w[mensagens_recentes card], destino: 'mensagem',
        instrucao: 'Responda falando do motivo da perda gravado no card antigo e diga que este ano consegue melhor.' }
    end
    let(:recebida) { [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }] }

    def receita(registro, filtros: recebida, passo: resposta)
      { gatilho: { tipo: 'mensagem.criada', filtros: filtros }, passos: [em_outro(registro, passo)] }
    end

    it 'passo 4: a IA escreve a resposta com o motivo da perda do card antigo, na conversa em que o cliente escreveu', :aggregate_failures do
      ia_responde(account, 'automacao_escrever' => { 'texto' => texto_da_ia })
      automacao = ligada(receita(perdido_mais_recente, passo: escrita_pela_ia))

      cliente_escreve(conversa, 'Quero uma cotação')

      expect(ia_recebeu.size).to eq(1)
      # Sem anexos, o PassoDeIa manda a entrada como texto JSON (entrada_com), e o cliente da IA a embrulha numa mensagem
      # do usuário com uma parte de texto (ResponsesClient#normalize_input): é o que chega à OpenAI.
      parte = ia_recebeu.sole['input'].sole.fetch('content').sole
      expect(parte['type']).to eq('input_text')
      lido = JSON.parse(parte['text'])
      expect(lido.dig('conversa', 'card')).to include('title' => 'Seguro 2025', 'status' => 'lost', 'lost_reason' => 'achou caro')
      expect(ia_recebeu.sole['instructions']).to include('motivo da perda gravado no card antigo')
      expect(saidas(conversa)).to eq([texto_da_ia])
      expect(saidas(conversa_antiga)).to be_empty
      filha = filhas(automacao).sole
      expect(filha).to have_attributes(alvo: card_perdido, estado: 'concluida')
      expect(inicio_da(filha)).to include('mae_id' => execucoes(automacao).first.id, 'conversa_id' => conversa.display_id, 'conversa_de' => 'mae')
    end

    it 'o contato sem card perdido: nenhuma filha, e a mãe diz por quê', :aggregate_failures do
      card_perdido.update!(status: :won)
      automacao = ligada(receita(perdido_mais_recente))

      cliente_escreve(conversa, 'Quero uma cotação')

      expect(historico_de(automacao)).to eq([['outro', 'ok', nil], %w[outro pulado nenhum_card_ligado]])
      expect(filhas(automacao)).to be_empty
      expect(saidas(conversa)).to be_empty
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
      expect(Autonomia::Automacao::Registro.where(execucao: mae, motivo: 'filhas_puladas')).to be_empty
      expect(saidas(conversa)).to contain_exactly('Da outra vez pesou: achou caro. Este ano consigo melhor.',
                                                  'Da outra vez pesou: fechou com outro. Este ano consigo melhor.')
    end

    it 'o job que cai no meio repete e abre o que faltou, sem duplicar nem contar como pulado', :aggregate_failures do
      outro_perdido = card_de(paulo, conversa_antiga, title: 'Seguro 2024', status: :lost, lost_reason: 'fechou com outro')
      automacao = ligada(receita({ de: 'cards_do_contato', situacao: ['lost'] }))
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: paulo, content: 'Oi')
      drenar_ate_enfileirar_filhas
      job = enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EmOutroRegistroJob }
      argumentos = ActiveJob::Arguments.deserialize(job[:args])
      chamadas = 0
      allow(Autonomia::Automacao::AvancarJob).to receive(:perform_later).and_wrap_original do |original, *args|
        chamadas += 1
        raise ActiveRecord::Deadlocked if chamadas == 2

        original.call(*args)
      end

      expect { Autonomia::Automacao::EmOutroRegistroJob.perform_now(*argumentos) }.to raise_error(ActiveRecord::Deadlocked)
      Autonomia::Automacao::EmOutroRegistroJob.perform_now(*argumentos)
      enqueued_jobs.delete(job)
      drenar

      expect(filhas(automacao).map(&:alvo)).to contain_exactly(card_perdido, outro_perdido)
      expect(saidas(conversa)).to contain_exactly('Da outra vez pesou: achou caro. Este ano consigo melhor.',
                                                  'Da outra vez pesou: fechou com outro. Este ano consigo melhor.')
      expect(Autonomia::Automacao::Registro.where(execucao: execucoes(automacao).first, motivo: 'filhas_puladas')).to be_empty
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

    it 'quem ligou não vê a conversa da mãe: a filha não abre, e a mãe diz quantos ficaram de fora', :aggregate_failures do
      automacao = ligada(receita(perdido_mais_recente))

      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: paulo, content: 'Oi')
      drenar_ate_enfileirar_filhas
      sem_ver(conversa)
      drenar

      expect(filhas(automacao)).to be_empty
      pulados = Autonomia::Automacao::Registro.find_by!(execucao: execucoes(automacao).first, motivo: 'filhas_puladas')
      expect(pulados.dados).to eq('fora_do_alcance' => 1)
      expect(saidas(conversa)).to be_empty
    end

    it 'vê o card e a principal, mas perdeu a conversa da mãe depois de a filha abrir: a filha pausa sem agir', :aggregate_failures do
      automacao = ligada(receita(perdido_mais_recente))

      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: paulo, content: 'Oi')
      drenar_ate_abrir_filha
      sem_ver(conversa)
      drenar

      expect(historico_de(automacao).last).to eq(%w[inicio pulado quem_ligou_sem_acesso])
      expect(filhas(automacao).sole.estado).to eq('parada')
      expect(saidas(conversa)).to be_empty
      expect(saidas(conversa_antiga)).to be_empty
    end
  end

  # Quem ligou deixa de ver o card (o funil dele) assim que a primeira filha existe: a mãe já rodou e abriu a filha.
  def perde_o_card_quando_a_filha_abre(card)
    allow(Crm::CardPolicy).to receive(:new).and_wrap_original do |original, contexto, registro|
      politica = original.call(contexto, registro)
      allow(politica).to(receive(:show?).and_wrap_original { |show| !filha_aberta? && show.call }) if registro == card
      politica
    end
  end

  def filha_aberta? = Autonomia::Automacao::Execucao.exists?(['evento LIKE ?', 'em:%'])

  # Quem ligou deixa de ver só esta conversa; o card e a conversa principal dele continuam à vista.
  def sem_ver(escondida)
    allow(ConversationPolicy).to receive(:new).and_wrap_original do |original, contexto, conversa|
      politica = original.call(contexto, conversa)
      allow(politica).to receive(:show?).and_return(false) if conversa == escondida
      politica
    end
  end

  # Roda os jobs até o passo da mãe enfileirar o que abre as filhas, sem rodar esse.
  def drenar_ate_enfileirar_filhas
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      return if enqueued_jobs.any? { |item| item[:job] == Autonomia::Automacao::EmOutroRegistroJob }

      job = enqueued_jobs.find { |item| FechamentoAutomacao::JOBS.include?(item[:job]) }
      raise 'o passo não enfileirou as filhas' unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
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
