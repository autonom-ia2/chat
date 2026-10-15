require 'rails_helper'

# Ligar e desligar a autorização do dono para o sistema criar modelos (#1586, regras do épico #1585).
RSpec.describe Whatsapp::Templates::Consentimento do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:versao) { Whatsapp::Templates::AvisoDeConsentimento::VERSAO }
  let(:servico) { described_class.new(account: account, user: admin) }

  def mudar(acao, *marcas, versao_mostrada: versao)
    servico.mudar(acao: acao, marcas: marcas, versao: versao_mostrada)
  end

  def linhas
    WhatsappTemplateConsent.where(account: account).ordem_de_gravacao.pluck(:marca, :acao)
  end

  it 'começa desligada, com o aviso, os preços e os limites da constante' do
    estado = servico.estado

    expect(estado['utility']).to eq('ativo' => false, 'mudanca' => nil)
    expect(estado['marketing']).to eq('ativo' => false, 'mudanca' => nil)
    expect(estado['aviso']).to include('versao' => versao, 'vigente_desde' => '2026-10-01', 'moeda' => 'BRL',
                                       'precos' => { 'utility' => '0.0350', 'marketing' => '0.3217' },
                                       'limites' => { 'modelos' => 250, 'modelos_verificada' => 6000, 'por_hora' => 100 })
  end

  it 'ligar o Aviso de serviço grava quem, a versão, o texto exato mostrado e os preços' do
    texto = I18n.with_locale(:pt_BR) do
      mostrado = servico.estado.dig('aviso', 'textos', 'ligar', 'utility')
      mudar('ligar', 'utility')
      mostrado
    end

    linha = WhatsappTemplateConsent.sole
    expect(linha).to have_attributes(account_id: account.id, user_id: admin.id, user_name: 'Ana Souza', marca: 'utility', acao: 'ligou',
                                     versao_aviso: versao, texto_aviso: texto,
                                     precos: { 'BRL' => '0.0350', 'USD' => '0.0068', 'vigente_desde' => '2026-10-01' })
    expect(texto).to include('R$ 0,035', 'mesmo com a conversa aberta', '01/10/2026', '1.000', 'R$ 35,00')
    expect(WhatsappTemplateConsent.ativo?(account, :utility)).to be(true)
  end

  it 'mostra quem mudou e quando' do
    estado = mudar('ligar', 'utility')

    expect(estado['utility']['ativo']).to be(true)
    expect(estado['utility']['mudanca']).to include('acao' => 'ligou', 'por' => 'Ana Souza')
    expect(Time.iso8601(estado['utility']['mudanca']['em'])).to be_within(5.seconds).of(Time.current)
  end

  it 'usuário apagado: a tela mostra o nome copiado na gravação' do
    mudar('ligar', 'utility')
    admin.destroy!

    estado = described_class.new(account: account).estado

    expect(estado['utility']['mudanca']).to include('acao' => 'ligou', 'por' => 'Ana Souza')
    expect(WhatsappTemplateConsent.sole).to have_attributes(user_id: admin.id, user_name: 'Ana Souza')
  end

  it 'usuário que mudou de nome: a tela mostra o nome atual' do
    mudar('ligar', 'utility')
    admin.update!(name: 'Ana Lima')

    expect(described_class.new(account: account).estado['utility']['mudanca']).to include('por' => 'Ana Lima')
    expect(WhatsappTemplateConsent.sole.user_name).to eq('Ana Souza')
  end

  it 'liga as duas no mesmo pedido: uma linha por marca' do
    estado = mudar('ligar', 'utility', 'marketing')

    expect(linhas).to eq([%w[utility ligou], %w[marketing ligou]])
    expect(estado.values_at('utility', 'marketing').pluck('ativo')).to eq([true, true])
    expect(WhatsappTemplateConsent.find_by(marca: 'marketing').precos).to include('BRL' => '0.3217', 'USD' => '0.0625')
  end

  it 'Divulgação sozinha só liga com o Aviso de serviço ligado' do
    expect { mudar('ligar', 'marketing') }.to raise_error(described_class::Invalida) { |erro| expect(erro.codigo).to eq('utility_desligada') }
    expect(linhas).to eq([])

    mudar('ligar', 'utility')
    mudar('ligar', 'marketing')
    expect(linhas).to eq([%w[utility ligou], %w[marketing ligou]])
  end

  it 'desligar o Aviso de serviço desliga as duas (2 linhas)' do
    mudar('ligar', 'utility', 'marketing')

    mudar('desligar', 'utility')

    expect(linhas.last(2)).to eq([%w[utility desligou], %w[marketing desligou]])
    expect(WhatsappTemplateConsent.ativo?(account, :marketing)).to be(false)
  end

  it 'desligar só a Divulgação mantém o Aviso de serviço' do
    mudar('ligar', 'utility', 'marketing')

    mudar('desligar', 'marketing')

    expect(linhas.last).to eq(%w[marketing desligou])
    expect(WhatsappTemplateConsent.ativo?(account, :utility)).to be(true)
  end

  it 'desligar o Aviso de serviço com a Divulgação já desligada grava só uma linha' do
    mudar('ligar', 'utility')

    mudar('desligar', 'utility')

    expect(linhas).to eq([%w[utility ligou], %w[utility desligou]])
  end

  it 'marca já no estado pedido não grava linha nova' do
    mudar('ligar', 'utility')
    mudar('ligar', 'utility')
    mudar('desligar', 'marketing')

    expect(linhas).to eq([%w[utility ligou]])
  end

  # O Agendamento assina depois (#1585): o evento sai uma vez ao ligar o Aviso de serviço, nunca ao desligar nem na
  # Divulgação.
  it 'publica whatsapp_templates.consentimento_ligado só ao ligar o Aviso de serviço' do
    eventos = []
    assinatura = ActiveSupport::Notifications.subscribe('whatsapp_templates.consentimento_ligado') do |*, payload|
      eventos << payload
    end

    mudar('ligar', 'utility', 'marketing')
    mudar('ligar', 'utility')
    mudar('desligar', 'marketing')
    mudar('desligar', 'utility')

    expect(eventos).to eq([{ account_id: account.id, marca: 'utility' }])
  ensure
    ActiveSupport::Notifications.unsubscribe(assinatura)
  end

  it 'aviso de outra versão (o preço mudou enquanto a pessoa lia): recusa sem gravar' do
    expect { mudar('ligar', 'utility', versao_mostrada: '2026-07-01') }
      .to raise_error(described_class::Invalida) { |erro| expect(erro.codigo).to eq('aviso_mudou') }
    expect(linhas).to eq([])
  end

  it 'ação ou marca fora da lista: recusa' do
    expect { mudar('apagar', 'utility') }.to raise_error(described_class::Invalida) { |erro| expect(erro.codigo).to eq('acao_invalida') }
    expect { mudar('ligar', 'propaganda') }.to raise_error(described_class::Invalida) { |erro| expect(erro.codigo).to eq('marca_invalida') }
    expect { mudar('ligar') }.to raise_error(described_class::Invalida) { |erro| expect(erro.codigo).to eq('marca_invalida') }
  end

  it 'ligar as duas grava nas duas linhas os dois parágrafos que a confirmação mostrou' do
    textos = I18n.with_locale(:pt_BR) do
      mostrados = servico.estado.dig('aviso', 'textos', 'ligar').values_at('utility', 'marketing')
      mudar('ligar', 'utility', 'marketing')
      mostrados
    end

    expect(WhatsappTemplateConsent.distinct.pluck(:texto_aviso)).to eq([textos.join("\n\n")])
  end

  # A confirmação mostrou só o texto de desligar o Aviso de serviço ("de Aviso de serviço e de Divulgação"): a linha da
  # Divulgação que cai junto grava esse texto, não o de desligar só a Divulgação ("O Aviso de serviço continua ligado").
  it 'desligar o Aviso de serviço com a Divulgação ligada grava nas duas linhas o texto mostrado' do
    mudar('ligar', 'utility', 'marketing')

    mostrado = I18n.with_locale(:pt_BR) do
      texto = servico.estado.dig('aviso', 'textos', 'desligar', 'utility')
      mudar('desligar', 'utility')
      texto
    end

    desligadas = WhatsappTemplateConsent.where(acao: 'desligou').ordem_de_gravacao
    expect(desligadas.pluck(:marca, :texto_aviso)).to eq([['utility', mostrado], ['marketing', mostrado]])
    expect(mostrado).to include('para de criar modelos sozinho')
    expect(mostrado).not_to include('continua ligado')
  end

  # Preço mudou = versão nova; quem aceitou antes continua valendo, sem aceitar de novo (épico #1585).
  it 'aceite de versão antiga continua valendo; a tela mostra o preço novo' do
    WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: 'ligou', versao_aviso: '2026-07-01',
                                    texto_aviso: 'Aviso antigo.', precos: { 'BRL' => '0.0300' })

    estado = servico.estado

    expect(estado['utility']['ativo']).to be(true)
    expect(estado.dig('aviso', 'versao')).to eq(versao)
    expect(estado.dig('aviso', 'precos', 'utility')).to eq('0.0350')
  end
end
