require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G20 (#2669): os passos de IA leem o anexo que o cliente mandou. Provado na
# triagem do exemplo 18 ("Seleção de candidatos sem planilha"): o candidato manda só o currículo em PDF na caixa de
# vagas, a IA lê o PDF e decide se tem o perfil, e a conversa ganha a etiqueta. A dona monta e liga pela API da tela; a
# mensagem chega pelo despacho da plataforma; a IA é o dublê no endereço da OpenAI. O exemplo 18 inteiro fica no
# pendentes_spec até as outras lacunas dele fecharem.
RSpec.describe 'Fechamento #2414 · G20: a IA lê o anexo', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Rita RH') }
  let(:candidata) { create(:contact, account: account, name: 'Júlia', phone_number: '+5511900000018') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: candidata, source_id: '5511900000018') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: candidata, contact_inbox: contact_inbox, status: :open) }

  let(:receita) do
    {
      gatilho: { tipo: 'mensagem.criada', filtros: [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }] },
      passos: [{
        id: 'perfil', tipo: 'decidir', le: %w[mensagens_recentes anexos], pergunta: 'O currículo tem o perfil da vaga de atendente?',
        caminhos: [
          { nome: 'Tem o perfil', chave: 'tem_perfil', descricao: 'experiência em atendimento ao cliente',
            passos: [etiqueta('etiqueta_perfil', 'perfil')] },
          { nome: 'Sem o perfil', chave: 'sem_perfil', descricao: 'sem experiência em atendimento',
            passos: [etiqueta('etiqueta_banco', 'banco-de-talentos')] }
        ],
        nenhum: []
      }]
    }
  end

  let(:automacao) { montar_automacao(dona, account, nome: 'Triagem de currículos', receita: receita) }

  def etiqueta(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: [nome] } }
  end

  # O currículo chega como o canal grava a mídia: a mensagem sem texto, com o PDF anexado, antes de os jobs rodarem.
  def candidata_manda_o_curriculo
    mensagem = conversa.messages.new(account: account, inbox: inbox, message_type: :incoming, sender: candidata, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'curriculo-julia.pdf', content_type: 'application/pdf')
    mensagem.save!
    rodar_jobs
  end

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    create(:label, account: account, title: 'perfil', description: 'Tem o perfil da vaga')
    create(:label, account: account, title: 'banco-de-talentos', description: 'Fica para outra vaga')
    conversa
    ligar_automacao(dona, account, automacao)
    clear_enqueued_jobs
    ia_responde(account, 'automacao_decidir' => { 'caminho' => 'tem_perfil', 'motivo' => 'três anos de atendimento' })
  end

  after { Current.reset }

  it 'o currículo em PDF, sem uma palavra, vai à IA, e a conversa ganha a etiqueta do caminho', :aggregate_failures do
    candidata_manda_o_curriculo

    expect(historico_de(automacao)).to eq([['perfil', 'ok', nil], ['etiqueta_perfil', 'ok', nil]])
    expect(conversa.reload.label_list).to eq(['perfil'])
    pdf = ia_recebeu.sole['input'].first['content'].find { |parte| parte['type'] == 'input_file' }
    expect(pdf).to include('filename' => 'curriculo-julia.pdf')
    expect(pdf['file_data']).to eq("data:application/pdf;base64,#{Base64.strict_encode64(Rails.root.join('spec/assets/sample.pdf').binread)}")
  end

  it 'a IA não recebe o telefone da candidata, nem no texto que vai junto do PDF' do
    candidata_manda_o_curriculo

    expect(ia_recebeu.sole['input'].first['content'].first['text']).not_to include('900000018')
  end
end
