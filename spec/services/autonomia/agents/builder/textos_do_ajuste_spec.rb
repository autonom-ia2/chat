require 'rails_helper'

# #1850 — a pergunta do que faltou não repete o que o cartão ⚠ da tela já mostra (ResultadoDoAjuste.no_cartao). O que o
# cartão não mostra continua citado: sem cartão (o desfazer automático recusado) ou com o cartão neutro (sem conferência
# de todos os itens), a pergunta segue dizendo o que não entrou.
RSpec.describe Autonomia::Agents::Builder::TextosDoAjuste do
  let(:preco) { 'preço passa para a equipe' }
  let(:horario) { 'atenda até as 22h' }

  def item(pedido, atendido:, pedido_pelo_dono: true)
    { 'campo' => 'handoff_rule', 'pedido' => pedido, 'resumo' => 'Mudou.', 'atendido' => atendido,
      'pedido_pelo_dono' => pedido_pelo_dono }
  end

  def texto(chave, **)
    I18n.t("autonomia.agents.ajuste.#{chave}", locale: :pt_BR, **)
  end

  def pergunta(conferencia, explicacao: nil)
    no_cartao = Autonomia::Agents::ResultadoDoAjuste.no_cartao(conferencia)
    described_class.pergunta_do_que_faltou(conferencia, :pt_BR, explicacao: explicacao, no_cartao: no_cartao)
  end

  it 'com o pedido no cartão ⚠, só pergunta (a genérica ou a explicação do Construtor)' do
    conferencia = { 'itens' => [item('2 frases', atendido: true), item("#{preco}.", atendido: false)], 'falta' => true }

    expect(Autonomia::Agents::ResultadoDoAjuste.no_cartao(conferencia)).to eq(pedidos: [preco], faltou_fora: false)
    expect(pergunta(conferencia)).to eq(texto(:de_outro_jeito))
    expect(pergunta(conferencia, explicacao: ' Qual equipe? ')).to eq('Qual equipe?')
  end

  it 'com a linha "uma parte não entrou" no cartão, também só pergunta' do
    conferencia = { 'itens' => [item('2 frases', atendido: true)], 'faltou_fora_da_lista' => true, 'falta' => true }

    expect(pergunta(conferencia)).to eq(texto(:de_outro_jeito))
  end

  it 'cita só o pedido que o cartão não mostra com ⚠ (o não pedido vai à linha neutra, pelo resumo)' do
    conferencia = { 'itens' => [item(preco, atendido: false), item(horario, atendido: false, pedido_pelo_dono: false)],
                    'falta' => true }

    expect(pergunta(conferencia)).to eq("#{texto(:nao_consegui, pedidos: horario)} #{texto(:de_outro_jeito)}")
  end

  it 'sem cartão (o desfazer automático foi recusado), cita o que não entrou como antes' do
    conferencia = { 'itens' => [item(preco, atendido: false, pedido_pelo_dono: false)], 'falta' => true,
                    'faltou_fora_da_lista' => true, 'desfeito' => { 'campos' => ['handoff_rule'], 'ok' => false } }

    expect(Autonomia::Agents::ResultadoDoAjuste.no_cartao(conferencia)).to eq(pedidos: [], faltou_fora: false)
    expect(pergunta(conferencia)).to eq("#{texto(:nao_consegui, pedidos: preco)} #{texto(:de_outro_jeito)}")
  end

  it 'com o cartão neutro (item sem a marca da conferência), cita o que não entrou como antes' do
    conferencia = { 'itens' => [item(preco, atendido: false), item(horario, atendido: nil).except('atendido')],
                    'falta' => true }

    expect(pergunta(conferencia)).to eq("#{texto(:nao_consegui, pedidos: "#{preco}; #{horario}")} #{texto(:de_outro_jeito)}")
  end

  it 'sem pedido citável e sem a linha no cartão, diz que não aplicou tudo' do
    conferencia = { 'itens' => [], 'faltou_fora_da_lista' => true, 'falta' => true,
                    'desfeito' => { 'campos' => [], 'ok' => false } }

    expect(pergunta(conferencia)).to eq("#{texto(:nao_consegui_tudo)} #{texto(:de_outro_jeito)}")
  end
end
