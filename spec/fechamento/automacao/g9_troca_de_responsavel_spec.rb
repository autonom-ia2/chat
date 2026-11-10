require 'rails_helper'

# Fechamento do épico #2414, G9 (#2707): o gatilho "quando muda quem cuida do card", com quem cuidava antes. É o começo
# ("o responsável do card muda e a responsável anterior está marcada como ausente") e os passos 1 a 3 do exemplo 17 dos
# termos de aceite, "Vendedora de férias, cliente bem cuidado", à risca, numa automação só:
#
# > "Quando alguém sai de férias eu passo os clientes para outra pessoa, mas o cliente fica perdido e a colega não sabe
# > o que foi combinado." — Paula, gerente comercial
#
# Montado como a Paula montaria, pela API da tela, e disparado como ela dispara: com a Júlia marcada "ausente até" (G23),
# troca todos os cards dela para a Renata de uma vez, pela Lista do CRM (o lote). A IA é o dublê; o WhatsApp oficial
# para no receptor de teste. O passo 3 grava a Júlia num campo do card do tipo pessoa da equipe (G62, #2829), e os
# passos 5 e 6, "toda manhã", leem se ela voltou e devolvem o card a ela: o termo dá a eles outro começo ("toda manhã"),
# então rodam na automação da manhã. O passo 4 ("a cada mensagem do cliente") espera a G63 (#2830): fica no
# pendentes_spec.
RSpec.describe 'Fechamento #2414 · G9: troca de responsável do card (exemplo 17, passos 1 a 3)', :fechamento_automacao,
               type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:paula) { create(:user, account: account, role: :administrator, name: 'Paula Gerente') }
  let(:julia) { create(:user, account: account, role: :agent, name: 'Júlia') }
  let(:renata) { create(:user, account: account, role: :agent, name: 'Renata') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: paula, name: 'Vendas') }

  let(:maria) { create(:contact, account: account, name: 'Maria', phone_number: '+5511900000017') }
  let(:conversa_da_maria) { conversa_de(maria, '5511900000017') }
  let(:card_da_maria) { card_de(maria, conversa_da_maria, 'Proposta da Maria') }

  let(:receita) do
    { gatilho: { tipo: 'card.responsavel_mudou', funil_id: funil_e_etapa.first.id,
                 filtros: [{ campo: valor('gatilho.responsavel_anterior_ausente'), op: 'igual', valor: true }] },
      passos: passos_do_termo }
  end
  let(:automacao) { montar_automacao(paula, account, nome: 'Cobertura de férias', receita: receita) }

  def valor(caminho) = { '$valor' => caminho }

  # Os passos 1 a 3 do termo, na ordem e com o texto dele.
  def passos_do_termo
    [
      { id: 'resumo', tipo: 'resumir', le: %w[conversa], linhas: 4, destino: { avisar: { responsavel_do_card: true } } },
      { id: 'aviso_ao_cliente', tipo: 'mensagem',
        texto: ['Oi, ', valor('contato.nome'), '! A ', valor('gatilho.responsavel_anterior_nome'), ' está de férias e a ',
                valor('card.responsavel_nome'), ' vai cuidar de você até ela voltar. Ela já está a par de tudo'] },
      { id: 'original', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Gravar no card quem é a responsável original',
        caminho: { id: valor('card.id') },
        corpo: { card: { custom_attributes: { responsavel_original: valor('gatilho.responsavel_anterior_id') } } } },
      { id: 'etiqueta', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
        descricao: 'Pôr a etiqueta cobertura de férias', caminho: { conversation_id: valor('conversa.id') },
        corpo: { por: ['cobertura-de-ferias'] } }
    ]
  end

  def conversa_de(contato, numero)
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: contato, source_id: numero)
    create(:conversation, account: account, inbox: inbox, contact: contato, contact_inbox: contact_inbox, assignee: julia,
                          status: :open)
  end

  def card_de(contato, conversa, titulo, pipeline: funil_e_etapa)
    account.crm_cards.create!(pipeline: pipeline.first, stage: pipeline.last, title: titulo, currency: 'BRL', contact: contato,
                              primary_conversation: conversa, owner: julia)
  end

  # A janela de 24 h aberta: a última mensagem do cliente é de hoje. Gravada antes de ligar, para não ser gatilho.
  def cliente_escreveu(conversa, texto)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: conversa.contact,
                     content: texto)
  end

  # A Paula troca os cards na Lista do CRM: o mesmo POST que a tela faz no lote.
  def paula_passa_para(pessoa, cards)
    post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
         params: { ids: cards.map(&:id), action_name: 'assign', payload: { owner_id: pessoa&.id } },
         headers: paula.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), -> { "a troca em lote falhou: #{response.body}" }
    rodar_jobs_do_card
  end

  # O gatilho do card vem pelo EventoDoCardJob (TrocaNoCard); depois, o motor e o envio, um job por vez.
  def rodar_jobs_do_card
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EventoDoCardJob }
      break unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
      rodar_jobs
    end
  end

  def execucoes = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id'])

  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!(Autonomia::Automacao::Motor::FLAG_GATILHOS)
    [julia, renata].each { |agente| create(:inbox_member, user: agente, inbox: inbox) }
    create(:label, account: account, title: 'cobertura-de-ferias', description: 'Cliente em cobertura de férias')
    create(:custom_attribute_definition, account: account, attribute_model: :card_attribute, attribute_key: 'responsavel_original',
                                         attribute_display_name: 'Responsável original', attribute_display_type: :pessoa)
    AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: 15.days.from_now)
    receptor_whatsapp_cloud
    cliente_escreveu(conversa_da_maria, 'Pode me mandar a proposta revisada até sexta?')
    card_da_maria
    ia_responde(account, 'automacao_resumir' => {
                  'resumo' => 'Maria quer a proposta revisada até sexta. Foi prometido 10% de desconto. Próximo passo: enviar a proposta.'
                })
    ligar_automacao(paula, account, automacao)
    clear_enqueued_jobs
  end

  after { Current.reset }

  context 'when a Paula passa os cards da Júlia para a Renata pela Lista do CRM' do
    let(:joao) { create(:contact, account: account, name: 'João', phone_number: '+5511900000018') }
    let(:card_do_joao) { card_de(joao, conversa_de(joao, '5511900000018'), 'Renovação do João') }

    before do
      cliente_escreveu(card_do_joao.primary_conversation, 'Quando renova?')
      clear_enqueued_jobs
      paula_passa_para(renata, [card_da_maria, card_do_joao])
    end

    it 'cada card trocado começa uma execução, uma vez só' do
      expect(execucoes.pluck(:alvo_id)).to contain_exactly(card_da_maria.id, card_do_joao.id)
    end

    it 'a Renata, nova dona do card, recebe no sino o resumo; a Júlia, que ainda atende a conversa, não', :aggregate_failures do
      expect(conversa_da_maria.reload.assignee).to eq(julia)
      nota = conversa_da_maria.messages.where(private: true).find_by('content LIKE ?', '%mention://user/%')
      expect(nota.content).to include('proposta revisada', "mention://user/#{renata.id}/")
      expect(nota.content).not_to include("mention://user/#{julia.id}/")
      expect(mencoes_para(renata).count).to eq(2)
      expect(mencoes_para(julia).count).to eq(0)
    end

    it 'o cliente recebe pelo WhatsApp oficial quem cuidava e quem vai cuidar dele' do
      saida = chamadas_para('graph.facebook.com').find { |chamada| chamada.corpo['to'] == '5511900000017' }
      expect(saida).to be_present, 'nada saiu para o WhatsApp da Maria'
      expect(saida.corpo.dig('text', 'body'))
        .to eq('Oi, Maria! A Júlia está de férias e a Renata vai cuidar de você até ela voltar. Ela já está a par de tudo')
    end

    it 'o card guarda quem é a responsável original e a conversa ganha a etiqueta cobertura de férias', :aggregate_failures do
      expect(card_da_maria.reload.owner).to eq(renata)
      expect(card_da_maria.custom_attributes['responsavel_original']).to eq(julia.id)
      expect(conversa_da_maria.reload.label_list).to include('cobertura-de-ferias')
    end

    it 'o histórico mostra cada passo feito' do
      execucao = execucoes.find_by!(alvo_id: card_da_maria.id)
      passos = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado)
      expect(passos).to eq([%w[resumo ok], %w[aviso_ao_cliente ok], %w[original ok], %w[etiqueta ok]])
    end
  end

  # D5: a nova dona que não está na caixa não enxerga a conversa; o resumo não vaza para ela.
  it 'a nova dona fora da caixa não recebe o resumo, e o registro diz por quê', :aggregate_failures do
    bia = create(:user, account: account, role: :agent, name: 'Bia')
    paula_passa_para(bia, [card_da_maria])

    registro = Autonomia::Automacao::Registro.find_by!(execucao: execucoes.sole, passo: 'resumo')
    expect([registro.resultado, registro.motivo]).to eq(%w[pulado ninguem_para_avisar])
    expect(mencoes_para(bia).count).to eq(0)
  end

  it 'card de outro funil não começa nada' do
    outro_funil = create_crm_pipeline(account: account, user: paula, name: 'Pós-venda')
    card = card_de(maria, conversa_da_maria, 'Pós-venda da Maria', pipeline: outro_funil)
    clear_enqueued_jobs
    paula_passa_para(renata, [card])

    expect(execucoes).to be_empty
  end

  it 'mudar outra coisa do card, sem trocar quem cuida, não começa nada' do
    card_da_maria.update!(title: 'Proposta revisada da Maria')
    rodar_jobs_do_card

    expect(execucoes).to be_empty
  end

  # Passos 5 e 6: "Toda manhã, para cada card com a etiqueta 'cobertura de férias': se a responsável original já está
  # disponível de novo, devolve o card a ela e tira a etiqueta" e "A IA resume para a Júlia o que aconteceu".
  context 'when a Júlia volta das férias' do
    let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
    let(:receita_da_manha) do
      { gatilho: { tipo: 'card.recorrente', frequencia: 'diaria', hora: 8, selecao: { situacao: 'aberto' },
                   filtros: [{ campo: valor('conversa.etiquetas'), op: 'contem', valor: 'cobertura-de-ferias' }] },
        passos: [{ id: 'voltou', tipo: 'se', condicao: { campo: valor('card.atributos.responsavel_original.ausente'), op: 'igual', valor: false },
                   entao: passos_da_volta }] }
    end

    def passos_da_volta
      [{ id: 'devolve', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Devolver o card à responsável original',
         caminho: { id: valor('card.id') }, corpo: { card: { owner_id: valor('card.atributos.responsavel_original') } } },
       { id: 'tira', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
         descricao: 'Tirar a etiqueta cobertura de férias', caminho: { conversation_id: valor('conversa.id') },
         corpo: { tirar: ['cobertura-de-ferias'] } },
       { id: 'conta', tipo: 'resumir', le: %w[conversa], linhas: 4, destino: { avisar: { responsavel_do_card: true } } }]
    end

    def varrer_em(momento)
      travel_to(momento) do
        Autonomia::Automacao::TempoJob.perform_now
        perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
        perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
        rodar_jobs
        rodar_jobs_do_card
      end
    end

    def execucoes_da_manha
      da_manha = Autonomia::Automacao::Definicao.find_by!(account_id: account.id, nome: 'Volta das férias')
      Autonomia::Automacao::Execucao.where(automacao_id: da_manha.id)
    end

    before do
      account.update!(reporting_timezone: fuso.name)
      travel_to(fuso.local(2026, 11, 2, 10)) { paula_passa_para(renata, [card_da_maria]) }
      travel_to(fuso.local(2026, 11, 2, 11)) do
        ligar_automacao(paula, account, montar_automacao(paula, account, nome: 'Volta das férias', receita: receita_da_manha))
      end
      AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: fuso.local(2026, 11, 10, 18))
    end

    it 'com a Júlia ainda de férias, a manhã não mexe no card', :aggregate_failures do
      varrer_em(fuso.local(2026, 11, 5, 8, 5))

      expect(card_da_maria.reload.owner).to eq(renata)
      expect(conversa_da_maria.reload.label_list).to include('cobertura-de-ferias')
      registro = Autonomia::Automacao::Registro.find_by!(execucao: execucoes_da_manha.sole, passo: 'voltou')
      expect(registro.dados['ramo']).to eq('senao')
    end

    it 'na manhã depois da volta, o card é dela de novo, sem a etiqueta, e ela recebe o resumo', :aggregate_failures do
      varrer_em(fuso.local(2026, 11, 11, 8, 5))

      expect(card_da_maria.reload.owner).to eq(julia)
      expect(conversa_da_maria.reload.label_list).not_to include('cobertura-de-ferias')
      expect(mencoes_para(julia).count).to eq(1)
      # A volta é outra troca, com a Renata (presente) como anterior: a cobertura não recomeça.
      expect(execucoes.count).to eq(1)
    end
  end

  # "A responsável anterior está marcada como ausente": trocar o card de quem está trabalhando não começa nada.
  it 'card de uma dona presente não começa nada' do
    AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: nil)
    paula_passa_para(renata, [card_da_maria])

    expect(execucoes).to be_empty
  end

  # A volta da Júlia é outra troca, com a Renata (presente) como anterior: para no filtro, sem laço.
  it 'devolver o card à Júlia não começa outra cobertura', :aggregate_failures do
    paula_passa_para(renata, [card_da_maria])
    paula_passa_para(julia, [card_da_maria])

    expect(execucoes.count).to eq(1)
    expect(Autonomia::Automacao::TrocaNoCard.anterior_da_marca(execucoes.sole.evento, 'card.responsavel_mudou')).to eq(julia.id)
  end

  it 'card que fica sem ninguém também é troca; o nome de quem cuida vem vazio e a mensagem não sai', :aggregate_failures do
    paula_passa_para(nil, [card_da_maria])

    execucao = execucoes.sole
    passos = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
    expect(passos.first).to eq(%w[resumo pulado ninguem_para_avisar])
    expect(passos.second).to eq(%w[aviso_ao_cliente pulado faltou_valor])
    expect(chamadas_para('graph.facebook.com')).to be_empty
  end
end
