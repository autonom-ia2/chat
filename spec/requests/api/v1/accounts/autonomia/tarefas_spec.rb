require 'rails_helper'

# As tarefas longas do Guia (#936) pela API que a tela usa: andamento, controles e isolamento.
RSpec.describe 'Guia da Plataforma — tarefas longas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:outro_admin) { create(:user, account: account, role: :administrator) }
  let(:rota) { "/api/v1/accounts/#{account.id}/autonomia/tarefas" }
  let(:tarefa) { planejar!(account, admin, receita_de_nomes) }

  before do
    allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true)
    simular_ia_do_cliente!
    limpar_semaforo!
    contatos_em_maiusculas!(account, 30)
  end

  def postar(comando, quem = admin)
    post "#{rota}/#{tarefa.id}/#{comando}", headers: quem.create_new_auth_token, as: :json
  end

  it 'mostra a tarefa com a amostra para o dono', :aggregate_failures do
    get "#{rota}/#{tarefa.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'amostra_pronta', 'total' => 30)
    expect(response.parsed_body['amostra'].size).to eq(10)
  end

  # AC-TL4 — o botão Começar grava o digest e solta o primeiro lote num job.
  it 'começa pela tela: grava o digest e enfileira o lote', :aggregate_failures do
    expect { postar('comecar') }.to have_enqueued_job(Autonomia::Guide::TarefaJob).with(tarefa.id)

    expect(response.parsed_body['status']).to eq('na_fila')
    expect(tarefa.reload.receita_intacta?).to be(true)
  end

  it 'pausa, retoma e cancela, recusando o que o estado não permite', :aggregate_failures do
    postar('comecar')
    postar('pausar')
    expect(response.parsed_body).to include('status' => 'pausada', 'motivo_pausa' => 'pessoa')

    expect { postar('retomar') }.to have_enqueued_job(Autonomia::Guide::TarefaJob)
    expect(response.parsed_body['status']).to eq('na_fila')

    postar('seguir')
    expect(response).to have_http_status(:conflict)

    postar('cancelar')
    expect(response.parsed_body['status']).to eq('cancelada')
  end

  it 'desfaz tudo num job, só quando há lote para desfazer', :aggregate_failures do
    postar('desfazer')
    expect(response).to have_http_status(:unprocessable_entity)

    comecar!(tarefa)
    rodar_lote!(tarefa)
    expect { postar('desfazer') }.to have_enqueued_job(Autonomia::Guide::DesfazerTarefaJob).with(tarefa.id)
    expect(response.parsed_body['status']).to eq('desfazendo')
  end

  # AC-TL9 — de outra pessoa, 404 em tudo, igual a uma que não existe.
  it 'responde 404 para quem não é o dono', :aggregate_failures do
    get "#{rota}/#{tarefa.id}", headers: outro_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    %w[comecar seguir pausar retomar cancelar desfazer].each do |comando|
      postar(comando, outro_admin)
      expect(response).to have_http_status(:not_found)
    end

    get rota, headers: outro_admin.create_new_auth_token, as: :json
    expect(response.parsed_body['tarefas']).to be_empty
    expect(tarefa.reload.status).to eq('amostra_pronta')
  end

  # AC-TL11 — em "Feito pelo Guia", a tarefa é uma linha só, com os totais, e não um lote por linha.
  it 'mostra a tarefa como uma linha em "Feito pelo Guia"', :aggregate_failures do
    comecar!(tarefa)
    rodar_lote!(tarefa)
    tarefa.reload.mudar!('seguir')
    rodar_lote!(tarefa)
    turno = Autonomia::Guide::Execucao.abrir(account: account, user: admin)
    turno.registrar_passo(acao: 'POST labels', frase: 'Criei a etiqueta.', feito: true)

    get "/api/v1/accounts/#{account.id}/autonomia/guide/execucoes", headers: admin.create_new_auth_token, as: :json

    linhas = response.parsed_body['execucoes']
    expect(Autonomia::Guide::Execucao.where(task_id: tarefa.id).count).to eq(2)
    expect(linhas.size).to eq(2)
    linha = linhas.find { |item| item['tarefa_id'] == tarefa.id }
    expect(linha['tarefa']).to include('total' => 30, 'feitos' => 30, 'desfazivel' => true)
  end

  # AC-TL4 — o Guia não começa nem segue sozinho: pela ação direta é recusado (precisa de propor_acao).
  it 'recusa o Guia chamando comecar ou seguir por executar_acao', :aggregate_failures do
    contexto = Autonomia::Guide::Contexto.new(account: account, user: admin)
    contexto.lido({ id: tarefa.id }.to_json)
    %w[comecar seguir].each do |comando|
      ferramenta = Autonomia::Agents::Tools::Native::GuiaExecucao.new(
        agent: nil, operador: contexto,
        params: { 'acao' => "POST autonomia/tarefas/:id/#{comando}", 'descricao' => 'Começar', 'caminho_json' => { id: tarefa.id }.to_json }
      )
      expect(ferramenta.call).to include('Use propor_acao')
    end
    expect(tarefa.reload.status).to eq('amostra_pronta')
  end
end
