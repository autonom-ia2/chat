require 'rails_helper'

# `lembrar` e `esquecer` (#933): o Guia anota o que a pessoa ensinou e apaga
# quando ela pede. Fora do diário, com o teto e o escopo valendo aqui; o que
# vale guardar é decisão do modelo, pela instrução (bateria M01–M08).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Memória do Guia: lembrar e esquecer' do
  let(:conta) { create(:account) }
  let(:admin) { create(:user, account: conta, role: :administrator) }
  let(:ana) { create(:user, account: conta) }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
                                     instruction: 'Guia.', config: { 'with_knowledge' => false })
  end
  let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }
  let(:memorias) { Autonomia::Guide::Memoria }

  def lembrar(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaLembrar.new(agent: agente, params: params, operador: quem).call
  end

  def esquecer(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaEsquecer.new(agent: agente, params: params, operador: quem).call
  end

  def anotar(texto, user: nil)
    memorias.create!(account: conta, user: user, texto: texto, autor_id: (user || admin).id)
  end

  describe 'lembrar' do
    it 'anota da pessoa ou da corretora, com o autor e o turno', :aggregate_failures do
      conversa = Autonomia::Guide::Conversa.create!(account: conta, user: admin, titulo: 't')
      turno = Autonomia::Guide::Turno.abrir(conversa: conversa, pedido_id: SecureRandom.uuid, pergunta: 'oi', tela: 'home')
      operador = Autonomia::Guide::Contexto.new(account: conta, user: admin, turno_id: turno.id)

      lembrar({ 'texto' => 'Fala curto comigo', 'de_quem' => 'minha' }, quem: operador)
      lembrar({ 'texto' => 'Funil do Zé = funil Comercial (id 12)', 'de_quem' => 'corretora' }, quem: operador)

      expect(memorias.pessoais(conta, admin).pluck(:texto, :autor_id, :turno_id)).to eq([['Fala curto comigo', admin.id, turno.id]])
      expect(memorias.da_corretora(conta).pluck(:texto)).to eq(['Funil do Zé = funil Comercial (id 12)'])
      expect(operador.lembrancas.pluck('de_quem')).to eq(%w[minha corretora])
    end

    # AC-M2
    it 'recusa a 13ª pessoal com a lista atual, e troca quando vem substitui_id', :aggregate_failures do
      atuais = Array.new(12) { |n| anotar("Preferência #{n}", user: admin) }

      recusa = lembrar({ 'texto' => 'Mais uma', 'de_quem' => 'minha' })

      expect(recusa).to include('Não anotei', '12', "##{atuais.first.id} Preferência 0")
      expect(memorias.pessoais(conta, admin).count).to eq(12)

      lembrar({ 'texto' => 'Mais uma', 'de_quem' => 'minha', 'substitui_id' => "##{atuais.first.id}" })

      expect(memorias.pessoais(conta, admin).count).to eq(12)
      expect(atuais.first.reload.texto).to eq('Mais uma')
    end

    it 'recusa o teto da corretora em 20' do
      20.times { |n| anotar("Combinado #{n}") }

      expect(lembrar({ 'texto' => 'Mais um', 'de_quem' => 'corretora' })).to include('Não anotei')
      expect(memorias.da_corretora(conta).count).to eq(20)
    end

    it 'não troca anotação de outra pessoa', :aggregate_failures do
      dela = anotar('Prefere tópicos', user: ana)

      expect(lembrar({ 'texto' => 'Troquei', 'de_quem' => 'minha', 'substitui_id' => dela.id.to_s })).to include('Não anotei')
      expect(dela.reload.texto).to eq('Prefere tópicos')
    end

    # AC-M3
    it 'recusa a da corretora para quem não é administrador, sem gravar nada', :aggregate_failures do
      resposta = lembrar({ 'texto' => 'A corretora trabalha com Porto', 'de_quem' => 'corretora' },
                         quem: Autonomia::Guide::Contexto.new(account: conta, user: ana))

      expect(resposta).to include('só administrador')
      expect(memorias.count).to eq(0)
    end

    it 'recusa frase vazia e frase acima de 200 caracteres', :aggregate_failures do
      expect(lembrar({ 'texto' => '  ', 'de_quem' => 'minha' })).to include('vazia')
      expect(lembrar({ 'texto' => 'x' * 201, 'de_quem' => 'minha' })).to include('200')
      expect(memorias.count).to eq(0)
    end

    # AC-M6 — não é mudança na conta: nada no diário, e o texto não vai para o registro.
    it 'grava fora do diário e o registro guarda de_quem e substitui_id, sem o texto', :aggregate_failures do
      registro = Autonomia::Guide::Registro.new
      chamada = { 'name' => 'anotar_lembranca',
                  'arguments' => { texto: 'CPF do Pedro 123.456.789-00', de_quem: 'minha', substitui_id: nil }.to_json }

      expect { lembrar(JSON.parse(chamada['arguments'])) }.not_to change(Autonomia::Guide::Execucao, :count)
      registro.registrar_chamada(chamada, 'Anotado.', 3)

      expect(registro.chamadas.first['args']).to eq('de_quem' => 'minha', 'substitui_id' => '')
      expect(registro.diagnostico.to_json).not_to include('123.456.789-00')
      expect(operador.execucao).to be_nil
    end
  end

  describe 'esquecer' do
    it 'apaga a anotação e tira o chip do turno', :aggregate_failures do
      lembrar({ 'texto' => 'Funil do Zé = funil Comercial (id 12)', 'de_quem' => 'corretora' })
      id = memorias.last.id

      expect(esquecer({ 'id' => "##{id}" })).to include('Apaguei')
      expect(memorias.exists?(id)).to be(false)
      expect(operador.lembrancas).to eq([])
    end

    it 'não alcança a de outra pessoa nem deixa quem não é administrador apagar a da corretora', :aggregate_failures do
      dela = anotar('Prefere tópicos', user: ana)
      da_corretora = anotar('Trabalhamos com Porto')

      expect(esquecer({ 'id' => dela.id.to_s })).to include('Não apaguei')
      expect(esquecer({ 'id' => da_corretora.id.to_s }, quem: Autonomia::Guide::Contexto.new(account: conta, user: ana)))
        .to include('só administrador')
      expect(memorias.count).to eq(2)
    end
  end

  it 'chega aos Guias pela lista de ferramentas do Seed (a cura reasserta)' do
    expect(Autonomia::Guide::Seed::FERRAMENTAS).to include('anotar_lembranca', 'apagar_lembranca')
  end
end
# rubocop:enable RSpec/DescribeClass
