require 'rails_helper'

# Parâmetro que a leitura não lê era ignorado calado (#942): o Guia criou uma vigia de conversas com
# `unassigned_for_more_than_seconds`, a plataforma ignorou, e a vigia contou todas as sem responsável.
# Os parâmetros de cada leitura saem do código, pelo mesmo gerador da escrita (#932).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Guia: parâmetros das leituras' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:consulta) { Autonomia::Guide::Consulta.new(account: conta, user: admin) }
  let(:leituras) { Autonomia::Guide::Formatos.leituras }
  let(:inventado) { 'unassigned_for_more_than_seconds' }

  describe 'o gerador' do
    it 'cobre exatamente o catálogo de ler_da_conta' do
      expect(leituras.keys.sort).to eq(consulta.catalogo)
    end

    # O controller entrega o params inteiro ao ConversationFinder; quem lê é ele.
    it 'segue o params entregue a uma classe nossa e lista o que ela lê', :aggregate_failures do
      conversas = leituras['conversations']

      expect(conversas['parametros']).to include('status', 'labels', 'assignee_type', 'inbox_id', 'page', 'q')
      expect(conversas['parametros']).not_to include(inventado, 'account_id', 'controller')
    end

    it 'leitura que lê params dentro de gem fica sem lista, com o motivo', :aggregate_failures do
      contatos = leituras['contacts']

      expect(contatos).not_to have_key('parametros')
      expect(contatos['motivos'].join).to include('Sift#filtrate')
    end

    it 'o relatório conta as leituras com e sem parâmetros conhecidos', :aggregate_failures do
      relatorio = Autonomia::Guide::Formatos::RELATORIO.read
      sem_lista = leituras.count { |_recurso, leitura| !leitura.key?('parametros') }

      expect(relatorio).to include('## Parâmetros das leituras', "| Sem parâmetros conhecidos | #{sem_lista} |")
      expect(relatorio).to include('- `GET contacts` — ')
    end
  end

  describe 'ler_da_conta' do
    it 'recusa parâmetro que a leitura não lê, com os que ela lê, sem chamar a plataforma', :aggregate_failures do
      expect(Autonomia::Guide::ChamadaInterna).not_to receive(:new)

      resposta = consulta.ler('conversations', { inventado => '3600' })

      expect(resposta).to include("conversations não lê #{inventado}", 'os que ela lê são:', 'assignee_type')
    end

    it 'recusa também o filtro de situação numa leitura que não o lê' do
      expect(consulta.ler('inboxes', {}, { 'status' => 'open' })).to include('inboxes não lê status', 'ela não lê nenhum')
    end

    it 'deixa passar o parâmetro que a leitura lê', :aggregate_failures do
      resposta = consulta.ler('conversations', { 'assignee_type' => 'unassigned' }, { 'status' => 'open' })

      expect(resposta).not_to include('não lê')
      expect(resposta).to start_with('{').or start_with('[')
    end

    # Recusar por palpite quebraria leitura que funciona: sem lista, segue como antes.
    it 'não recusa nada em leitura sem parâmetros conhecidos' do
      expect(consulta.parametros_recusados('contacts', { 'qualquer_um' => '1' })).to be_nil
    end
  end

  describe 'a vigia' do
    def vigia(parametros)
      Autonomia::Guide::Vigia.new(account: conta, criado_por: admin, nome: 'Sem responsável',
                                  leitura: { 'rota' => 'conversations', 'parametros' => parametros,
                                             'medida' => { 'tipo' => 'contagem' } },
                                  gatilho: { 'acima_de' => 0 })
    end

    it 'com parâmetro que a leitura não lê é recusada ao criar, com os que ela lê', :aggregate_failures do
      registro = vigia({ inventado => 3600 })

      expect(registro).not_to be_valid
      expect(registro.errors[:leitura].join).to include("conversations não lê #{inventado}", 'assignee_type')
    end

    it 'com parâmetro que a leitura lê é aceita' do
      expect(vigia({ 'assignee_type' => 'unassigned', 'status' => 'open' })).to be_valid
    end
  end
end
# rubocop:enable RSpec/DescribeClass
