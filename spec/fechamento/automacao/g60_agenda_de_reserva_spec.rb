require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G60, decisão 10 do Rodrigo: a página de agenda de reserva do link da agenda
# (`gatilho.agenda_de_reserva.pagina_id`). O que vale ao rodar (quem atende, a reserva, sem reserva, reserva apagada)
# está no spec do exemplo 6 (g59_reuniao_atendida_na_espera_spec); aqui, o que o salvar recusa: página de outra conta,
# gatilho sem alvo que tenha conversa, e quem salva sem ler as páginas de agendamento.
RSpec.describe 'Fechamento #2414 · G60: página de agenda de reserva', :fechamento_automacao, type: :request do
  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:jessica) { create(:user, account: account, role: :administrator, name: 'Jéssica') }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [jessica]) }
  let(:salao) { create_booking_profile(account: account, host: jessica, title: 'Agenda do salão') }
  let(:outra_conta) { create(:account) }
  let(:de_fora) { create_booking_profile(account: outra_conta, host: create(:user, account: outra_conta), title: 'Outra conta') }

  def receita(pagina_id, tipo: 'contato.data')
    gatilho = { tipo: tipo, campo: 'nascimento', dias: 0, quando: 'antes', hora: 9, repete: 'todo_ano',
                conversa_nova: { caixa_id: inbox.id }, agenda_de_reserva: { pagina_id: pagina_id } }
    { gatilho: gatilho, passos: [{ id: 'nota', tipo: 'avisar', para: { pessoas: [jessica.id] }, texto: ['Oi'] }] }
  end

  def salvar(receita)
    post api_automacoes(account), params: { nome: 'Aniversário', receita: receita }, headers: jessica.create_new_auth_token, as: :json
  end

  def problemas(gatilho, account_user)
    Autonomia::Automacao::AgendaDeReserva.problemas_ao_salvar(account, gatilho.deep_stringify_keys, account_user)
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    create(:custom_attribute_definition, account: account, attribute_key: 'nascimento', attribute_display_name: 'nascimento',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'date')
  end

  after { Current.reset }

  it 'aceita a página da conta e guarda a escolha no gatilho' do
    salvar(receita(salao.id))

    expect(response).to have_http_status(:created), -> { response.body }
    expect(response.parsed_body.dig('versao', 'receita', 'gatilho', 'agenda_de_reserva', 'pagina_id')).to eq(salao.id)
  end

  it 'recusa a página de outra conta' do
    salvar(receita(de_fora.id))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include(I18n.t('autonomia.automacao.receita.agenda_de_reserva_de_fora', id: de_fora.id, locale: :pt_BR))
  end

  it 'recusa a reserva no gatilho que não tem conversa, card nem contato' do
    gatilho = { tipo: 'conta.recorrente', agenda_de_reserva: { pagina_id: salao.id } }

    expect(problemas(gatilho, nil)).to eq([I18n.t('autonomia.automacao.receita.agenda_de_reserva_sem_alvo')])
  end

  # No OSS quem monta automação é administrador, que lê as páginas; a função personalizada (EE) pode montar sem ler.
  it 'recusa quem salva sem ler as páginas de agendamento', :aggregate_failures do
    gatilho = receita(salao.id)[:gatilho]
    sem_paginas = instance_double(AccountUser, permission_granted?: false)
    com_paginas = account.account_users.find_by!(user: jessica)

    expect(problemas(gatilho, sem_paginas)).to eq([I18n.t('autonomia.automacao.receita.agenda_de_reserva_sem_acesso', id: salao.id)])
    expect(problemas(gatilho, com_paginas)).to be_empty
  end

  # Ao rodar, quem ligou e já não lê as páginas não empresta a reserva: vazio com o motivo próprio.
  it 'ao rodar, a reserva só vale enquanto quem ligou lê as páginas', :aggregate_failures do
    expect(Autonomia::Automacao::AgendaDeReserva.resultado(account, salao.id, jessica).url).to eq(Crm::BookingV2::ShortLink.url_for(salao))

    de_fora_da_conta = create(:user)
    resultado = Autonomia::Automacao::AgendaDeReserva.resultado(account, salao.id, de_fora_da_conta)
    expect([resultado.url, resultado.por]).to eq([nil, 'agenda_de_reserva_indisponivel'])

    resultado = Autonomia::Automacao::AgendaDeReserva.resultado(account, de_fora.id, jessica)
    expect([resultado.url, resultado.por]).to eq([nil, 'agenda_de_reserva_indisponivel'])
  end
end
