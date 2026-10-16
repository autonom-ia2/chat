require 'rails_helper'

# Ponto único fora da janela de 24 h (#1587, C+D do épico #1585). A Meta (`MetaClient`, `DispatchCheck`), o Jev
# (`TypesafeAi::Decisor`) e o redator (`Ai::Redacao::Escrever`) são sempre dublês: nenhuma chamada paga sai daqui.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:contato) { account.contacts.create!(name: 'Júlia Ramos', phone_number: '+5511955554444') }
  let(:client) { instance_double(Whatsapp::Templates::MetaClient) }
  let(:jev) { instance_double(TypesafeAi::Decisor) }
  let(:outcome) { Whatsapp::Templates::MetaClient::Outcome }
  let(:texto_ia) do
    'Olá, {{cliente.primeiro_nome}}! Aqui é da {{minha_empresa.nome}}. Seu pedido {{negocio.titulo}} segue em andamento; ' \
      'avisamos o próximo passo por aqui.'
  end
  let(:texto_meta) do
    'Olá, {{1}}! Aqui é da {{2}}. Seu pedido {{3}} segue em andamento; avisamos o próximo passo por aqui.'
  end
  let(:campos_ia) { { '1' => 'cliente.primeiro_nome', '2' => 'minha_empresa.nome', '3' => 'negocio.titulo' } }

  before do
    Redis::Alfred.delete(Whatsapp::Templates::EnvioForaDaJanela::Limites.chave_da_hora(inbox))
    allow(Whatsapp::Templates::MetaClient).to receive(:new).with(inbox: inbox).and_return(client)
    allow(TypesafeAi::Config).to receive(:configured?).and_return(true)
    allow(TypesafeAi::Decisor).to receive(:new).and_return(jev)
    allow(jev).to receive(:decidir).and_return(resultado('nenhum'))
    allow(Ai::Redacao::Escrever).to receive(:call).and_return(redacao)
  end

  def resultado(resposta, certeza: 0.95)
    TypesafeAi::Decisor::Resultado.new(resposta: resposta, certeza: certeza, modelo: 'jev-1.13.0')
  end

  def redacao(opcoes = [opcao_ia])
    { status: 'ok', pergunta: nil, sugestoes: [], descartadas: 0, opcoes: opcoes }
  end

  def opcao_ia(texto: texto_ia, categoria: 'servico', botoes: [])
    { texto: texto, chaves_usadas: Ai::Redacao::Chaves.extrair(texto).uniq, categoria_prevista: categoria,
      motivo_categoria: nil, o_que_mudou: nil,
      whatsapp: { cabecalho: nil, rodape: nil, nome_sugerido: 'andamento', botoes: botoes } }
  end

  def autorizar(marca = 'utility', acao = WhatsappTemplateConsent::LIGOU)
    WhatsappTemplateConsent.create!(account: account, marca: marca, acao: acao, versao_aviso: 'v1', texto_aviso: 'Aviso.')
  end

  def modelo(nome, status: 'APPROVED', categoria: 'UTILITY', texto: texto_meta, extra: {})
    { 'id' => "id_#{nome}", 'name' => nome, 'language' => 'pt_BR', 'status' => status, 'category' => categoria,
      'components' => [{ 'type' => 'BODY', 'text' => texto }] }.merge(extra)
  end

  def na_lista(*templates)
    channel.update_columns(message_templates: templates) # rubocop:disable Rails/SkipsModelValidations
  end

  def perfil(nome, campos, dono: nil)
    WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: nome, language: 'pt_BR',
                                    fields: campos, system_owner: dono)
  end

  def proprio(versao = 1)
    versao == 1 ? "c2y_andamento_#{inbox.id}" : "c2y_andamento_#{inbox.id}_v#{versao}"
  end

  def planejar(tipo = 'andamento', **opcoes)
    described_class.planejar(inbox: inbox, tipo: tipo, **opcoes)
  end

  describe '.planejar' do
    it 'caixa sem WhatsApp oficial: equipe, sem IA nem Meta' do
      api = create(:channel_api, account: account).inbox

      plano = described_class.planejar(inbox: api, tipo: 'andamento')

      expect(plano).to include('caminho' => 'equipe', 'motivo' => 'sem_whatsapp_oficial', 'tipo' => 'andamento')
      expect(jev).not_to have_received(:decidir)
    end

    it 'cobrança com o pronto aprovado: o modelo do tipo, sem IA' do
      pronto = Whatsapp::Templates::Finalidades.pronto(:cobranca_vencimento, momento: :no_dia, com_valor: true)
      na_lista(pronto.corpo.deep_stringify_keys.merge('id' => '9', 'status' => 'APPROVED'))

      plano = planejar('cobranca_no_dia', com_valor: true)

      expect(plano).to eq(
        'versao' => 1, 'tipo' => 'cobranca_no_dia', 'caminho' => 'modelo', 'escolha' => 'do_tipo',
        'nome' => 'cobranca_dia_vencimento_com_valor_v1', 'idioma' => 'pt_BR', 'categoria' => 'UTILITY', 'origem' => 'sistema',
        'texto' => pronto.texto, 'campos' => pronto.campos, 'opcoes' => { 'com_valor' => true }, 'ja_recusado' => false
      )
      expect(jev).not_to have_received(:decidir)
      expect(JSON.parse(plano.to_json)).to eq(plano)
    end

    it 'modelo do tipo já aprovado na caixa: usa, sem IA nem Meta' do
      na_lista(modelo(proprio))
      perfil(proprio, campos_ia, dono: 'fora_da_janela')

      plano = planejar

      expect(plano).to include('caminho' => 'modelo', 'escolha' => 'do_tipo', 'nome' => proprio, 'campos' => campos_ia,
                               'texto' => texto_meta, 'origem' => 'sistema')
      expect(jev).not_to have_received(:decidir)
      expect(Ai::Redacao::Escrever).not_to have_received(:call)
    end

    describe 'compatível (decisão do Jev)' do
      let(:da_conta) { modelo('acompanhamento_pedido', texto: 'Oi, {{1}}! Seu pedido {{2}} está em andamento.') }

      before do
        na_lista(da_conta)
        perfil('acompanhamento_pedido', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
      end

      it 'o Jev escolhe um aprovado da conta: modelo compatível, com o mapa de campos do perfil' do
        allow(jev).to receive(:decidir).and_return(resultado('acompanhamento_pedido'))

        plano = planejar

        expect(plano).to include('caminho' => 'modelo', 'escolha' => 'compativel', 'nome' => 'acompanhamento_pedido',
                                 'origem' => 'conta', 'campos' => { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
        expect(TypesafeAi::Decisor).to have_received(:new).with(feature: 'modelo_compativel')
      end

      it 'dois planos seguidos pagam o Jev uma vez só (cache por caixa, tipo e campos)' do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        allow(jev).to receive(:decidir).and_return(resultado('acompanhamento_pedido'))

        2.times { planejar }

        expect(jev).to have_received(:decidir).once
      end

      it 'o Jev sem certeza vale como nenhum' do
        autorizar
        allow(client).to receive(:create).and_return(outcome.new(template: modelo(proprio, status: 'PENDING'), created: true))
        allow(jev).to receive(:decidir).and_return(resultado('acompanhamento_pedido', certeza: 0.4))

        expect(planejar).to include('caminho' => 'criando', 'nome' => proprio)
      end

      it 'ja_recusado: o composer do Followup já recusou, então não pergunta ao Jev' do
        autorizar
        allow(client).to receive(:create).and_return(outcome.new(template: modelo(proprio, status: 'PENDING'), created: true))

        plano = planejar(ja_recusado: true)

        expect(plano).to include('caminho' => 'criando', 'ja_recusado' => true)
        expect(jev).not_to have_received(:decidir)
      end

      it 'Jev fora do ar: segue para criar, sem guardar a falha no cache' do
        autorizar
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
        allow(client).to receive(:create).and_return(outcome.new(template: modelo(proprio, status: 'PENDING'), created: true))
        allow(jev).to receive(:decidir).and_raise(TypesafeAi::Decisor::Error, 'typesafe_unavailable')

        2.times { planejar }

        expect(jev).to have_received(:decidir).twice
      end
    end

    describe 'regras de uso' do
      it 'do sistema e MARKETING: só com a 2ª marca (Divulgação)' do
        na_lista(modelo('cobranca_extra', categoria: 'MARKETING', texto: 'Oi, {{1}}! Sobre {{2}}, fale com a gente.'))
        perfil('cobranca_extra', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' }, dono: 'outro_recurso')
        allow(jev).to receive(:decidir).and_return(resultado('cobranca_extra'))

        expect(planejar(contato: contato)).to include('caminho' => 'equipe', 'motivo' => 'sem_consentimento')

        autorizar('marketing')
        expect(planejar(contato: contato)).to include('caminho' => 'modelo', 'nome' => 'cobranca_extra', 'categoria' => 'MARKETING')
      end

      it 'da conta, qualquer categoria: usa' do
        na_lista(modelo('volta', categoria: 'MARKETING', texto: 'Oi, {{1}}! Ainda tem interesse em {{2}}?'))
        perfil('volta', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
        allow(jev).to receive(:decidir).and_return(resultado('volta'))

        expect(planejar('retomar_contato', contato: contato)).to include('caminho' => 'modelo', 'origem' => 'conta', 'categoria' => 'MARKETING')
        expect(planejar('retomar_contato')).to include('caminho' => 'equipe', 'motivo' => 'sem_contato')
      end

      it 'MARKETING para número +1 (EUA) ou contato que recusou: equipe' do
        na_lista(modelo('volta', categoria: 'MARKETING', texto: 'Oi, {{1}}! Ainda tem interesse em {{2}}?'))
        perfil('volta', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
        allow(jev).to receive(:decidir).and_return(resultado('volta'))

        contato.update!(phone_number: '+14155550100')
        expect(planejar('retomar_contato', contato: contato)).to include('caminho' => 'equipe', 'motivo' => 'numero_eua')

        contato.update!(phone_number: '+5511955554444')
        contato.opt_out!(source: 'manual')
        expect(planejar('retomar_contato', contato: contato)).to include('caminho' => 'equipe', 'motivo' => 'contato_recusou')
      end

      it 'UTILITY não olha a recusa de propaganda do contato' do
        na_lista(modelo(proprio))
        perfil(proprio, campos_ia, dono: 'fora_da_janela')
        contato.opt_out!(source: 'manual')

        expect(planejar(contato: contato)).to include('caminho' => 'modelo')
      end
    end

    describe 'criar o modelo do tipo (IA + Garantir)' do
      before { allow(client).to receive(:create).and_return(outcome.new(template: modelo(proprio, status: 'PENDING'), created: true)) }

      it 'sem a 1ª marca: equipe sem_consentimento, sem pagar a IA nem falar com a Meta' do
        expect(planejar(contato: contato)).to include('caminho' => 'equipe', 'motivo' => 'sem_consentimento')
        expect(Ai::Redacao::Escrever).not_to have_received(:call)
        expect(client).not_to have_received(:create)
      end

      it 'com a 1ª marca: a IA escreve pelo propósito, o Garantir cria e o plano fica criando' do
        autorizar

        plano = planejar

        expect(plano).to include('caminho' => 'criando', 'nome' => proprio, 'campos' => campos_ia, 'texto' => texto_meta,
                                 'categoria' => 'UTILITY', 'origem' => 'sistema')
        expect(Ai::Redacao::Escrever).to have_received(:call).with(
          hash_including(account: account, feature: 'modelo_fora_da_janela', canal: 'whatsapp_modelo',
                         chaves: { permitidas: %w[cliente.primeiro_nome minha_empresa.nome negocio.titulo],
                                   obrigatorias: %w[negocio.titulo] },
                         limites: hash_including(categoria_desejada: 'servico'))
        )
        expect(client).to have_received(:create).with(hash_including('name' => proprio, 'category' => 'UTILITY'))
        perfil_gravado = WhatsappTemplateProfile.find_by(name: proprio)
        expect(perfil_gravado.system_owner).to eq('fora_da_janela')
        expect(perfil_gravado.fields).to eq(campos_ia)
      end

      it 'idempotente: o segundo pré-voo acha o criado, sem IA nem Meta de novo' do
        autorizar
        planejar

        expect(planejar).to include('caminho' => 'criando', 'nome' => proprio)
        expect(Ai::Redacao::Escrever).to have_received(:call).once
        expect(client).to have_received(:create).once
      end

      it 'a opção com botões ou que a IA prevê como propaganda não serve para utilidade' do
        autorizar
        allow(Ai::Redacao::Escrever).to receive(:call).and_return(
          redacao([opcao_ia(botoes: [{ tipo: 'resposta_rapida', texto: 'Confirmar', chave: nil }]),
                   opcao_ia(categoria: 'divulgacao')])
        )

        expect(planejar).to include('caminho' => 'equipe', 'motivo' => 'ia_sem_opcao')
        expect(client).not_to have_received(:create)
      end

      it 'IA fora do ar: equipe ia_indisponivel, e o próximo pré-voo não paga de novo (falha guardada 30 min)' do
        autorizar
        allow(Ai::Redacao::Escrever).to receive(:call).and_raise(Ai::Redacao::Escrever::Indisponivel, 'ai_disabled')

        2.times { expect(planejar).to include('caminho' => 'equipe', 'motivo' => 'ia_indisponivel') }

        expect(Ai::Redacao::Escrever).to have_received(:call).once
        chave = described_class::ModeloDoTipo.chave_da_falha(inbox, described_class::Tipos.buscar('andamento'))
        expect(Redis::Alfred.ttl(chave)).to be_between(1, described_class::ModeloDoTipo::ESPERA_DEPOIS_DA_FALHA)
      ensure
        Redis::Alfred.delete(chave) if chave
      end

      it 'a Meta recusa a criação depois da IA paga: o próximo pré-voo não paga a IA nem gasta o teto de novo' do
        autorizar
        allow(client).to receive(:create).and_raise(Whatsapp::Templates::MetaClient::MetaError.new('recusado', code: 'meta_text'))
        chave = described_class::ModeloDoTipo.chave_da_falha(inbox, described_class::Tipos.buscar('andamento'))

        2.times { expect(planejar).to include('caminho' => 'equipe', 'motivo' => 'meta_recusou') }

        expect(Ai::Redacao::Escrever).to have_received(:call).once
        expect(client).to have_received(:create).once
        expect(Redis::Alfred.get(described_class::Limites.chave_da_hora(inbox)).to_i).to eq(1)
      ensure
        Redis::Alfred.delete(chave)
      end

      it 'a tentativa conta no teto por hora antes da IA, mesmo quando a IA falha' do
        autorizar
        allow(Ai::Redacao::Escrever).to receive(:call).and_return(redacao([]))

        planejar

        expect(Redis::Alfred.get(described_class::Limites.chave_da_hora(inbox)).to_i).to eq(1)
      ensure
        Redis::Alfred.delete(described_class::ModeloDoTipo.chave_da_falha(inbox, described_class::Tipos.buscar('andamento')))
      end

      it 'a regra de categoria do tipo vai no pedido ao redator (o prompt da tela de Modelos não muda)' do
        autorizar

        planejar

        expect(Ai::Redacao::Escrever).to have_received(:call).with(
          hash_including(pedido: include(described_class::Redator::REGRA_DA_CATEGORIA['UTILITY'],
                                         described_class::Redator::SO_CORPO))
        )
      end

      it 'recusado: cria o _v2, contando à IA o motivo da Meta' do
        autorizar
        na_lista(modelo(proprio, status: 'REJECTED', extra: { 'rejected_reason' => 'INCORRECT_CATEGORY' }))
        allow(client).to receive(:create).and_return(outcome.new(template: modelo(proprio(2), status: 'PENDING'), created: true))

        expect(planejar).to include('caminho' => 'criando', 'nome' => proprio(2))
        expect(Ai::Redacao::Escrever).to have_received(:call).with(hash_including(contexto: hash_including(recusa_anterior: 'INCORRECT_CATEGORY')))
      end

      it 'recusado até o _v3: equipe recusado, sem criar outro' do
        autorizar
        na_lista(*[1, 2, 3].map { |versao| modelo(proprio(versao), status: 'REJECTED') })

        expect(planejar).to include('caminho' => 'equipe', 'motivo' => 'recusado')
        expect(client).not_to have_received(:create)
      end

      it 'pausado pela Meta: equipe, sem criar outro por cima' do
        autorizar
        na_lista(modelo(proprio, status: 'PAUSED'))

        expect(planejar).to include('caminho' => 'equipe', 'motivo' => 'pausado')
        expect(Ai::Redacao::Escrever).not_to have_received(:call)
      end

      it 'retomar_contato (MARKETING): criar exige também a 2ª marca, e vai como MARKETING' do
        autorizar
        expect(planejar('retomar_contato', contato: contato)).to include('caminho' => 'equipe', 'motivo' => 'sem_consentimento_propaganda')
        expect(Ai::Redacao::Escrever).not_to have_received(:call)

        autorizar('marketing')
        nome = "c2y_retomar_contato_#{inbox.id}"
        allow(client).to receive(:create).and_return(outcome.new(template: modelo(nome, status: 'PENDING', categoria: 'MARKETING'),
                                                                 created: true))
        allow(Ai::Redacao::Escrever).to receive(:call).and_return(redacao([opcao_ia(categoria: 'divulgacao')]))

        expect(planejar('retomar_contato', contato: contato)).to include('caminho' => 'criando', 'categoria' => 'MARKETING')
        expect(client).to have_received(:create).with(hash_including('category' => 'MARKETING'))
      end

      it '250 modelos na WABA: equipe limite_de_modelos, sem IA' do
        autorizar
        na_lista(*Array.new(250) { |indice| modelo("outro_#{indice}", status: 'REJECTED') })

        expect(planejar(ja_recusado: true)).to include('caminho' => 'equipe', 'motivo' => 'limite_de_modelos')
        expect(Ai::Redacao::Escrever).not_to have_received(:call)
      end

      it '100 criações na hora: equipe limite_por_hora' do
        autorizar
        chave = described_class::Limites.chave_da_hora(inbox)
        Redis::Alfred.set(chave, described_class::Limites::POR_HORA)

        expect(planejar).to include('caminho' => 'equipe', 'motivo' => 'limite_por_hora')
        expect(Ai::Redacao::Escrever).not_to have_received(:call)
      ensure
        Redis::Alfred.delete(chave)
      end

      it 'outro job já está criando o mesmo (caixa, tipo): criando, sem pagar a IA de novo' do
        autorizar
        chave = described_class::ModeloDoTipo.chave_da_trava(inbox, Whatsapp::Templates::EnvioForaDaJanela::Tipos.buscar('andamento'))
        Redis::Alfred.set(chave, 'outro', ex: 60)

        expect(planejar).to include('caminho' => 'criando', 'nome' => proprio)
        expect(Ai::Redacao::Escrever).not_to have_received(:call)
      ensure
        Redis::Alfred.delete(chave)
      end

      it 'outro job criando o _v2 (v1 recusado): criando com o nome da v2' do
        autorizar
        na_lista(modelo(proprio, status: 'REJECTED'))
        chave = described_class::ModeloDoTipo.chave_da_trava(inbox, Whatsapp::Templates::EnvioForaDaJanela::Tipos.buscar('andamento'))
        Redis::Alfred.set(chave, 'outro', ex: 60)

        expect(planejar).to include('caminho' => 'criando', 'nome' => proprio(2))
      ensure
        Redis::Alfred.delete(chave)
      end

      it 'o teto por hora é por WABA: caixas irmãs (e todos os tipos) somam' do
        irma = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                         validate_provider_config: false, message_templates: []).inbox
        expect(irma.channel.waba_id).to eq(channel.waba_id)

        (described_class::Limites::POR_HORA - 1).times { described_class::Limites.reservar!(inbox) }

        expect(described_class::Limites.reservar!(irma)).to be(true)
        expect(described_class::Limites.reservar!(inbox)).to be(false)
      end

      it 'a chave do teto nasce com prazo' do
        described_class::Limites.reservar!(inbox)

        expect(Redis::Alfred.ttl(described_class::Limites.chave_da_hora(inbox))).to be_between(1, described_class::Limites::HORA)
      end

      it 'criar: false (o envio replanejando) nunca cria' do
        autorizar

        expect(planejar(criar: false)).to include('caminho' => 'equipe', 'motivo' => 'no_template')
        expect(Ai::Redacao::Escrever).not_to have_received(:call)
      end
    end
  end

  describe '.enviar' do
    let(:verdict) { Whatsapp::Templates::DispatchCheck::Verdict }
    let(:checagem) { instance_double(Whatsapp::Templates::DispatchCheck) }
    let(:valores) { { '1' => 'Júlia', '2' => 'Studio Exemplo', '3' => 'Seguro auto' } }

    before do
      na_lista(modelo(proprio))
      perfil(proprio, campos_ia, dono: 'fora_da_janela')
      allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(checagem)
      allow(checagem).to receive(:call).and_return(verdict.new(reason_code: nil, source: nil, details: { lookup_source: 'meta' },
                                                               template: modelo(proprio)))
    end

    it 'a conferência veio da lista guardada (a Meta não respondeu): equipe, nada vai com modelo sem conferir' do
      allow(checagem).to receive(:call).and_return(verdict.new(reason_code: nil, source: nil, details: { lookup_source: 'cache' },
                                                               template: modelo(proprio)))

      expect(described_class.enviar(inbox: inbox, plano: planejar, valores: valores))
        .to have_attributes(status: :equipe, motivo: 'conferencia_sem_meta', metadata: {})
    end

    describe 'modelo do sistema MARKETING' do
      let(:marketing) { modelo('cobranca_extra', categoria: 'MARKETING', texto: 'Oi, {{1}}! Sobre {{2}}, fale com a gente.') }

      before do
        na_lista(marketing)
        perfil('cobranca_extra', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' }, dono: 'outro_recurso')
        allow(jev).to receive(:decidir).and_return(resultado('cobranca_extra'))
        allow(checagem).to receive(:call).and_return(verdict.new(reason_code: nil, source: nil, details: { lookup_source: 'meta' },
                                                                 template: marketing))
        autorizar('marketing')
      end

      it 'a 2ª marca desligada entre o pré-voo e o envio: equipe, sem falar com a Meta' do
        plano = planejar(contato: contato)
        expect(plano).to include('caminho' => 'modelo', 'nome' => 'cobranca_extra', 'origem' => 'sistema')
        autorizar('marketing', WhatsappTemplateConsent::DESLIGOU)

        envio = described_class.enviar(inbox: inbox, plano: plano, valores: { '1' => 'Júlia', '2' => 'Seguro' }, contato: contato)

        expect(envio).to have_attributes(status: :equipe, motivo: 'sem_consentimento_propaganda')
        expect(checagem).not_to have_received(:call)
      end

      it 'com a 2ª marca ligada: envia, e o registro guarda a linha da autorização de propaganda' do
        plano = planejar(contato: contato)

        envio = described_class.enviar(inbox: inbox, plano: plano, valores: { '1' => 'Júlia', '2' => 'Seguro' }, contato: contato)

        expect(envio).to be_enviar
        expect(envio.metadata['envio_fora_da_janela']).to include(
          'categoria' => 'MARKETING', 'origem' => 'sistema', 'consentimento_id' => WhatsappTemplateConsent.ultima(account, :marketing).id
        )
      end

      it 'sem contato: equipe sem_contato' do
        plano = planejar(contato: contato)

        expect(described_class.enviar(inbox: inbox, plano: plano, valores: { '1' => 'Júlia', '2' => 'Seguro' }))
          .to have_attributes(status: :equipe, motivo: 'sem_contato')
      end
    end

    it 'não envia: devolve o metadata do MessageSender, relido na Meta, com o registro do envio' do
      consentimento = autorizar

      envio = described_class.enviar(inbox: inbox, plano: planejar, valores: valores)

      expect(envio).to be_enviar
      expect(envio.metadata).to eq(
        'template_name' => proprio, 'template_language' => 'pt_BR', 'template_category' => 'utility',
        'template_params_category' => 'UTILITY', 'template_processed_params' => { 'body' => valores },
        'message_body' => 'Olá, Júlia! Aqui é da Studio Exemplo. Seu pedido Seguro auto segue em andamento; avisamos o próximo ' \
                          'passo por aqui.',
        'envio_fora_da_janela' => { 'tipo' => 'andamento', 'caminho' => 'modelo', 'escolha' => 'do_tipo', 'modelo' => proprio,
                                    'idioma' => 'pt_BR', 'categoria' => 'UTILITY', 'origem' => 'sistema', 'consentimento_id' => consentimento.id }
      )
      expect(Whatsapp::Templates::DispatchCheck).to have_received(:new).with(
        having_attributes(template_params: { 'name' => proprio, 'language' => 'pt_BR', 'category' => 'UTILITY',
                                             'processed_params' => { 'body' => valores } }),
        channel: channel
      )
    end

    it 'campo sem valor: equipe, sem falar com a Meta' do
      envio = described_class.enviar(inbox: inbox, plano: planejar, valores: valores.merge('3' => ' '))

      expect(envio).to have_attributes(status: :equipe, motivo: 'campo_sem_valor')
      expect(checagem).not_to have_received(:call)
    end

    it 'a Meta mudou o modelo: equipe com o código da conferência' do
      allow(checagem).to receive(:call).and_return(verdict.new(reason_code: 'template_not_approved', source: 'template', details: {}))

      expect(described_class.enviar(inbox: inbox, plano: planejar, valores: valores))
        .to have_attributes(status: :equipe, motivo: 'template_not_approved', metadata: {})
    end

    it 'plano criando: no horário relê a caixa e envia se já aprovou' do
      plano = planejar.merge('caminho' => 'criando')

      expect(described_class.enviar(inbox: inbox, plano: plano, valores: valores)).to be_enviar
      expect(Ai::Redacao::Escrever).not_to have_received(:call)
    end

    it 'plano criando e ainda em análise: equipe em_analise, sem criar nada' do
      na_lista(modelo(proprio, status: 'PENDING'))
      plano = { 'versao' => 1, 'tipo' => 'andamento', 'caminho' => 'criando', 'nome' => proprio, 'opcoes' => {} }

      expect(described_class.enviar(inbox: inbox, plano: plano, valores: valores))
        .to have_attributes(status: :equipe, motivo: 'em_analise')
      expect(Ai::Redacao::Escrever).not_to have_received(:call)
    end

    it 'MARKETING: número +1 também barrado no envio' do
      autorizar('marketing')
      na_lista(modelo('volta', categoria: 'MARKETING', texto: 'Oi, {{1}}! Ainda tem interesse em {{2}}?'))
      perfil('volta', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
      allow(jev).to receive(:decidir).and_return(resultado('volta'))
      plano = planejar('retomar_contato', contato: contato)
      contato.update!(phone_number: '+14155550100')

      envio = described_class.enviar(inbox: inbox, plano: plano, valores: { '1' => 'Júlia', '2' => 'Seguro' }, contato: contato)

      expect(envio).to have_attributes(status: :equipe, motivo: 'numero_eua')
    end

    it 'modelo da conta que virou do sistema (MARKETING) depois do pré-voo: a regra relê o dono no horário' do
      na_lista(modelo('volta', categoria: 'MARKETING', texto: 'Oi, {{1}}! Ainda tem interesse em {{2}}?'))
      perfil_da_conta = perfil('volta', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
      allow(jev).to receive(:decidir).and_return(resultado('volta'))
      plano = planejar('retomar_contato', contato: contato)
      expect(plano).to include('caminho' => 'modelo', 'origem' => 'conta')
      perfil_da_conta.update!(system_owner: 'outro_recurso')

      envio = described_class.enviar(inbox: inbox, plano: plano, valores: { '1' => 'Júlia', '2' => 'Seguro' }, contato: contato)

      expect(envio).to have_attributes(status: :equipe, motivo: 'sem_consentimento_propaganda')
    end

    it 'MARKETING: a recusa do contato vale também no envio' do
      autorizar('marketing')
      na_lista(modelo('volta', categoria: 'MARKETING', texto: 'Oi, {{1}}! Ainda tem interesse em {{2}}?'))
      perfil('volta', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
      allow(jev).to receive(:decidir).and_return(resultado('volta'))
      plano = planejar('retomar_contato', contato: contato)
      contato.opt_out!(source: 'manual')

      envio = described_class.enviar(inbox: inbox, plano: plano, valores: { '1' => 'Júlia', '2' => 'Seguro' }, contato: contato)

      expect(envio).to have_attributes(status: :equipe, motivo: 'contato_recusou')
    end
  end

  # O que o Followup faz de verdade: o pré-voo planeja, e o envio no horário chama `enviar` com o plano guardado.
  describe 'pré-voo e envio' do
    let(:checagem) { instance_double(Whatsapp::Templates::DispatchCheck) }
    let(:valores) { { '1' => 'Júlia', '2' => 'Studio Exemplo', '3' => 'Seguro auto' } }

    before { allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(checagem) }

    it 'o compatível paga o Jev uma vez só: o envio replaneja pelo cache' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      da_conta = modelo('acompanhamento_pedido', texto: 'Oi, {{1}}! Seu pedido {{2}} está em andamento.')
      na_lista(da_conta)
      perfil('acompanhamento_pedido', { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' })
      allow(jev).to receive(:decidir).and_return(resultado('acompanhamento_pedido'))
      allow(checagem).to receive(:call).and_return(
        Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: nil, source: nil, details: { lookup_source: 'meta' }, template: da_conta)
      )
      plano = planejar
      expect(plano).to include('caminho' => 'modelo', 'escolha' => 'compativel')

      # Um plano que ficou "criando" no pré-voo obriga o envio a replanejar.
      envio = described_class.enviar(inbox: inbox, plano: plano.merge('caminho' => 'criando'), valores: valores.slice('1', '2'))

      expect(envio).to be_enviar
      expect(envio.metadata['template_name']).to eq('acompanhamento_pedido')
      expect(jev).to have_received(:decidir).once
    end

    it 'o modelo criado no pré-voo ainda em análise no horário: equipe em_analise, sem IA nem Meta de novo' do
      autorizar
      allow(client).to receive(:create).and_return(outcome.new(template: modelo(proprio, status: 'PENDING'), created: true))
      plano = planejar
      expect(plano).to include('caminho' => 'criando', 'nome' => proprio)

      envio = described_class.enviar(inbox: inbox, plano: plano, valores: valores)

      expect(envio).to have_attributes(status: :equipe, motivo: 'em_analise')
      expect(Ai::Redacao::Escrever).to have_received(:call).once
      expect(client).to have_received(:create).once
      expect(Whatsapp::Templates::DispatchCheck).not_to have_received(:new)
    end
  end

  describe '.previa' do
    it 'o texto como vai sair, para a pessoa ver antes' do
      plano = { 'texto' => texto_meta, 'campos' => campos_ia }

      expect(described_class.previa(plano: plano, valores: { '1' => 'Ana', '2' => 'Loja', '3' => 'Pedido 12' }))
        .to eq('Olá, Ana! Aqui é da Loja. Seu pedido Pedido 12 segue em andamento; avisamos o próximo passo por aqui.')
    end
  end

  it 'todo motivo de equipe tem texto em en e pt_BR (crm.service_reminders.aviso.*)' do
    locales = %i[en pt_BR]
    described_class::MOTIVOS.each do |motivo|
      locales.each do |locale|
        expect(I18n.t("crm.service_reminders.aviso.#{motivo}", locale: locale, default: nil)).to be_present, "#{locale}: #{motivo}"
      end
    end
  end
end
