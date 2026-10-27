import { sinalDaConversa, FAIXA_DA_VEZ } from '../sinalDaConversa';
import { FAIXA } from '../duracaoDaEspera';
import { REMETENTE } from '../prefixoDoRemetente';
import { FUSO, emSaoPaulo, t } from './apoio';

const AGORA = emSaoPaulo(2026, 10, 25, 19, 21);
const MIN = 60;
const iso = segundos => new Date(segundos * 1000).toISOString();
const NOMES = { 7: 'Bruno Reis', 9: 'Ana Lopes' };

const conversa = (extras = {}) => ({
  status: 'open',
  waiting_since: 0,
  meta: {},
  additional_attributes: {},
  ...extras,
});
const cliente = { tipo: REMETENTE.CLIENTE };
const sinal = (chat, extras = {}) =>
  sinalDaConversa(chat, {
    t,
    agora: AGORA,
    fuso: FUSO,
    euId: 1,
    ultima: cliente,
    nomeDoUltimoRobo: '',
    nomeDoAgente: id => NOMES[id] || '',
    mostrarResponsavel: true,
    ...extras,
  });
const convite = (convidado, segundos) => ({
  crm_entrega: {
    modo: 'convite',
    convidado_id: convidado,
    ate: iso(AGORA + segundos),
  },
});

