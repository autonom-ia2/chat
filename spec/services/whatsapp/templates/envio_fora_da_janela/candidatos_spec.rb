require 'rails_helper'

# Os aprovados da caixa que o Jev pode julgar compatíveis (#1587): só o que o envio consegue preencher e mandar como está,
# e só o que as regras de uso deixam usar.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela::Candidatos do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:dois_campos) { { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' } }

  def modelo(nome, status: 'APPROVED', categoria: 'UTILITY', texto: 'Oi, {{1}}! Sobre {{2}}, seguimos por aqui.', extra: [])
    { 'name' => nome, 'language' => 'pt_BR', 'status' => status, 'category' => categoria,
      'components' => [{ 'type' => 'BODY', 'text' => texto }, *extra] }
  end

  def perfil(nome, campos, dono: nil)
    WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: nome, language: 'pt_BR',
                                    fields: campos, system_owner: dono)
  end

  def nomes(**opcoes)
    described_class.new(inbox: inbox, **opcoes).call.map(&:nome)
  end

  it 'aceita o aprovado da conta com todos os campos ligados ao catálogo, com o texto e o mapa' do
    channel.update_columns(message_templates: [modelo('bom')]) # rubocop:disable Rails/SkipsModelValidations
    perfil('bom', dois_campos)

    candidato = described_class.new(inbox: inbox).call.sole

    expect(candidato).to have_attributes(nome: 'bom', idioma: 'pt_BR', categoria: 'UTILITY', sistema: false,
                                         texto: 'Oi, {{1}}! Sobre {{2}}, seguimos por aqui.', campos: dois_campos)
  end

  it 'deixa de fora o que o envio não preenche ou não manda como está' do
    link_variavel = { 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://x.com/{{1}}' }
    templates = [
      modelo('sem_perfil'),
      modelo('campo_solto'),
      modelo('do_publico'),
      modelo('do_horario'),
      modelo('pendente', status: 'PENDING'),
      modelo('autenticacao', categoria: 'AUTHENTICATION'),
      modelo('topo_variavel', extra: [{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Pedido {{1}}' }]),
      modelo('topo_imagem', extra: [{ 'type' => 'HEADER', 'format' => 'IMAGE' }]),
      modelo('link_variavel', extra: [{ 'type' => 'BUTTONS', 'buttons' => [link_variavel] }]),
      modelo('excluido')
    ]
    channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
    perfil('campo_solto', { '1' => 'cliente.primeiro_nome' })
    perfil('do_publico', { '1' => 'cliente.primeiro_nome', '2' => 'publico.vencimento' })
    perfil('do_horario', { '1' => 'cliente.primeiro_nome', '2' => 'horario.data_hora' })
    %w[pendente autenticacao topo_variavel topo_imagem link_variavel excluido].each { |nome| perfil(nome, dois_campos) }

    expect(nomes(excluir: ['excluido'])).to eq([])
  end

  it 'aceita botão de resposta rápida e link fixo' do
    botoes = { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ok' },
                                                  { 'type' => 'URL', 'text' => 'Site', 'url' => 'https://x.com' }] }
    channel.update_columns(message_templates: [modelo('com_botoes', extra: [botoes])]) # rubocop:disable Rails/SkipsModelValidations
    perfil('com_botoes', dois_campos)

    expect(nomes).to eq(['com_botoes'])
  end

  it 'do sistema: UTILITY sim; MARKETING só com a 2ª marca; pesquisa, agendamento e anúncios nunca' do
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      message_templates: [modelo('sis_util'), modelo('sis_mkt', categoria: 'MARKETING'), modelo('conta_mkt', categoria: 'MARKETING'),
                          modelo('customer_satisfaction_survey_9')]
    )
    perfil('sis_util', dois_campos, dono: 'outro_recurso')
    perfil('sis_mkt', dois_campos, dono: 'outro_recurso')
    perfil('conta_mkt', dois_campos)
    perfil('customer_satisfaction_survey_9', dois_campos)

    expect(nomes).to contain_exactly('sis_util', 'conta_mkt')

    WhatsappTemplateConsent.create!(account: account, marca: 'marketing', acao: 'ligou', versao_aviso: 'v1', texto_aviso: 'Aviso.')
    expect(nomes).to contain_exactly('sis_util', 'sis_mkt', 'conta_mkt')
  end

  it 'o modelo do sistema de OUTRO tipo deste ponto (c2y_*) e o pronto da cobrança não servem; o da conta, sim' do
    outro_tipo = "c2y_retomar_contato_#{inbox.id}"
    cobranca = 'cobranca_dia_vencimento_com_valor_v1'
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      message_templates: [modelo(outro_tipo, categoria: 'MARKETING'), modelo(cobranca), modelo('da_conta')]
    )
    perfil(outro_tipo, dois_campos, dono: 'fora_da_janela')
    perfil(cobranca, dois_campos, dono: 'cobranca')
    perfil('da_conta', dois_campos)
    WhatsappTemplateConsent.create!(account: account, marca: 'marketing', acao: 'ligou', versao_aviso: 'v1', texto_aviso: 'Aviso.')

    expect(nomes).to eq(['da_conta'])
  end

  it 'só pt_BR (o idioma dos modelos do tipo), em ordem estável de nome' do
    channel.update_columns( # rubocop:disable Rails/SkipsModelValidations
      message_templates: [modelo('zeta'), modelo('alfa'), modelo('alfa').merge('language' => 'en')]
    )
    perfil('zeta', dois_campos)
    perfil('alfa', dois_campos)
    WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'alfa', language: 'en',
                                    fields: dois_campos)

    candidatos = described_class.new(inbox: inbox).call

    expect(candidatos.map { |candidato| [candidato.nome, candidato.idioma] }).to eq([%w[alfa pt_BR], %w[zeta pt_BR]])
  end
end
