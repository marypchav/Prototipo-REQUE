/* =====================================================================
   comun.js: funciones que usan todas las páginas.
     - api():          llama al backend y devuelve { ok, datos, mensaje }
     - pintarMarco():  encabezado y pie de página
     - notificar():    aviso flotante de confirmación o error
     - formatos de precio, fotos y textos
   Se carga ANTES del script propio de cada página.
   ===================================================================== */

const MENSAJE_INESPERADO = 'Ocurrió un error inesperado. Intente de nuevo más tarde.';
const MENSAJE_SIN_CONEXION = 'No hay conexión con el servidor. Intente de nuevo más tarde.';

// Error con el código de la API (ver database/CodigosError.md)
class ErrorApi extends Error {
  constructor(codigo, mensaje, estadoHttp = 0) {
    super(mensaje);
    this.codigo = codigo;
    this.estadoHttp = estadoHttp;
  }
}

/*
Llama a la API. Ejemplos:
    const { datos } = await api('/catalogo?categoria=2');
    await api('/admin/productos', { metodo: 'POST', cuerpo: { nombre: 'Blusa' } });
    await api('/admin/productos/5/foto', { metodo: 'POST', formulario: formData });
Si la API responde { ok:false }, lanza ErrorApi con el mensaje para el usuario.
*/
async function api(ruta, { metodo = 'GET', cuerpo, formulario } = {}) {
  const opciones = { method: metodo, credentials: 'same-origin', headers: {} };

  if (cuerpo !== undefined) {
    opciones.headers['Content-Type'] = 'application/json';
    opciones.body = JSON.stringify(cuerpo);
  } else if (formulario) {
    opciones.body = formulario; // el navegador pone el Content-Type multipart
  }

  let respuesta;
  try {
    respuesta = await fetch('/api' + ruta, opciones);
  } catch {
    throw new ErrorApi(0, MENSAJE_SIN_CONEXION);
  }

  let json = null;
  try {
    json = await respuesta.json();
  } catch {
    json = null;
  }

  if (!respuesta.ok || !json || json.ok === false) {
    const error = new ErrorApi(
      json?.codigo ?? respuesta.status,
      json?.mensaje || MENSAJE_INESPERADO,
      respuesta.status
    );
    // sesión vencida o inexistente en una página de administración
    if (error.codigo === 50033 && location.pathname.startsWith('/admin/')) {
      irAlIngreso();
    }
    throw error;
  }

  return json;
}

/* ---------------- Formatos ---------------- */

const formatoColones = new Intl.NumberFormat('es-CR', {
  style: 'currency',
  currency: 'CRC',
  minimumFractionDigits: 0,
  maximumFractionDigits: 2,
});

// CP004: si el precio no es válido no se muestra
function precioValido(precio) {
  const n = Number(precio);
  return precio !== null && precio !== undefined && Number.isFinite(n) && n > 0;
}

function formatearPrecio(precio) {
  return precioValido(precio) ? formatoColones.format(Number(precio)) : 'Precio no disponible';
}

