if (!navigator.language.startsWith('pt')) {
  document.documentElement.lang = 'en';
  document.title = 'Instagram — private access';
  document.querySelector('p').textContent = 'Preparing private browser access.';
  document.querySelector('a').textContent = 'Continue to browser';
}
window.location.replace(new URL('../console/', import.meta.url));
