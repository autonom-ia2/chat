import { createI18n } from 'vue-i18n';
import pt from 'dashboard/i18n/locale/pt_BR';
import { novoPassoNovo } from '../passosNovos';
import {
  fraseDoPassoNovo,
  linhaDoEnsaioNovo,
  linhaDoEnsaioReal,
  quemEmFrase,
} from '../frasesDosNovos';
import { guardarNomesDosPassosNovos } from '../nomesDaConta';
import { ensaiarComPassosNovos } from '../adaptadorFalso';
import { linhasDoEnsaio } from '../../ensaio';

// Protótipo #2931–#2936 — as frases dos passos novos com o catálogo pt_BR de
// verdade: o que o Rodrigo lê no Confira e no ensaio. O `t` falso dos outros
// specs não pega maiúscula no meio da frase, preposição errada nem plural.
const { t } = createI18n({
  legacy: false,
  locale: 'pt_BR',
  messages: { pt_BR: pt },
}).global;

const novo = (tipo, mudanca = {}) => ({
  ...novoPassoNovo(tipo, 'p1', t),
  ...mudanca,
});
const frase = passo => fraseDoPassoNovo(passo, t);
const aprovacao = quem => novo('pedir_aprovacao', { quem });
const reuniao = com => novo('marcar_reuniao', { com });
const lista = de => novo('repetir_lista', { lista: de });

describe('frases dos passos novos em pt_BR', () => {
  beforeEach(() => {
    guardarNomesDosPassosNovos({
      pessoa: [{ value: 7, label: 'Maria Souza' }],
      time: [{ value: 3, label: 'Vendas' }],
      etapas: [{ label: 'Funil', options: [{ value: 12, label: 'Proposta' }] }],
    });
  });

  afterEach(() => {
    guardarNomesDosPassosNovos({});
  });

  it('pedir aprovação diz a quem, em minúscula e com o nome escolhido', () => {
    expect(frase(novo('pedir_aprovacao'))).toBe(
      'Pedir aprovação a quem cuida do card: Posso seguir com este pedido?'
    );
    expect(frase(aprovacao({ de: 'pessoa', id: 7 }))).toBe(
      'Pedir aprovação a Maria Souza: Posso seguir com este pedido?'
    );
    expect(frase(aprovacao({ de: 'time', id: 3 }))).toBe(
      'Pedir aprovação ao time Vendas: Posso seguir com este pedido?'
    );
    expect(frase(aprovacao({ de: 'pessoa', id: 99 }))).toBe(
      'Pedir aprovação a uma pessoa da equipe: Posso seguir com este pedido?'
    );
  });

  it('o pedido diz quem recebe, e a reunião, de quem é a agenda', () => {
    expect(quemEmFrase({ de: 'responsavel' }, t)).toBe('quem cuida do card');
    expect(frase(novo('marcar_reuniao'))).toBe(
      'Oferecer 3 horários na agenda de quem cuida do card e marcar a reunião'
    );
    expect(frase(reuniao({ de: 'pessoa', id: 7 }))).toBe(
      'Oferecer 3 horários na agenda de Maria Souza e marcar a reunião'
    );
  });

  it('a lista diz o nome da etapa ou do público', () => {
    expect(frase(lista({ de: 'etapa', etapa_id: 12 }))).toBe(
      'Para cada card da etapa Proposta, até 50 por vez'
    );
    expect(frase(lista({ de: 'publico', publico_id: 1 }))).toBe(
      'Para cada contato do público Clientes ativos, até 50 por vez'
    );
    expect(frase(lista({ de: 'etapa', etapa_id: 99 }))).toBe(
      'Para cada card da etapa escolhida, até 50 por vez'
    );
  });

  it('a espera da pesquisa tem a unidade e o plural certos', () => {
    const espera = duracao =>
      linhaDoEnsaioNovo(novo('pesquisa_nota', { espera: duracao }), t).destaque;

    expect(espera({ valor: 5, unidade: 'horas' })).toContain('por 5 horas.');
    expect(espera({ valor: 1, unidade: 'dias' })).toContain('por 1 dia.');
  });

  it('reunião e pesquisa dizem o que sai com a janela de 24 h fechada', () => {
    expect(linhaDoEnsaioNovo(novo('marcar_reuniao'), t).aviso).toBe(
      'Se a janela de 24 h estiver fechada, não manda nada e a automação para nesta conversa.'
    );
    const comModelo = novo('pesquisa_nota', {
      modelo: { nome: 'pesquisa_nps', idioma: 'pt_BR', variaveis: [] },
    });
    expect(linhaDoEnsaioNovo(comModelo, t).aviso).toContain(
      'vai o modelo pesquisa_nps'
    );
  });

  // Decisão do Rodrigo (12/11): sem com quem marcar, a reunião segue sem
  // reunião pelo "Se o cliente não responder"; o ensaio diz o mesmo que o motor.
  it('a reunião sem com quem marcar diz que segue sem reunião', () => {
    const aviso = faria => linhaDoEnsaioReal({ faria, dados: {} }, t).aviso;

    expect(aviso('reuniao_sem_responsavel')).toBe(
      'Sem responsável no card nem na conversa: seguiria sem reunião, pelo caminho “Se o cliente não responder”.'
    );
    expect(aviso('reuniao_sem_pagina')).toBe(
      'O responsável não tem uma página de agendamento só dele: seguiria sem reunião, pelo caminho “Se o cliente não responder”.'
    );
  });

  it('no ensaio, o galho do passo novo diz o próprio nome', async () => {
    const comGalho = novo('pedir_aprovacao', {
      aprovado: [{ id: 'p2', tipo: 'parar' }],
    });
    const { data } = await ensaiarComPassosNovos(
      { passos: [comGalho] },
      () => ''
    );
    const [, caminho] = linhasDoEnsaio(data.conversas[0].passos, () => '', t);

    expect(caminho.texto).toBe('Se aprovar:');
  });
});
