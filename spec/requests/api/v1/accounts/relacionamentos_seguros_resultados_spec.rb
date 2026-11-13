require 'rails_helper'

# E5 (#2898) — os resultados das renovações: dos seguros que terminaram nos últimos 30, 90 e 365 dias, quantos
# renovaram, quantos não e por quê, por tipo, por seguradora e por quem cuida; e o grupo "Não renovaram" da aba Seguros,
# que mostra os mesmos seguros. Tudo fictício.
RSpec.describe 'Carteira de seguros: resultados das renovações', type: :request do
  # 23h30 de 12/11/2026 em São Paulo: no servidor (UTC) já é dia 13. Para a conta, hoje é 12/11.
  let(:agora) { Time.utc(2026, 11, 13, 2, 30) }
  let(:hoje) { Date.new(2026, 11, 12) }
  let(:account) { conta_com_carteira(reporting_timezone: 'America/Sao_Paulo', locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Bia Exemplo') }
  let(:caio) { create(:user, account: account, role: :agent, name: 'Caio Exemplo') }
  let(:base) { "/api/v1/accounts/#{account.id}/relacionamentos" }
  let(:ajustes) { escolher_funil_de_renovacao(account, user: admin) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023', contact_type: :customer) }
  let(:sem_motivos) { %w[achou_caro outra_corretora vendeu_o_bem nao_respondeu cancelou outro sem_motivo].index_with(0) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { travel_to(agora) }

  def ler(caminho = 'seguros/resultados', quem: admin, **params)
    get "#{base}/#{caminho}", params: params, headers: quem.create_new_auth_token
    response.parsed_body
  end

  def seguro(numero, dias, cuida: nil, pessoa: marina, **campos)
    apolice = criar_apolice(pessoa, numero: numero, fim_vigencia: hoje + dias, **campos.slice(:tipo, :seguradora))
    por_em_renovacao(apolice, ajustes).update!(owner: cuida) if cuida
    apolice.update!(campos.except(:tipo, :seguradora))
    apolice
  end

  # A carteira do exemplo: o que terminou há 10, 20, 29, 30, 31, 200 e 366 dias, um cancelado e os que ainda valem.
  def montar_carteira
    seguro('EX-RENOVOU', -10, cuida: admin, renovado_em: agora)
    seguro('EX-CARO', -20, cuida: caio, nao_renovou_em: agora, motivo_nao_renovou: 'achou_caro')
    seguro('EX-SO-VENCEU', -29, tipo: 'vida', seguradora: 'Outra Seguradora Exemplo')
    seguro('EX-OUTRO', -30, seguradora: 'SEGURADORA EXEMPLO', nao_renovou_em: agora, motivo_nao_renovou: 'outro', motivo_escrito: 'Mudou de cidade')
    seguro('EX-HA-31', -31, tipo: 'residencial', seguradora: 'Outra Seguradora Exemplo', renovado_em: agora)
    seguro('EX-HA-200', -200, nao_renovou_em: agora)
    seguro('EX-HA-366', -366)
    seguro('EX-CANCELADO', -5, cancelado_em: agora)
    seguro('EX-HOJE', 0)
    seguro('EX-EM-30', 30)
    seguro('EX-EM-31', 31)
    seguro('EX-RENOVADO-CEDO', 10, renovado_em: agora)
  end

  def motivos(**contados)
    sem_motivos.merge(contados.stringify_keys).map { |motivo, quantos| { 'motivo' => motivo, 'quantos' => quantos } }
  end

  def linha(chave, nome, venceram, renovou)
    { chave => nome, 'venceram' => venceram, 'renovou' => renovou }
  end

  it 'conta, em cada período, quantos venceram, renovaram e não renovaram, os motivos e os recortes, no dia da conta' do
    montar_carteira
    quem_cuida = [linha('nome', 'Bia Exemplo', 1, 1), linha('nome', 'Caio Exemplo', 1, 0)]

    lido = ler

    expect(response).to have_http_status(:ok)
    expect(lido.keys).to contain_exactly('periodos', 'vencem30')
    expect(lido['vencem30']).to eq(2)
    expect(lido['periodos'][0]).to eq(
      'dias' => 30, 'venceram' => 4, 'renovou' => 1, 'naoRenovou' => 3, 'motivos' => motivos(achou_caro: 1, outro: 1, sem_motivo: 1),
      'recortes' => { 'tipo' => [linha('tipo', 'auto', 3, 1), linha('tipo', 'vida', 1, 0)],
                      'seguradora' => [linha('nome', 'SEGURADORA EXEMPLO', 3, 1), linha('nome', 'Outra Seguradora Exemplo', 1, 0)],
                      'cuida' => quem_cuida }
    )
    expect(lido['periodos'][1]).to eq(
      'dias' => 90, 'venceram' => 5, 'renovou' => 2, 'naoRenovou' => 3, 'motivos' => motivos(achou_caro: 1, outro: 1, sem_motivo: 1),
      'recortes' => { 'tipo' => [linha('tipo', 'auto', 3, 1), linha('tipo', 'residencial', 1, 1), linha('tipo', 'vida', 1, 0)],
                      'seguradora' => [linha('nome', 'SEGURADORA EXEMPLO', 3, 1), linha('nome', 'Outra Seguradora Exemplo', 2, 1)],
                      'cuida' => quem_cuida }
    )
    expect(lido['periodos'][2]).to eq(
      'dias' => 365, 'venceram' => 6, 'renovou' => 2, 'naoRenovou' => 4, 'motivos' => motivos(achou_caro: 1, outro: 1, sem_motivo: 2),
      'recortes' => { 'tipo' => [linha('tipo', 'auto', 4, 1), linha('tipo', 'residencial', 1, 1), linha('tipo', 'vida', 1, 0)],
                      'seguradora' => [linha('nome', 'SEGURADORA EXEMPLO', 4, 1), linha('nome', 'Outra Seguradora Exemplo', 2, 1)],
                      'cuida' => quem_cuida }
    )
  end

  it 'a conta sem seguro vem com os três períodos zerados' do
    lido = ler

    expect(lido['vencem30']).to eq(0)
    expect(lido['periodos']).to eq(
      [30, 90, 365].map do |dias|
        { 'dias' => dias, 'venceram' => 0, 'renovou' => 0, 'naoRenovou' => 0, 'motivos' => motivos,
          'recortes' => { 'tipo' => [], 'seguradora' => [], 'cuida' => [] } }
      end
    )
  end

  it 'o grupo "Não renovaram" da aba Seguros mostra os mesmos seguros que o número da tela conta' do
    montar_carteira
    periodos = ler['periodos'].to_h { |periodo| [periodo['dias'], periodo['naoRenovou']] }

    listas = [30, 90, 365].to_h do |dias|
      lida = ler('seguros', grupo: "nao_renovaram_#{dias}")
      [dias, [lida['itens'].pluck('numero'), lida['total']]]
    end

    expect(listas).to eq(30 => [%w[EX-CARO EX-SO-VENCEU EX-OUTRO], 3], 90 => [%w[EX-CARO EX-SO-VENCEU EX-OUTRO], 3],
                         365 => [%w[EX-CARO EX-SO-VENCEU EX-OUTRO EX-HA-200], 4])
    expect(listas.transform_values(&:last)).to eq(periodos)
  end

  it 'o grupo temporário só entra na contagem quando é ele o pedido, e traz o motivo de cada seguro' do
    montar_carteira

    expect(ler('seguros/contagens').keys).not_to include('nao_renovaram_30')
    expect(ler('seguros/contagens', grupo: 'nao_renovaram_30')).to include('nao_renovaram_30' => 3, 'vencido' => 5)
    expect(ler('seguros', grupo: 'nao_renovaram_30')['itens'].pluck('numero', 'motivo', 'motivoEscrito')).to eq(
      [['EX-CARO', 'achou_caro', nil], ['EX-SO-VENCEU', nil, nil], ['EX-OUTRO', 'outro', 'Mudou de cidade']]
    )
  end

  it 'faz o mesmo número de consultas com a carteira pequena e com a grande' do
    montar_carteira
    do_admin = admin.create_new_auth_token
    pedir = -> { get "#{base}/seguros/resultados", headers: do_admin }
    pedir.call
    com_doze = consultas_da_carteira(&pedir)
    30.times { |n| seguro("EX-MAIS-#{n}", -(n + 1), cuida: (caio if n.even?), tipo: Carteira::Apolice::TIPOS[n % 4]) }

    expect(consultas_da_carteira(&pedir)).to eq(com_doze)
    expect(response.parsed_body['periodos'][0]['venceram']).to eq(34)
  end

  describe 'em toda conta' do
    it 'atende quem vê contatos, e não conta seguro de outra conta' do
      outra = conta_com_carteira
      criar_apolice(create(:contact, account: outra), numero: 'EX-DE-FORA', fim_vigencia: hoje - 3)
      seguro('EX-SO-VENCEU', -3)

      lido = ler(quem: caio)

      expect(response).to have_http_status(:ok)
      expect(lido['periodos'].pluck('venceram')).to eq([1, 1, 1])
    end

    it 'responde 401 sem login, 404 sem a carteira e 422 para parâmetro que não conhece' do
      get "#{base}/seguros/resultados"
      sem_login = response.status
      ler(dias: 30)
      com_parametro = [response.status, response.parsed_body]
      account.disable_features!('carteira_seguros')
      ler

      expect([sem_login, com_parametro, response.status]).to eq([401, [422, { 'error' => 'pedido_invalido' }], 404])
    end
  end
end
