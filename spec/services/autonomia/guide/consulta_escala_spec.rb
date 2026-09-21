require 'rails_helper'

# A conta de verdade, no tamanho de verdade.
#
# Os outros testes de leitura usam uma resposta fabricada por mim, e por isso
# mediam o que EU achava que a plataforma devolve. Aqui as caixas, os funis e os
# contatos são criados no banco e a leitura passa pelo caminho completo —
# serializador real, payload real, tamanho real.
#
# Existe porque em 20/09/2026 o Guia respondeu "apareceu uma caixa" para uma
# conta com três: o orçamento tinha sido dimensionado olhando etiqueta (92
# bytes) sem nunca olhar caixa de entrada (~3.000). Nenhum teste pegou, porque
# nenhum teste tinha uma caixa de entrada de verdade dentro.
RSpec.describe Autonomia::Guide::Consulta do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:consulta) { described_class.new(account: conta, user: admin) }

  # O pedido do Rodrigo, literal: "quero que ele responda se tiver 40 caixas".
  it 'responde a conta com 40 caixas de entrada, sem cortar', :aggregate_failures do
    40.times { |i| create_crm_inbox(account: conta, name: "Caixa #{i}", members: [admin]) }

    resposta = consulta.ler('inboxes')

    expect(resposta).to include('Caixa 0')
    expect(resposta).to include('Caixa 39')
    expect(resposta).not_to include('NÃO afirme quantos são')
    # Todas as 40, não 39: quem responde "quantas eu tenho" conta o que recebeu.
    expect(resposta.scan('"name"').size).to eq(40)
  end

  it 'responde a conta com 40 funis, sem cortar', :aggregate_failures do
    40.times { |i| create_crm_pipeline(account: conta, user: admin, name: "Funil #{i}") }

    resposta = with_modified_env CRM_KANBAN_ENABLED: 'true' do
      consulta.ler('crm/pipelines')
    end

    expect(resposta).to include('Funil 0', 'Funil 39')
    expect(resposta).not_to include('NÃO afirme quantos são')
  end

  # Recurso desligado na conta responde 404. Isso NÃO pode virar "a plataforma
  # respondeu 404" na tela de quem está tentando trabalhar.
  it 'explica recurso desligado sem mostrar código de status' do
    resposta = with_modified_env CRM_KANBAN_ENABLED: 'false' do
      consulta.ler('crm/pipelines')
    end

    expect(resposta).to include('não está disponível nesta conta')
  end

  # Contato é o recurso que escala sem teto — uma conta real tem milhares. Aqui
  # o certo NÃO é caber tudo: é cortar e dizer que cortou, para o Guia nunca
  # contar a amostra como se fosse o total.
  it 'corta o que não cabe e avisa, em vez de contar a amostra', :aggregate_failures do
    120.times { |i| conta.contacts.create!(name: "Contato #{i}", phone_number: "+5511900000#{format('%03d', i)}") }

    resposta = consulta.ler('contacts')

    expect(resposta).to include('Contato 0')
    expect(resposta).to include('total nesta conta').or include('NÃO afirme quantos são')
  end

  # O que sustenta tudo acima: a lista manda o que identifica, e o detalhe de um
  # item se pede pelo item. Se esta leitura vier enxuta, a de lista não tem como
  # ser o lugar do detalhe — e o desenho inteiro cai.
  it 'a leitura de UM item continua vindo inteira' do
    caixa = create_crm_inbox(account: conta, name: 'Detalhada', members: [admin])

    lista = consulta.ler('inboxes')
    item = consulta.ler('inboxes/:id', { id: caixa.id })

    expect(item.length).to be > (lista.length / 2)
  end
end
