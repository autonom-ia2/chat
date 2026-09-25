// Carga do script do Google Maps no navegador, sem bibliotecas extras. Usa o
// mesmo id de script do mapa de resultados (ProspectingGoogleMap.vue): quem
// chegar primeiro carrega, o outro reaproveita. O desenho de área usa as formas
// do núcleo (Circle, Rectangle, Polygon); a biblioteca drawing foi retirada
// pelo Google em maio de 2026 e não é carregada.
export const GOOGLE_MAPS_SCRIPT_ID = 'autonomia-prospecting-google-maps';

let scriptPromise = null;

const waitForScript = script =>
  new Promise((resolve, reject) => {
    script.addEventListener('load', resolve, { once: true });
    script.addEventListener('error', reject, { once: true });
  });

export const loadGoogleMaps = apiKey => {
  if (!apiKey) return Promise.reject(new Error('missing_api_key'));
  if (window.google?.maps) return Promise.resolve();
  if (scriptPromise) return scriptPromise;

  const existingScript = document.getElementById(GOOGLE_MAPS_SCRIPT_ID);
  if (existingScript) {
    scriptPromise = waitForScript(existingScript);
    return scriptPromise;
  }

  const script = document.createElement('script');
  script.id = GOOGLE_MAPS_SCRIPT_ID;
  script.async = true;
  script.defer = true;
  script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(apiKey)}`;
  scriptPromise = waitForScript(script).catch(error => {
    scriptPromise = null;
    throw error;
  });
  document.head.appendChild(script);
  return scriptPromise;
};
