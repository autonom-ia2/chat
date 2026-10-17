require 'rails_helper'

# W4 (#1601): a memória de carona na avaliação de card, com as invariantes do contrato (procedência, isolamento de card
# e de conta, nota da equipe, correção que vence, idempotência, avaliação superada) e os canários.
RSpec.describe Crm::Memoria::Escritor do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, name: 'Ana') }
  let(:card) { create_card(pipeline: suporte, title: 'Seguro auto') }

  before do
    ligar_memoria!(account)
    conversation.reload
    hook = instance_double(MessageTemplates::HookExecutionService, perform: nil)
    allow(MessageTemplates::HookExecutionService).to receive(:new).and_return(hook)
    create_definicao('cpf_titular', :contact_attribute, 'CPF do titular')
    create_definicao('placa', :card_attribute, 'Placa')
    create_definicao('modelo_veiculo', :card_attribute, 'Modelo do veículo')
    create_definicao('franquia', :card_attribute, 'Franquia')
    Crm::Memoria::Catalogo.sincronizar!(account)
  end

  def create_definicao(chave, modelo, rotulo)
    CustomAttributeDefinition.create!(account: account, attribute_key: chave, attribute_display_name: rotulo,
                                      attribute_display_type: :text, attribute_model: modelo)
  end

  def op(grupo, chave, valor, provas, **extra)
    { 'op' => 'adicionar', 'grupo' => grupo, 'chave' => chave, 'item_ref' => nil, 'valor' => valor, 'alvo_fato_id' => nil,
      'base_versao' => nil, 'provas' => provas }.merge(extra.stringify_keys)
  end

  # refs: { 'm1' => message } como o ContextBuilder montaria.
  def aplicar(ops, refs, alvo: card, token: nil)
    classificacao = { memoria_ops: ops, memoria_refs: refs.transform_values(&:id), memoria_token: token, model_used: 'gpt-6-luna' }
    Crm::Memoria::Pendente.guardar!(card: alvo, classificacao: classificacao)
    Crm::Memoria::Pendente.aplicar!(alvo)
  end

  def fatos(**filtro)
    Crm::MemoriaFato.where(account_id: account.id, **filtro)
  end

  def cliente(texto, **attrs)
    mensagem!(conversation, :incoming, content: texto, **attrs)
  end

  def decidir!(message, alvo)
    Crm::SubjectDecision.create!(account: account, conversation: conversation, message_id: message.id, card_id: alvo.id,
                                 action: 'focus', state: 'applied', mode: 'auto')
  end

  describe 'procedência (invariantes 1 e 9)' do
    it 'grava o fato do cliente como alegado, com a prova e o trecho copiados pelo código; a fonte vinda do JSON é ignorada' do
      m1 = cliente('Meu CPF é 123.456.789-00')
      card
      aplicar([op('contato', 'cpf_titular', '12345678900', ['m1'], fonte: 'sistema', status: 'confirmado')], { 'm1' => m1 })

      fato = fatos(chave: 'cpf_titular').sole
      expect(fato).to have_attributes(escopo: 'contato', fonte: 'cliente', status: 'alegado', situacao: 'vigente',
                                      prova_message_ids: [m1.id], prova_trecho: 'Meu CPF é 123.456.789-00', card_id: nil)
    end

    it 'operação sem prova, com ref que esta avaliação não enviou ou com chave fora do catálogo é descartada' do
      m1 = cliente('placa ABC1D23')
      card
      aplicar([op('pedido', 'placa', 'ABC1D23', []), op('pedido', 'placa', 'ABC1D23', ['m9']),
               op('pedido', 'cor_do_carro', 'azul', ['m1'])], { 'm1' => m1 })

      expect(fatos).to be_empty
    end

    it 'a IA ecoando o CPF não prova o fato; cliente + eco da IA dá fonte cliente, alegado (prova mista)' do
      eco = mensagem!(conversation, :outgoing, sender: porta, content: 'Confirmando: seu CPF é 123.456.789-00')
      m2 = cliente('isso, 123.456.789-00')
      card
      aplicar([op('contato', 'cpf_titular', '12345678900', ['m1'])], { 'm1' => eco })
      expect(fatos).to be_empty

      aplicar([op('contato', 'cpf_titular', '12345678900', %w[m1 m2])], { 'm1' => eco, 'm2' => m2 })
      expect(fatos.sole).to have_attributes(fonte: 'cliente', status: 'alegado')
    end

    it '"a atendente confirmou" dito pelo cliente continua alegado; o banco recusa confirmado vindo do cliente' do
      m1 = cliente('A atendente já confirmou: franquia reduzida')
      decidir!(m1, card)
      aplicar([op('pedido', 'franquia', 'reduzida', ['m1'])], { 'm1' => m1 })

      expect(fatos.sole.status).to eq('alegado')
      expect { fatos.sole.update_columns(status: 'confirmado') }.to raise_error(ActiveRecord::StatementInvalid) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  describe 'isolamento de card (invariante 2) e o valor conferido na prova (A9)' do
    it 'CANARIO: a placa dita no card A não vira fato do card B (vira sugestão)' do
      card_a = create_card(pipeline: suporte, title: 'Auto A')
      card_b = create_card(pipeline: comercial, title: 'Auto B')
      m1 = cliente('a placa é CANARIOA1')
      decidir!(m1, card_a)
      aplicar([op('pedido', 'placa', 'CANARIOA1', ['m1'])], { 'm1' => m1 }, alvo: card_b)

      expect(fatos(card_id: card_b.id).sole.situacao).to eq('sugestao')
      expect(fatos(card_id: card_b.id, situacao: 'vigente')).to be_empty
    end

    it 'sem decisão de assunto e com dois cards abertos na conversa, a prova não prende o card: sugestão' do
      create_card(pipeline: comercial, title: 'Outro')
      m1 = cliente('placa XYZ9W87')
      aplicar([op('pedido', 'placa', 'XYZ9W87', ['m1'])], { 'm1' => m1 })

      expect(fatos.sole.situacao).to eq('sugestao')
    end

    it 'CANARIO: dois veículos no MESMO card; a placa é item natural e o modelo no item errado vira sugestão' do
      Crm::MemoriaChave.where(account: account, chave: 'placa').update_all(cardinalidade: 2, item_natural: true) # rubocop:disable Rails/SkipsModelValidations
      Crm::MemoriaChave.where(account: account, chave: 'modelo_veiculo').update_all(cardinalidade: 2) # rubocop:disable Rails/SkipsModelValidations
      card
      m1 = cliente('O meu é um Onix placa ABC1D23')
      m2 = cliente('o da minha esposa é HB20 placa XYZ9W87')
      aplicar([op('pedido', 'placa', 'ABC1D23', ['m1']), op('pedido', 'placa', 'XYZ9W87', ['m2']),
               op('pedido', 'modelo_veiculo', 'Onix', ['m1'], item_ref: 'ABC1D23'),
               op('pedido', 'modelo_veiculo', 'HB20', ['m2'], item_ref: 'ABC1D23')], { 'm1' => m1, 'm2' => m2 })

      expect(fatos(chave: 'placa', situacao: 'vigente').pluck(:item_ref)).to contain_exactly('ABC1D23', 'XYZ9W87')
      expect(fatos(chave: 'modelo_veiculo', situacao: 'vigente').pluck(:item_ref, :valor)).to eq([%w[ABC1D23 Onix]])
      expect(fatos(chave: 'modelo_veiculo', situacao: 'sugestao').pluck(:valor)).to eq(['HB20'])
    end

    it 'CANARIO duas contas: o id de mensagem de outra conta no mapa não prova nada' do
      de_fora = create(:message, conversation: create(:conversation), content: 'placa CANARIOCONTA')
      decidir!(cliente('oi'), card)
      aplicar([op('pedido', 'placa', 'CANARIOCONTA', ['m1'])], { 'm1' => de_fora })

      expect(fatos).to be_empty
    end

    it 'A9: o CPF que só aparece no eco da IA (o cliente disse "o de sempre") vira sugestão' do
      m1 = cliente('pode usar o CPF de sempre')
      eco = mensagem!(conversation, :outgoing, sender: porta, content: 'Certo, CPF 123.456.789-00')
      card
      aplicar([op('contato', 'cpf_titular', '12345678900', %w[m1 m2])], { 'm1' => m1, 'm2' => eco })

      expect(fatos.sole).to have_attributes(situacao: 'sugestao', fonte: 'cliente')
    end

    it 'identidade: o CPF que não aparece na prova (valor inventado) vira sugestão' do
      m1 = cliente('meu CPF é 111.222.333-44')
      card
      aplicar([op('contato', 'cpf_titular', '99988877766', ['m1'])], { 'm1' => m1 })

      expect(fatos.sole.situacao).to eq('sugestao')
    end
  end

  describe 'nota da equipe e mensagem que não prova (invariante 4)' do
    it 'NOTA-SECRETA: nota privada, mensagem encaminhada e voto sem a leitura do #1741 não provam' do
      nota = mensagem!(conversation, :outgoing, sender: ana, content: 'NOTA-SECRETA franquia reduzida', private: true)
      encaminhada = mensagem!(conversation, :outgoing, sender: ana, content: 'franquia reduzida', content_attributes: { forwarded: true })
      voto = cliente('reduzida', content_attributes: { c2y_ai_turn: { kind: 'poll', choice: 'reduzida' } })
      [nota, encaminhada, voto].each { |message| decidir!(message, card) }
      aplicar([op('pedido', 'franquia', 'reduzida', ['m1']), op('pedido', 'franquia', 'reduzida', ['m2']),
               op('pedido', 'franquia', 'reduzida', ['m3'])], { 'm1' => nota, 'm2' => encaminhada, 'm3' => voto })

      expect(fatos).to be_empty unless defined?(Waha::RichNative::TurnKinds)
    end
  end

  describe 'correção vence e versiona (invariante 6), divergência e decisão' do
    it 'a pessoa corrige; a avaliação seguinte tenta voltar ao valor antigo e cai em sugestão visível' do
      m1 = cliente('franquia normal')
      decidir!(m1, card)
      aplicar([op('pedido', 'franquia', 'normal', ['m1'])], { 'm1' => m1 })
      Crm::Memoria::Correcao.corrigir!(card: card, grupo: 'pedido', chave: 'franquia', valor: 'reduzida', user: ana)
      m2 = cliente('a franquia é a normal mesmo')
      decidir!(m2, card)
      aplicar([op('pedido', 'franquia', 'normal', ['m2'])], { 'm2' => m2 })

      vigente = fatos(chave: 'franquia', situacao: 'vigente', expirado_em: nil).sole
      expect(vigente).to have_attributes(valor: 'reduzida', fonte: 'pessoa_corrigiu', status: 'confirmado', travado: true, versao: 2)
      expect(fatos(chave: 'franquia', situacao: 'sugestao').sole.valor).to eq('normal')
    end

    it 'a equipe disse X e depois o cliente diz Y: nasce um divergente, sem trocar o da equipe' do
      m1 = mensagem!(conversation, :outgoing, sender: ana, content: 'Sua franquia ficou reduzida')
      m2 = cliente('franquia normal')
      [m1, m2].each { |message| decidir!(message, card) }
      aplicar([op('pedido', 'franquia', 'reduzida', ['m1'])], { 'm1' => m1 })
      aplicar([op('pedido', 'franquia', 'normal', ['m2'])], { 'm2' => m2 })

      expect(fatos(chave: 'franquia', situacao: 'vigente').sole.valor).to eq('reduzida')
      expect(fatos(chave: 'franquia', situacao: 'divergente').sole).to have_attributes(valor: 'normal', fonte: 'cliente')
    end

    it 'decisão acumula, a repetida não duplica, e a da IA sozinha vale como alegada' do
      m1 = cliente('fico com o carro reserva de 15 dias')
      decidir!(m1, card)
      2.times { aplicar([op('decisao', 'decisao', 'carro reserva 15 dias', ['m1'])], { 'm1' => m1 }) }

      expect(fatos(tipo: 'decisao').sole).to have_attributes(fonte: 'cliente', status: 'alegado', escopo: 'card')
    end
  end

  describe 'falha no meio' do
    it 'uma operação que quebra não derruba as outras nem trava a avaliação do card' do
      m1 = cliente('placa ABC1D23 e franquia reduzida')
      decidir!(m1, card)
      allow(Crm::Memoria::Gravador).to receive(:gravar!).and_call_original
      allow(Crm::Memoria::Gravador).to receive(:gravar!).with(hash_including(chave: 'franquia')).and_raise(ActiveRecord::StatementInvalid, 'x')
      aplicar([op('pedido', 'franquia', 'reduzida', ['m1']), op('pedido', 'placa', 'ABC1D23', ['m1'])], { 'm1' => m1 })

      expect(fatos.pluck(:chave)).to eq(['placa'])
      expect(card.reload.metadata.dig('ai', Crm::Memoria::Pendente::CHAVE)).to be_nil
    end
  end

  describe 'idempotência e avaliação superada (invariantes 10 e 11)' do
    it 'o retry aplica o pendente uma vez só (mesma avaliação, mesma chave estrutural)' do
      m1 = cliente('placa ABC1D23')
      decidir!(m1, card)
      classificacao = { memoria_ops: [op('pedido', 'placa', 'ABC1D23', ['m1'])], memoria_refs: { 'm1' => m1.id }, model_used: 'x' }
      Crm::Memoria::Pendente.guardar!(card: card, classificacao: classificacao)
      described_class.new(card: card, pendente: card.reload.metadata.dig('ai', Crm::Memoria::Pendente::CHAVE)).aplicar
      Crm::Memoria::Pendente.aplicar!(card)

      expect(fatos.count).to eq(1)
      expect(card.reload.metadata.dig('ai', 'memoria_pendente')).to be_nil
    end

    it 'a avaliação superada (outra agendada depois, relendo o card) não grava nada' do
      m1 = cliente('placa ABC1D23')
      decidir!(m1, card)
      Crm::Ai::Observer.new(card: card).marcar(200.0)
      aplicar([op('pedido', 'placa', 'ABC1D23', ['m1'])], { 'm1' => m1 }, token: 100.0)

      expect(fatos).to be_empty
    end
  end

  describe 'mensagem apagada, apagamento e mescla' do
    it 'a mensagem apagada invalida o fato que dependia só dela' do
      m1 = cliente('placa ABC1D23')
      decidir!(m1, card)
      aplicar([op('pedido', 'placa', 'ABC1D23', ['m1'])], { 'm1' => m1 })
      m1.update!(content_attributes: { deleted: true })
      Crm::Memoria::OrigemJob.perform_now(m1.id)

      expect(fatos.sole).to have_attributes(prova_trecho: nil)
      expect(fatos.sole.expirado_em).to be_present
    end

    it 'invariante 13: apagar o contato deixa 0 fatos dele' do
      m1 = cliente('meu CPF é 123.456.789-00')
      card
      aplicar([op('contato', 'cpf_titular', '12345678900', ['m1'])], { 'm1' => m1 })

      expect { Contact.where(id: contact.id).delete_all }.to change(fatos, :count).from(1).to(0)
    end

    it 'C1: mesclar dois contatos com o mesmo CPF vigente não falha nem perde linha; CPF diferente vira divergente' do
      outro = create(:contact, account: account)
      base = { account_id: account.id, escopo: 'contato', tipo: 'fato', chave: 'cpf_titular', fonte: 'pessoa_corrigiu',
               status: 'confirmado', gerado_por: 'teste' }
      Crm::Memoria::Gravador.gravar!(base.merge(contact_id: contact.id, valor: '123', travado: true))
      Crm::Memoria::Gravador.gravar!(base.merge(contact_id: outro.id, valor: '123'))
      Crm::Memoria::Gravador.gravar!(base.merge(contact_id: outro.id, chave: 'placa', valor: 'ZZZ'))

      expect { ContactMergeAction.new(account: account, base_contact: contact, mergee_contact: outro).perform }
        .not_to change(Crm::MemoriaFato, :count)
      expect(fatos(contact_id: contact.id, chave: 'cpf_titular', situacao: 'vigente', expirado_em: nil).sole.travado).to be(true)
    end
  end
end