describe('sinalDaConversa (#2202, linha 3)', () => {
  it('0. Sua vez, para o convidado, com prazo em minutos; abaixo de 1 min, "pegue agora"', () => {
    const chat = conversa({
      waiting_since: AGORA - 600,
      additional_attributes: convite(1, 4 * MIN + 30),
    });
    expect(sinal(chat).sinal).toMatchObject({
      texto: 'Sua vez: 4 min para pegar',
      faixa: FAIXA_DA_VEZ,
    });
    const quase = conversa({ additional_attributes: convite(1, 59) });
    expect(sinal(quase).sinal.texto).toBe('Sua vez: pegue agora');
    const um = conversa({ additional_attributes: convite(1, 60) });
    expect(sinal(um).sinal.texto).toBe('Sua vez: 1 min para pegar');
  });

  it('0. no "ate" exato o convite acabou: vale a próxima regra', () => {
    const chat = conversa({
      waiting_since: AGORA - 600,
      additional_attributes: convite(1, 0),
    });
    expect(sinal(chat).sinal.familia).toBe('espera');
  });

  it('0b. Reservada para outra pessoa, também para o gestor; sem nome, "outra pessoa"', () => {
    const chat = conversa({ additional_attributes: convite(7, 300) });
    expect(sinal(chat).sinal.texto).toBe('Reservada para Bruno');
    const semNome = conversa({ additional_attributes: convite(99, 300) });
    expect(sinal(semNome).sinal.texto).toBe('Reservada para outra pessoa');
  });

  it('1. adiada, com e sem hora de voltar', () => {
    const comHora = conversa({
      status: 'snoozed',
      snoozed_until: iso(emSaoPaulo(2026, 10, 26, 9)),
    });
    expect(sinal(comHora).sinal.texto).toBe('Adiada até amanhã 9:00');
    const semHora = conversa({ status: 'snoozed', snoozed_until: null });
    expect(sinal(semHora).sinal.texto).toBe('Adiada até o cliente responder');
  });

  it('2. o robô pediu ajuda: o nome do robô responsável; sem nome, "A assistente"', () => {
    const chat = conversa({
      waiting_since: AGORA - 20 * MIN,
      meta: {
        assignee_type: 'AgentBot',
        assignee: { id: 3, name: 'Gabriela' },
      },
      additional_attributes: {
        bot_handoff_waiting_since: iso(AGORA - 12 * MIN),
      },
    });
    expect(sinal(chat).sinal).toMatchObject({
      texto: 'Gabriela pediu ajuda há 12 min',
      faixa: FAIXA.CALMA,
    });
    const semNome = conversa({
      waiting_since: AGORA - 20 * MIN,
      additional_attributes: {
        bot_handoff_waiting_since: iso(AGORA - 40 * MIN),
      },
    });
    expect(sinal(semNome).sinal).toMatchObject({
      texto: 'A assistente pediu ajuda há 40 min',
      faixa: FAIXA.ATENCAO,
      selo: true,
    });
  });

  it('2. sem espera ativa (respondeu sem pegar), não diz "pediu ajuda"', () => {
    const chat = conversa({
      waiting_since: 0,
      additional_attributes: {
        bot_handoff_waiting_since: iso(AGORA - 12 * MIN),
      },
    });
    const resultado = sinal(chat, {
      ultima: { tipo: REMETENTE.PESSOA, nome: 'Ana' },
    });
    expect(resultado.sinal.texto).toBe('Ana respondeu sem pegar');
  });

  it('3. espera do cliente nas três cores e, com 7 dias, "Sem resposta" em cinza', () => {
    const espera = segundos =>
      sinal(conversa({ waiting_since: AGORA - segundos })).sinal;
    expect(espera(8 * MIN)).toMatchObject({
      texto: 'Esperando há 8 min',
      faixa: FAIXA.CALMA,
    });
    expect(espera(40 * MIN)).toMatchObject({ faixa: FAIXA.ATENCAO });
    expect(espera(2 * 3600)).toMatchObject({
      texto: 'Esperando há 2 horas',
      faixa: FAIXA.URGENTE,
    });
    expect(espera(13 * 86400)).toMatchObject({
      texto: 'Sem resposta há 13 dias',
      faixa: FAIXA.PARADA,
    });
  });

  it('3. nota por último com espera ativa continua mostrando a espera', () => {
    const chat = conversa({ waiting_since: AGORA - 3 * 3600 });
    expect(
      sinal(chat, { ultima: { tipo: REMETENTE.NOTA } }).sinal.familia
    ).toBe('espera');
  });

  it('3. a última é nossa: não é "esperando"', () => {
    const chat = conversa({ waiting_since: AGORA - 3600 });
    const resultado = sinal(chat, { ultima: { tipo: REMETENTE.EQUIPE } });
    expect(resultado.sinal.familia).toBe('ninguem');
  });

  it('4. "respondeu sem pegar" aparece em todas as abas', () => {
    const resultado = sinal(conversa(), {
      ultima: { tipo: REMETENTE.VOCE },
      mostrarResponsavel: false,
    });
    expect(resultado.sinal.texto).toBe('Você respondeu sem pegar');
  });

  it('4. "Com …" e "Sem ninguém" só onde a aba não diz isso', () => {
    const comAna = conversa({
      meta: { assignee_type: 'User', assignee: { id: 9, name: 'Ana Lopes' } },
    });
    expect(
      sinal(comAna, { ultima: { tipo: REMETENTE.PESSOA, nome: 'Ana' } }).sinal
        .texto
    ).toBe('Com Ana');
    expect(
      sinal(comAna, {
        mostrarResponsavel: false,
        ultima: { tipo: REMETENTE.PESSOA },
      }).sinal
    ).toBeNull();
    const robo = conversa({
      meta: {
        assignee_type: 'AgentBot',
        assignee: { id: 3, name: 'Gabriela' },
      },
    });
    expect(
      sinal(robo, { ultima: { tipo: REMETENTE.ROBO, nome: 'Gabriela' } }).sinal
    ).toMatchObject({
      texto: 'Com Gabriela',
      selo: true,
    });
    expect(
      sinal(conversa(), { ultima: { tipo: REMETENTE.EQUIPE } }).sinal.texto
    ).toBe('Sem ninguém');
  });

  it('prioridade: só urgente e alta, com ou sem sinal', () => {
    expect(
      sinal(conversa({ priority: 'urgent', waiting_since: AGORA - 3600 }))
    ).toMatchObject({
      prioridade: 'Urgente',
      sinal: { texto: 'Esperando há 1 hora' },
    });
    expect(
      sinal(conversa({ priority: 'high' }), { mostrarResponsavel: false })
        .prioridade
    ).toBe('Prioridade alta');
    expect(sinal(conversa({ priority: 'medium' })).prioridade).toBe('');
  });

  it('Captain::Assistant responsável conta como robô, como o AgentBot', () => {
    const captain = conversa({
      meta: {
        assignee_type: 'Captain::Assistant',
        assignee: { id: 9, name: 'Clara' },
      },
    });
    expect(
      sinal(captain, { ultima: { tipo: REMETENTE.ROBO, nome: 'Clara' } }).sinal
    ).toMatchObject({ familia: 'com_robo', texto: 'Com Clara', selo: true });
    // Robô responsável não é pessoa: a resposta da equipe sem pegar aparece.
    expect(
      sinal(captain, { ultima: { tipo: REMETENTE.PESSOA, nome: 'Ana' } }).sinal
        .familia
    ).toBe('respondeu');
  });
});

describe('sinalDaConversa: Resolvida na busca (#2211)', () => {
  it('no resultado da busca, a conversa resolvida diz "Resolvida"', () => {
    const achado = sinal(conversa({ status: 'resolved' }), {
      marcarResolvida: true,
    });
    expect(achado.sinal.texto).toBe('Resolvida');
    expect(achado.sinal.icone).toBe('i-lucide-circle-check');
  });

  it('fora da busca, a resolvida segue as outras regras', () => {
    const achado = sinal(conversa({ status: 'resolved' }));
    expect(achado.sinal.familia).not.toBe('resolvida');
  });

  it('na busca, a aberta não ganha "Resolvida"', () => {
    const achado = sinal(conversa(), { marcarResolvida: true });
    expect(achado.sinal.familia).not.toBe('resolvida');
  });
});
