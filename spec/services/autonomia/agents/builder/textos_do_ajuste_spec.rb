require 'rails_helper'

# #1850 — a pergunta do que faltou tem duas formas. A INTEIRA ("Não consegui aplicar: X. Pergunta") vai para a conversa e
# para a pendência do Construtor: o referente nunca se perde, nem no turno seguinte nem depois do Desfazer. A DA TELA,
# enquanto o cartão ⚠ do turno está lá, não repete o que o cartão já mostra (ResultadoDoAjuste.o_que_faltou, pelos grupos
# do cartão). Sem cartão, ou com o cartão neutro, as duas são iguais.
RSpec.describe Autonomia::Agents::Builder::TextosDoAjuste do
  let(:preco) { 'preço passa para a equipe' }
  let(:horario) { 'atenda até as 22h' }

  def item(pedido, atendido:, pedido_pelo_dono: true, campo: 'handoff_rule')
    { 'campo' => campo, 'pedido' => pedido, 'resumo' => 'Mudou.', 'atendido' => atendido, 'pedido_pelo_dono' => pedido_pelo_dono }
  end

  def texto(chave, **)
    I18n.t("autonomia.agents.ajuste.#{chave}", locale: :pt_BR, **)
  end

  def inteira(conferencia, explicacao: nil)
    described_class.pergunta_do_que_faltou(conferencia, :pt_BR, explicacao: explicacao)
  end

  def na_tela(conferencia, explicacao: nil)
    described_class.pergunta_na_tela(conferencia, :pt_BR, explicacao: explicacao)
  end

  it 'com o pedido no cartão ⚠, a da tela só pergunta e a inteira cita o pedido' do
    conferencia = { 'itens' => [item('2 frases', atendido: true), item("#{preco}.", atendido: false)], 'falta' => true }

    expect(inteira(conferencia)).to eq("#{texto(:nao_consegui, pedidos: preco)} #{texto(:de_outro_jeito)}")
    expect(na_tela(conferencia)).to eq(texto(:de_outro_jeito))
    expect(na_tela(conferencia, explicacao: ' Qual equipe? ')).to eq('Qual equipe?')
  end

  it 'com a linha "uma parte não entrou" no cartão, a da tela também só pergunta' do
    conferencia = { 'itens' => [item('2 frases', atendido: true)], 'faltou_fora_da_lista' => true, 'falta' => true }

    expect(inteira(conferencia)).to eq("#{texto(:nao_consegui_tudo)} #{texto(:de_outro_jeito)}")
    expect(na_tela(conferencia)).to eq(texto(:de_outro_jeito))
  end

  it 'compara pelo grupo do cartão: o destino secundário com outro pedido entra no ⚠ do principal' do
    conferencia = { 'itens' => [item('mais curto', atendido: true, campo: 'tone'),
                                item('regra de tamanho', atendido: false, pedido_pelo_dono: false, campo: 'instruction')],
                    'falta' => true }

    expect(Autonomia::Agents::ResultadoDoAjuste.o_que_faltou(conferencia)).to eq(fora_do_cartao: [], mostrado: true)
    expect(na_tela(conferencia)).to eq(texto(:de_outro_jeito))
  end

  it 'a da tela cita só o pedido que o cartão não mostra com ⚠ (o não pedido vai à linha neutra, pelo resumo)' do
    conferencia = { 'itens' => [item(preco, atendido: false), item(horario, atendido: false, pedido_pelo_dono: false)],
                    'falta' => true }

    expect(na_tela(conferencia)).to eq("#{texto(:nao_consegui, pedidos: horario)} #{texto(:de_outro_jeito)}")
  end

  it 'sem cartão (o desfazer automático foi recusado), as duas são iguais' do
    conferencia = { 'itens' => [item(preco, atendido: false, pedido_pelo_dono: false)], 'falta' => true,
                    'faltou_fora_da_lista' => true, 'desfeito' => { 'campos' => ['handoff_rule'], 'ok' => false } }

    expect(Autonomia::Agents::ResultadoDoAjuste.o_que_faltou(conferencia)).to eq(fora_do_cartao: [preco], mostrado: false)
    expect(na_tela(conferencia)).to eq(inteira(conferencia))
  end

  it 'com o cartão neutro (item sem a marca da conferência), as duas são iguais' do
    conferencia = { 'itens' => [item(preco, atendido: false), item(horario, atendido: nil).except('atendido')],
                    'falta' => true }

    expect(na_tela(conferencia)).to eq("#{texto(:nao_consegui, pedidos: "#{preco}; #{horario}")} #{texto(:de_outro_jeito)}")
    expect(na_tela(conferencia)).to eq(inteira(conferencia))
  end
end
