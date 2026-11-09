require 'rails_helper'

# Fechamento do épico #2414 (#2570), exemplo 18 dos termos de aceite, o começo e o passo 1 (#2716): "Seleção de
# candidatos sem planilha".
#
# > "Abri vaga de recepcionista e chegam currículos pelo WhatsApp. Quero que o sistema separe os bons e marque a
# > entrevista." — Dra. Patrícia, dona da clínica
#
# Começa quando: "Mensagem com currículo (PDF ou foto) na caixa de vagas." Passo 1: "A IA extrai do currículo nome,
# bairro, experiência e se tem curso de atendimento." O filtro "a mensagem tem anexo" (#2716) para quem só escreveu
# antes da IA, sem cobrar. Os outros passos seguem no pendentes_spec.
RSpec.describe 'Fechamento #2414 · exemplo 18, começo: só o currículo na caixa de vagas chama a IA', :fechamento_automacao,
               type: :request do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:vagas) { canal.inbox }
  let(:outra_caixa) { create(:inbox, account: account, name: 'Atendimento') }
  let(:patricia) { create(:user, account: account, role: :administrator, name: 'Dra. Patrícia') }
  # Chega pelo WhatsApp sem nome: o extrair só preenche o que está vazio (PassoDeExtrair).
  let(:candidata) { create(:contact, account: account, name: '', phone_number: '+5511900000018') }
  let(:contact_inbox) { create(:contact_inbox, inbox: vagas, contact: candidata, source_id: '5511900000018') }
  let(:conversa) { create(:conversation, account: account, inbox: vagas, contact: candidata, contact_inbox: contact_inbox, status: :open) }
  let(:campos) { %w[nome bairro experiencia curso_de_atendimento] }

  let(:receita) do
    {
      gatilho: { tipo: 'mensagem.criada', filtros: [
        { campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' },
        { campo: { '$valor' => 'conversa.caixa_id' }, op: 'igual', valor: vagas.id },
        { campo: { '$valor' => 'mensagem.tem_anexo' }, op: 'igual', valor: true }
      ] },
      passos: [{
        id: 'curriculo', tipo: 'extrair', le: %w[anexos],
        campos: [
          { chave: 'nome', descricao: 'o nome da candidata', destino: 'contato.nome' },
          { chave: 'bairro', descricao: 'o bairro onde mora', destino: 'contato.atributos.bairro' },
          { chave: 'experiencia', descricao: 'a experiência em recepção ou atendimento', destino: 'contato.atributos.experiencia' },
          { chave: 'curso_de_atendimento', descricao: 'se tem curso de atendimento: sim ou não',
            destino: 'contato.atributos.curso_de_atendimento' }
        ]
      }]
    }
  end

  let(:automacao) { montar_automacao(patricia, account, nome: 'Seleção de recepcionista', receita: receita) }

  def manda_o_curriculo(na_conversa)
    mensagem = na_conversa.messages.new(account: account, inbox: na_conversa.inbox, message_type: :incoming, sender: candidata, content: nil)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: :file)
    anexo.file.attach(io: Rails.root.join('spec/assets/sample.pdf').open, filename: 'curriculo-julia.pdf', content_type: 'application/pdf')
    mensagem.save!
    rodar_jobs
  end

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    campos.drop(1).each do |chave|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_model: 'contact_attribute',
                                           attribute_display_type: 'text')
    end
    conversa
    ligar_automacao(patricia, account, automacao)
    clear_enqueued_jobs
    ia_responde(account, 'automacao_extrair' => { 'nome' => 'Júlia Andrade', 'bairro' => 'Tatuapé',
                                                  'experiencia' => '3 anos de recepção em clínica', 'curso_de_atendimento' => 'sim' })
  end

  after { Current.reset }

  it 'o currículo em PDF na caixa de vagas: a IA lê e o contato ganha nome, bairro, experiência e curso', :aggregate_failures do
    manda_o_curriculo(conversa)

    expect(historico_de(automacao)).to eq([['curriculo', 'ok', nil]])
    candidata.reload
    expect(candidata.name).to eq('Júlia Andrade')
    expect(candidata.custom_attributes).to include('bairro' => 'Tatuapé', 'experiencia' => '3 anos de recepção em clínica',
                                                   'curso_de_atendimento' => 'sim')
    expect(ia_recebeu.sole['input'].first['content'].find { |parte| parte['type'] == 'input_file' })
      .to include('filename' => 'curriculo-julia.pdf')
  end

  it 'quem só escreve, sem currículo, não chama a IA' do
    cliente_escreve(conversa, 'Oi, a vaga de recepcionista ainda está aberta?')

    expect([historico_de(automacao), ia_recebeu]).to eq([[], []])
  end

  it 'o currículo que chega em outra caixa não é da vaga' do
    fora = create(:conversation, account: account, inbox: outra_caixa, contact: candidata, status: :open)

    manda_o_curriculo(fora)

    expect([historico_de(automacao), ia_recebeu]).to eq([[], []])
  end
end
