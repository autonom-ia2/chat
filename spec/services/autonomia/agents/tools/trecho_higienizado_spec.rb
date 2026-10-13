require 'rails_helper'

# #1425 (revisão): o trecho do corpo de um 4xx que chega ao modelo e à tela de teste.
RSpec.describe Autonomia::Agents::Tools::TrechoHigienizado do
  def trecho(texto, segredos: [], literais: [], limite: 500, cortado: false)
    described_class.new(texto, segredos: segredos, literais: literais, limite: limite, cortado: cortado).to_s
  end

  # Revisão 2: literal do cadastro (caminho, query, corpo) só vale como segredo com cara de credencial.
  it 'keeps a common word of the setup readable' do
    expect(trecho('clientes: busca inválida', literais: %w[clientes busca palavrasemnumero]))
      .to eq('clientes: busca inválida')
  end

  it 'hides a setup literal that looks like a credential, whole and never split' do
    resultado = trecho('chave abc123def e conta loja-0001-matriz', literais: ['abc123def', 'loja-0001-matriz', 'nota fiscal'])

    expect(resultado).to eq('chave [oculto] e conta [oculto]')
  end

  it 'cuts a long common text at the limit' do
    resultado = trecho('palavra ' * 400, limite: 100)

    expect(resultado.length).to be <= 100
    expect(resultado).to start_with('palavra palavra')
  end

  it 'joins line breaks and spaces into one space' do
    expect(trecho("erro:\n\n   falta\to cep")).to eq('erro: falta o cep')
  end

  it 'hides the token of a Bearer header echoed alone' do
    resultado = trecho('token abcdefghij123 recusado', segredos: ['Bearer abcdefghij123'])

    expect(resultado).to eq('token [oculto] recusado')
  end

  it 'keeps a value shorter than 4 characters' do
    expect(trecho('id abc inválido', segredos: ['abc'])).to eq('id abc inválido')
  end

  it 'hides the secret in any letter case' do
    expect(trecho('chave SK_LIVE_AB12 errada', segredos: ['sk_live_ab12'])).to eq('chave [oculto] errada')
  end

  it 'hides the JSON-escaped and url-encoded forms of a secret' do
    segredo = 'a+b/c="d"'
    eco = "json #{JSON.generate(segredo)[1..-2]} url #{CGI.escape(segredo)} barra a+b\\/c=\\\"d\\\""

    resultado = trecho(eco, segredos: [segredo])

    expect(resultado).to eq('json [oculto] url [oculto] barra [oculto]')
  end

  it 'hides long tokens even when nobody listed them' do
    expect(trecho("sessao #{'x' * 40} expirou")).to eq('sessao [oculto] expirou')
  end

  # O corpo foi cortado na origem (2 KB): o último pedaço pode ser o começo de uma chave.
  it 'drops the last piece of a text cut at the source' do
    resultado = trecho('{"erro":"chave errada","eco":"sk_live_abcd', segredos: ['sk_live_abcdefgh'], cortado: true)

    expect(resultado).not_to include('sk_live_ab')
    expect(resultado).to include('chave errada')
  end

  it 'hides a secret prefix left at the end of a cut text' do
    resultado = trecho('chave errada: sk_live_abcd', segredos: ['sk_live_abcdefgh'], cortado: true)

    expect(resultado).not_to include('sk_live')
  end
end
