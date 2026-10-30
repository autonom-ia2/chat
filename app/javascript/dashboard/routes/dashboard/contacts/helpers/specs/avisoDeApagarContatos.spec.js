import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/painelDoContato.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/painelDoContato.json';
import { avisoDeApagarContatos } from '../avisoDeApagarContatos';

// #2138: a exclusão em massa escolhe o aviso pela quantidade selecionada; o texto vem do catálogo real.
const tDe = locale =>
  createI18n({ legacy: false, locale, messages: { en, pt_BR: ptBR } }).global.t;

describe('avisoDeApagarContatos', () => {
  it.each([
    [
      1,
      'O contato, as conversas e as mensagens dele serão apagados. Não dá para desfazer.',
    ],
    [
      2,
      'Os 2 contatos, as conversas e as mensagens deles serão apagados. Não dá para desfazer.',
    ],
    [
      37,
      'Os 37 contatos, as conversas e as mensagens deles serão apagados. Não dá para desfazer.',
    ],
  ])('com %i selecionado(s), em pt_BR', (quantidade, texto) => {
    expect(avisoDeApagarContatos(tDe('pt_BR'), quantidade)).toBe(texto);
  });

  it.each([
    [
      1,
      "The contact, its conversations and its messages will be deleted. This can't be undone.",
    ],
    [
      2,
      "These 2 contacts, their conversations and their messages will be deleted. This can't be undone.",
    ],
    [
      37,
      "These 37 contacts, their conversations and their messages will be deleted. This can't be undone.",
    ],
  ])('com %i selecionado(s), em inglês', (quantidade, texto) => {
    expect(avisoDeApagarContatos(tDe('en'), quantidade)).toBe(texto);
  });
});