// evita que un nombre con < o & rompa el HTML
function escapar(texto) {
  return String(texto ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

// RutaImagen se guarda como "img/productos/x.jpg" o "uploads/productos/x.jpg"
function urlFoto(rutaImagen) {
  return rutaImagen ? '/' + String(rutaImagen).replace(/^\/+/, '') : null;
}

// clase de color pastel de la categoría (estilos.css: .cat-1 a .cat-5)
function claseCategoria(idCategoria) {
  const id = Number(idCategoria);
  return id >= 1 && id <= 5 ? `cat-${id}` : 'cat-0';
}

// foto del producto o, si no tiene, el monograma de Capanni (CP002 alterno)
function htmlFoto(producto, { textoSinFoto = 'Foto pendiente' } = {}) {
  const url = urlFoto(producto.RutaImagen);
  if (url) {
    return `<img src="${escapar(url)}" alt="${escapar(producto.Nombre)}" loading="lazy"
              data-foto data-sin-foto="${escapar(textoSinFoto)}">`;
  }
  return htmlSinFoto(textoSinFoto);
}

function htmlSinFoto(texto) {
  return `<div class="sin-foto"><img src="/img/monograma.svg" alt=""><span>${escapar(texto)}</span></div>`;
}

// si el archivo de la foto no existe en el servidor, se muestra el monograma
document.addEventListener(
  'error',
  (evento) => {
    const img = evento.target;
    if (img instanceof HTMLImageElement && img.hasAttribute('data-foto')) {
      img.outerHTML = htmlSinFoto(img.dataset.sinFoto || 'Foto pendiente');
    }
  },
  true
);

/* ---------------- Memoria del navegador (solo comodidades) ---------------- */

function guardarTemporal(clave, valor) {
  try {
    sessionStorage.setItem('capanni:' + clave, valor);
  } catch {
    /* sin almacenamiento: no pasa nada */
  }
}

function leerTemporal(clave, { borrar = false } = {}) {
  try {
    const valor = sessionStorage.getItem('capanni:' + clave);
    if (borrar) sessionStorage.removeItem('capanni:' + clave);
    return valor;
  } catch {
    return null;
  }
}

/* ---------------- Aviso flotante ---------------- */

let temporizadorAviso = null;

function notificar(texto, { error = false } = {}) {
  let caja = document.querySelector('.notificacion');
  if (!caja) {
    caja = document.createElement('div');
    caja.className = 'notificacion';
    caja.setAttribute('role', 'status');
    caja.setAttribute('aria-live', 'polite');
    document.body.appendChild(caja);
  }
  caja.textContent = texto;
  caja.classList.toggle('es-error', error);
  caja.hidden = false;
  clearTimeout(temporizadorAviso);
  temporizadorAviso = setTimeout(() => {
    caja.hidden = true;
  }, 4200);
}

// para mostrar un aviso en la página siguiente (por ejemplo, después de guardar)
function avisarEnSiguientePagina(texto) {
  guardarTemporal('aviso', texto);
}

function mostrarAvisoPendiente() {
  const texto = leerTemporal('aviso', { borrar: true });
  if (texto) notificar(texto);
}

/* ---------------- Encabezado y pie ---------------- */

const DATOS_TIENDA = {
  // Datos del negocio pendientes: se reemplazan cuando Capanni los confirme
  whatsapp: 'Aquí va el número de WhatsApp',
  correo: 'Aquí va el correo de la tienda',
  direccion: 'Aquí va la dirección del taller',
  horario: 'Aquí va el horario de atención',
  instagram: 'Aquí va el usuario de Instagram',
  facebook: 'Aquí va la página de Facebook',
};

function pintarEncabezadoPublico(actual) {
  const encabezado = document.getElementById('encabezado');
  if (!encabezado) return;
  encabezado.className = 'encabezado';
  encabezado.innerHTML = `
    <div class="contenedor">
      <a class="marca" href="/" aria-label="Confecciones Capanni, ir al catálogo">
        <img src="/img/logo-capanni.svg" alt="Confecciones Capanni" width="53" height="58">
      </a>
      <nav class="menu" aria-label="Principal">
        <a href="/" ${actual === 'catalogo' ? 'aria-current="page"' : ''}>Catálogo</a>
        <a href="#contacto">Contacto</a>
      </nav>
    </div>`;
}

function pintarEncabezadoAdmin(actual, usuario) {
  const encabezado = document.getElementById('encabezado');
  if (!encabezado) return;
  encabezado.className = 'encabezado admin';
  encabezado.innerHTML = `
    <div class="contenedor">
      <a class="marca" href="/admin/inventario.html" aria-label="Inventario de Capanni">
        <img src="/img/logo-capanni.svg" alt="Confecciones Capanni" width="53" height="58">
      </a>
      <nav class="menu" aria-label="Administración">
        <a href="/admin/inventario.html" ${actual === 'inventario' ? 'aria-current="page"' : ''}>Inventario</a>
        <a href="/admin/historial.html" ${actual === 'historial' ? 'aria-current="page"' : ''}>Historial de ventas</a>
        <a href="/" target="_blank" rel="noopener">Ver catálogo</a>
        ${usuario ? `<span class="usuario">${escapar(usuario.nombre || usuario.correo || '')}</span>` : ''}
        <button type="button" class="boton boton-secundario boton-pequeno" id="botonSalir">Cerrar sesión</button>
      </nav>
    </div>`;

  document.getElementById('botonSalir').addEventListener('click', cerrarSesionAdmin);
}

function pintarPie() {
  const pie = document.getElementById('pie');
  if (!pie) return;
  const d = DATOS_TIENDA;
  pie.className = 'pie';
  pie.id = 'contacto';
  pie.innerHTML = `
    <div class="contenedor">
      <div>
        <a class="marca-pie" href="/" aria-label="Confecciones Capanni"><img src="/img/logo-capanni.svg" alt="" width="64" height="70"></a>
        <p class="relleno">Aquí va una frase corta sobre Confecciones Capanni.</p>
      </div>
      <div>
        <h2>Contacto</h2>
        <ul>
          <li>WhatsApp: <span class="relleno">${d.whatsapp}</span></li>
          <li>Correo: <span class="relleno">${d.correo}</span></li>
          <li>Instagram: <span class="relleno">${d.instagram}</span></li>
          <li>Facebook: <span class="relleno">${d.facebook}</span></li>
        </ul>
      </div>
      <div>
        <h2>Visítenos</h2>
        <ul>
          <li><span class="relleno">${d.direccion}</span></li>
          <li><span class="relleno">${d.horario}</span></li>
        </ul>
      </div>
      <div class="legal">
        <span>© ${new Date().getFullYear()} Confecciones Capanni</span>
        <a href="/admin/ingresar.html">Acceso de administración</a>
      </div>
    </div>`;
}

/* ---------------- Sesión de la administradora (GI001) ---------------- */

function irAlIngreso() {
  const volver = location.pathname + location.search;
  location.replace('/admin/ingresar.html?volver=' + encodeURIComponent(volver));
}

// Las páginas de /admin la llaman al cargar. Sin sesión, van al ingreso (CP009 alterno).
async function exigirSesion(actual) {
  let usuario = null;
  try {
    ({ datos: usuario } = await api('/sesion'));
  } catch {
    usuario = null;
  }
  if (!usuario) {
    irAlIngreso();
    return null;
  }
  pintarEncabezadoAdmin(actual, usuario);
  pintarPie();
  mostrarAvisoPendiente();
  return usuario;
}

async function cerrarSesionAdmin() {
  try {
    await api('/sesion', { metodo: 'DELETE' });
  } catch {
    /* aunque falle, se sale */
  }
  location.replace('/admin/ingresar.html');
}

/* ---------------- Tiempo real (CP010) ---------------- */

/*
Escucha los cambios del inventario. alCambiar(idProducto) se llama con el id
del producto que cambió, o null si pueden ser varios.
Si se pierde la conexión, muestra el aviso; al volver, llama alReconectar().
*/
function escucharCatalogo(alCambiar, alReconectar) {
  if (typeof io !== 'function') return; // socket.io no cargó: la página sigue funcionando

  const aviso = document.getElementById('avisoConexion');
  const socket = io({ reconnectionDelayMax: 8000 });
  let seDesconecto = false;

  socket.on('catalogo:actualizado', (datos) => alCambiar(datos?.idProducto ?? null));

  socket.on('disconnect', () => {
    seDesconecto = true;
    if (aviso) aviso.hidden = false;
  });

  socket.on('connect', () => {
    if (aviso) aviso.hidden = true;
    if (seDesconecto) {
      seDesconecto = false;
      alReconectar?.();
    }
  });

  // el navegador avisa antes que socket.io cuando se cae el wifi
  window.addEventListener('offline', () => {
    if (aviso) aviso.hidden = false;
  });
}
