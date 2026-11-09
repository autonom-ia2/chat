require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 5 dos termos de aceite: "Revisão do carro no tempo certo".
#
# > "Cliente que fez revisão aqui some. Quero lembrar ele da próxima revisão e já deixar marcado. Se ele enrolar,
# > oferece uma lavagem de graça." — Seu Zé, dono da oficina
#
# Começa quando: card do serviço marcado como ganho.
#   1. A IA extrai da conversa e da nota do mecânico o carro, a placa, a quilometragem e o que ficou para a próxima vez.
#   2. Grava tudo no contato e escreve uma nota: "Na próxima: trocar pastilhas".
#   3. Grava no card a data da próxima revisão: 6 meses depois.
#   4. 15 dias antes dessa data, a IA escreve o lembrete citando o que ficou para a próxima vez, e manda pelo modelo
#      aprovado com o link da agenda.
#   5. Marcou: move para "Revisão marcada" e põe a etiqueta "cliente fiel".
#   6. Não marcou em 5 dias: manda de novo pelo modelo aprovado, oferecendo a lavagem grátis.
#   7. Não marcou de novo em 5 dias: cria retorno para o Seu Zé ligar.
#   8. Revisão marcada e cancelada: manda o link da agenda de novo no dia seguinte.
# Resultado: o cliente volta sozinho a cada 6 meses, lembrado do que o mecânico anotou. O Seu Zé só liga para quem
# ignorou duas mensagens.
#
# Montado como o Seu Zé montaria, pela API da tela, em três automações: a do card ganho (passos 1 a 3, G5, G36, G19,
# G16), a da data da revisão (passos 4 a 7, G6, G28, G1, G12, G32, G3) e a da revisão cancelada (passo 8, G12). O
# cliente marca pela página de agendamento do Seu Zé, pelo serviço real (Crm::BookingV2::Booker): com o card do serviço
# já ganho, a página põe a reunião num card novo do contato, e a espera lê `contato.tem_reuniao_marcada` (#2710).
# Mensagem fora da janela de 24 h vai pelo modelo aprovado e para no receptor do WhatsApp oficial; a IA é o dublê.
# Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
#
# A etiqueta "cliente fiel" se escreve `cliente-fiel`: nome de etiqueta na plataforma não tem espaço.
RSpec.describe 'Fechamento #2414 · exemplo 5: revisão do carro no tempo certo', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:seu_ze) { create(:user, account: account, role: :administrator, name: 'Seu Zé') }
  let(:cliente) { create(:contact, account: account, name: 'Carla', phone_number: '+5511900000005') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: cliente, source_id: '5511900000005') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: cliente, contact_inbox: contact_inbox) }
  let(:funil_e_entrada) { create_crm_pipeline(account: account, user: seu_ze, name: 'Revisões') }
  let(:funil) { funil_e_entrada.first }
  let(:servico) { funil_e_entrada.last }
  let(:revisao_marcada) { create_crm_stage(account: account, pipeline: funil, name: 'Revisão marcada', position: 2) }
  # Na tela, o Seu Zé põe o WhatsApp da oficina como a caixa dos avisos da página.
  let(:agenda) do
    create_booking_profile(account: account, host: seu_ze, pipeline: funil, stage: servico, title: 'Revisão', notice_inbox: canal.inbox)
  end
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: servico, inbox: canal.inbox, contact: cliente, primary_conversation: conversa,
                              owner: seu_ze, title: 'Revisão do Gol', currency: 'BRL')
  end
  let(:roteiro) do
    { 'automacao_extrair' => { 'carro' => 'Gol 2015', 'placa' => 'ABC1D23', 'quilometragem' => 45_000,
                               'proxima_vez' => 'trocar pastilhas' },
      'automacao_escrever' => { 'texto' => 'Seu Gol está chegando na revisão: desta vez vamos trocar as pastilhas.' } }
  end

  def nome = { '$valor' => 'contato.nome' }
  def link_da_agenda = { '$valor' => 'card.link_da_agenda' }
  def modelo(nome_do_modelo, *variaveis) = { nome: nome_do_modelo, idioma: 'pt_BR', variaveis: [[nome], *variaveis] }

  def mensagem(id, nome_do_modelo, texto, *variaveis)
    { id: id, tipo: 'mensagem', texto: texto, modelo: modelo(nome_do_modelo, *variaveis) }
  end

  # Passos 1 a 3, no card ganho.
  def receita_do_servico
    { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: [
      { id: 'do_carro', tipo: 'extrair', le: %w[mensagens_recentes notas], campos: [
        { chave: 'carro', descricao: 'o carro (modelo e ano)', destino: 'contato.atributos.carro' },
        { chave: 'placa', descricao: 'a placa do carro', destino: 'contato.atributos.placa' },
        { chave: 'quilometragem', descricao: 'a quilometragem do carro', destino: 'contato.atributos.quilometragem' },
        { chave: 'proxima_vez', descricao: 'o que o mecânico deixou para a próxima revisão', destino: 'contato.atributos.proxima_vez' }
      ] },
      { id: 'nota', tipo: 'acao', acao: 'POST contacts/:contact_id/notes', descricao: 'Anotar no contato o que fica para a próxima',
        caminho: { contact_id: { '$valor' => 'contato.id' } },
        corpo: { content: { '$texto' => ['Na próxima: ', { '$valor' => 'contato.atributos.proxima_vez' }] } } },
      { id: 'proxima_revisao', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Gravar a data da próxima revisão',
        caminho: { id: { '$valor' => 'card.id' } }, corpo: { card: { custom_attributes: {
          proxima_revisao: { '$data' => { de: 'hoje', mais: { valor: 6, unidade: 'meses' } } }
        } } } }
    ] }
  end

  # Passos 4 a 7, 15 dias antes da próxima revisão.
  def receita_do_lembrete
    lembrete = { '$valor' => 'ia.lembrete' }
    { gatilho: { tipo: 'card.data', campo: 'proxima_revisao', dias: 15, quando: 'antes', hora: 9 }, passos: [
      { id: 'lembrete', tipo: 'escrever', le: %w[contato card], destino: 'guardar',
        instrucao: 'Escreva o lembrete da próxima revisão citando o que ficou para a próxima vez (campo proxima_vez do contato).' },
      mensagem('manda_lembrete', 'revisao_lembrete', [lembrete, ' Marque aqui: ', link_da_agenda], [lembrete], [link_da_agenda]),
      ate_marcar('marcou', [
                   mensagem('lavagem', 'revisao_lavagem', ['Marque sua revisão e ganhe uma lavagem grátis: ', link_da_agenda],
                            [link_da_agenda]),
                   ate_marcar('marcou_de_novo', [
                                { id: 'ligar', tipo: 'retorno', titulo: ['Ligar para ', nome, ' marcar a revisão'],
                                  daqui: { valor: 1, unidade: 'horas' } },
                                { id: 'fim', tipo: 'parar' }
                              ])
                 ]),
      { id: 'mover', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Revisão marcada',
        caminho: { id: { '$valor' => 'card.id' } }, corpo: { stage_id: revisao_marcada.id } },
      { id: 'fiel', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr a etiqueta cliente fiel',
        caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['cliente-fiel'] } }
    ] }
  end

  def ate_marcar(id, se_vencer)
    { id: id, tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'contato.tem_reuniao_marcada' }, op: 'igual', valor: true },
      prazo: { valor: 5, unidade: 'dias' }, se_vencer: se_vencer }
  end

  # Passo 8: a revisão marcada e cancelada.
  def receita_do_cancelamento
    { gatilho: { tipo: 'card.reuniao_cancelada', funil_id: funil.id }, passos: [
      { id: 'dia_seguinte', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
      mensagem('de_novo', 'revisao_agenda', ['Sua revisão foi cancelada. Marque de novo: ', link_da_agenda], [link_da_agenda])
    ] }
  end

  def atributo(chave, modelo_do_atributo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo_do_atributo, attribute_display_type: tipo)
  end

  def modelos_aprovados
    { 'revisao_lembrete' => 'Oi {{1}}, {{2}} Marque aqui: {{3}}',
      'revisao_lavagem' => 'Oi {{1}}, marque sua revisão e ganhe uma lavagem grátis: {{2}}',
      'revisao_agenda' => 'Oi {{1}}, sua revisão foi cancelada. Marque de novo: {{2}}' }.map do |nome_do_modelo, texto|
      { 'name' => nome_do_modelo, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => texto }] }
    end
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    create(:inbox_member, user: seu_ze, inbox: canal.inbox)
    { 'carro' => 'text', 'placa' => 'text', 'quilometragem' => 'number', 'proxima_vez' => 'text' }
      .each { |chave, tipo| atributo(chave, 'contact_attribute', tipo) }
    atributo('proxima_revisao', 'card_attribute', 'date')
    create(:label, account: account, title: 'cliente-fiel', description: 'Cliente que volta para a revisão')
    canal.update!(message_templates: modelos_aprovados)
    [revisao_marcada, agenda, card]
  end

  def ligar_tudo
    { servico: receita_do_servico, lembrete: receita_do_lembrete, cancelamento: receita_do_cancelamento }.each do |nome_da, receita|
      ligar_automacao(seu_ze, account, montar_automacao(seu_ze, account, nome: "Revisão: #{nome_da}", receita: receita))
    end
  end

  # Um job por vez, como no Sidekiq, com o do evento do card no meio.
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

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  def servico_ganho
    as('2026-11-10 17:00') do
      Crm::Cards::Closer.new(card: card, actor: seu_ze, result: 'won').perform
      drenar
    end
  end

  # A varredura acha os gatilhos de data e acorda as esperas vencidas; os jobs que ela abre rodam um por vez.
  def varredura_as(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  # A Carla marca pela página do link que recebeu, como qualquer cliente: nome, WhatsApp e horário.
  def carla_marca_as(hora, horario)
    as(hora) do
      Crm::BookingV2::Booker.new(profile: agenda, name: 'Carla', phone: '(11) 90000-0005', starts_at: fuso.parse(horario).iso8601,
                                 source: 'public_link').perform
      drenar
    end
  end

  def reuniao = account.crm_meetings.sole
  def link = Crm::BookingV2::ShortLink.url_for(agenda)
  def whatsapp = chamadas_para('graph.facebook.com')
  def modelos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def parametros(chamada) = chamada.corpo.dig('template', 'components', 0, 'parameters').pluck('text')
  def historico(nome_da) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome_da)).order(:id).pluck(:passo, :resultado, :motivo)
  def automacao_id(nome_da) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Revisão: #{nome_da}").id

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 10:00') do
      preparar_conta
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: cliente,
                       content: 'Bom dia! Deixo o Gol 2015 hoje, placa ABC1D23, está com 45 mil km.')
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :outgoing, private: true,
                       sender: seu_ze, content: 'Mecânico: pastilhas de freio no limite, trocar na próxima revisão.')
      ligar_tudo
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passos 1 a 3: card ganho; a IA lê a conversa e a nota, grava no contato, anota a próxima e marca a revisão no card',
     :aggregate_failures do
    servico_ganho

    lido = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_extrair' }.sole['input'].to_json
    expect(lido).to include('placa ABC1D23', 'pastilhas de freio no limite')
    expect(cliente.reload.custom_attributes).to include('carro' => 'Gol 2015', 'placa' => 'ABC1D23', 'quilometragem' => 45_000,
                                                        'proxima_vez' => 'trocar pastilhas')
    expect(cliente.notes.pluck(:content, :user_id)).to eq([['Na próxima: trocar pastilhas', seu_ze.id]])
    expect(card.reload.custom_attributes).to include('proxima_revisao' => '2027-05-10')
    expect(historico(:servico)).to eq([['do_carro', 'ok', nil], ['nota', 'ok', nil], ['proxima_revisao', 'ok', nil]])
  end

  context 'with 15 dias antes da revisão (passos 4 a 8)' do
    before do
      servico_ganho
      varredura_as('2027-04-25 09:30')
    end

    it 'passo 4: a IA escreve o lembrete com o que ficou para a próxima e ele sai pelo modelo aprovado, com o link da agenda',
       :aggregate_failures do
      lido = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_escrever' }.sole['input'].to_json
      expect(lido).to include('trocar pastilhas')
      expect(modelos_enviados).to eq(%w[revisao_lembrete])
      expect(parametros(whatsapp.sole))
        .to eq(['Carla', 'Seu Gol está chegando na revisão: desta vez vamos trocar as pastilhas.', link])
    end

    it 'passo 5: marcou pela página; o card do serviço vai para "Revisão marcada" e a Carla ganha a etiqueta', :aggregate_failures do
      carla_marca_as('2027-04-26 11:00', '2027-04-28 10:00')

      expect(reuniao.card).not_to eq(card)
      expect(card.reload.stage_id).to eq(revisao_marcada.id)
      expect(cliente.reload.label_list).to include('cliente-fiel')
      expect(modelos_enviados).to eq(%w[revisao_lembrete])
      expect(Crm::FollowUp.where(card_id: card.id)).to be_empty
    end

    it 'passos 6 e 7: não marcou em 5 dias, a lavagem grátis; não marcou de novo, o retorno para o Seu Zé ligar',
       :aggregate_failures do
      varredura_as('2027-04-30 09:31')
      expect(modelos_enviados).to eq(%w[revisao_lembrete revisao_lavagem])
      expect(parametros(whatsapp.last)).to eq(['Carla', link])

      varredura_as('2027-05-05 09:32')
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, assignee_id: seu_ze.id, title: 'Ligar para Carla marcar a revisão')
      expect(card.reload.stage_id).to eq(servico.id)
      expect(cliente.reload.label_list).not_to include('cliente-fiel')
      expect(modelos_enviados).to eq(%w[revisao_lembrete revisao_lavagem])
    end

    # G47: a reunião está no card que a página criou, e ele nasce com a conversa da Carla no WhatsApp dos avisos da
    # página. A última mensagem dela é de meses atrás: com a janela de 24 h fechada, sai o modelo aprovado com o link.
    it 'passo 8: marcou e cancelou; no dia seguinte o link da agenda vai de novo pelo modelo aprovado', :aggregate_failures do
      carla_marca_as('2027-04-26 11:00', '2027-04-28 10:00')
      as('2027-04-27 08:00') do
        Crm::Meetings::CancelService.new(meeting: reuniao).perform
        drenar
      end

      varredura_as('2027-04-28 08:05')

      expect(reuniao.card).to have_attributes(conversation_id: conversa.id)
      expect(reuniao.card).not_to eq(card)
      expect(modelos_enviados).to eq(%w[revisao_lembrete revisao_agenda])
      expect(parametros(whatsapp.last)).to eq(['Carla', link])
      expect(historico(:cancelamento)).to eq([['dia_seguinte', 'ok', nil], ['de_novo', 'ok', nil]])
      expect(Autonomia::Automacao::Registro.find_by!(automacao_id: automacao_id(:cancelamento), passo: 'de_novo').dados)
        .to include('modelo' => 'revisao_agenda')
    end
  end
end
