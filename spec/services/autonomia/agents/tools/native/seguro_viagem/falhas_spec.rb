require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Falhas do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:contratado) { Autonomia::Agents::Agent.create!(account: account, name: 'Contratado', agent_type: 'custom') }
  let!(:acesso) do
    # O `let!` roda antes do `before`: a senha é coluna cifrada, e a CI não tem as chaves do cofre (R8).
    enable_test_encryption!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
  end

  def tratar(codigo, mensagem = nil)
    erro = Autonomia::Seguradoras::Universal::Cliente::Erro.new(codigo, mensagem_da_seguradora: mensagem)
    described_class.tratar(erro, acao: 'cotar_seguro_viagem', agent: contratado, conversation: conversa)
  end

  def notas
    conversa.messages.where(private: true)
  end

  it 'acesso recusado: marca o acesso, posta nota privada uma vez, registra a recusa' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('acesso_recusado', hash_including(slug: 'cotar_seguro_viagem', conversa: conversa.id)).twice
    2.times { tratar('acesso_recusado') }
    expect(acesso.reload).to have_attributes(estado: 'recusado', motivo: 'acesso_recusado')
    expect(notas.count).to eq(1)
  end

  it 'acesso recusado limpa as capacidades, como a conferência recusada' do
    acesso.update!(capacidades: { 'so_cotacao' => false, 'tarifa_acordo' => true })
    tratar('acesso_recusado')
    expect(acesso.reload.capacidades).to eq({})
  end

  it 'acesso recusado manda passar a conversa para a equipe' do
    expect(tratar('acesso_recusado')).to eq(described_class::TEXTO_PASSAR)
  end

  it 'a frase ao modelo não traz o erro técnico nem a credencial' do
    expect(tratar('acesso_recusado')).not_to include('401', 'corretor.teste', 's3nha-teste')
  end

  it 'a nota à equipe não traz a credencial' do
    tratar('acesso_recusado')
    expect(notas.first.content).not_to include('corretor.teste', 's3nha-teste')
  end

  it 'acesso recusado sem acesso gravado não levanta e ainda devolve o texto' do
    acesso.destroy!
    expect(tratar('acesso_recusado')).to eq(described_class::TEXTO_PASSAR)
    expect(notas.count).to eq(1)
  end

  it 'indisponível: nota uma vez, não mexe no acesso, registra e manda tentar de novo' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('indisponivel', hash_including(slug: 'cotar_seguro_viagem', conversa: conversa.id)).twice
    textos = Array.new(2) { tratar('indisponivel') }
    expect(textos.uniq).to eq([described_class::TEXTO_INDISPONIVEL])
    expect(acesso.reload.estado).to eq('ok')
    expect(notas.count).to eq(1)
  end

  it 'a mesma falha em outra ação da mesma conversa vira outra nota' do
    tratar('indisponivel')
    erro = Autonomia::Seguradoras::Universal::Cliente::Erro.new('indisponivel')
    described_class.tratar(erro, acao: 'gerar_proposta_seguro_viagem', agent: contratado, conversation: conversa)
    expect(notas.count).to eq(2)
  end

  it 'pedido inválido: repassa a mensagem curta da seguradora rotulada como dado, sem nota' do
    texto = tratar('pedido_invalido', 'Data de saída inválida')
    expect(texto).to include('"Data de saída inválida"', Autonomia::Agents::Tools::Recusa::AVISO_DE_DADO_EXTERNO)
    expect(texto).to start_with(described_class::TEXTO_INVALIDO)
    expect(notas.count).to eq(0)
  end

  it 'pedido inválido sem mensagem (nil ou só espaços): só o texto fixo, sem "pedido: ."' do
    expect(tratar('pedido_invalido')).to eq(described_class::TEXTO_INVALIDO)
    expect(tratar('pedido_invalido', '   ')).to eq(described_class::TEXTO_INVALIDO)
  end

  it 'pedido inválido registra a recusa e não mexe no acesso' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pedido_invalido', anything)
    tratar('pedido_invalido', 'x')
    expect(acesso.reload.estado).to eq('ok')
  end

  it 'sem link: nota e recusa registrada' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_link', anything)
    described_class.sem_link(acao: 'gerar_proposta_seguro_viagem', agent: contratado, conversation: conversa)
    expect(notas.count).to eq(1)
  end

  it 'sem link devolve o texto que manda passar a conversa' do
    texto = described_class.sem_link(acao: 'gerar_proposta_seguro_viagem', agent: contratado, conversation: conversa)
    expect(texto).to eq(described_class::TEXTO_SEM_LINK)
  end
end
