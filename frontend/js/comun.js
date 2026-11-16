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
    } else if (error.codigo === 50033 && document.body?.dataset.requiere === 'cliente') {
      irAlIngresoCliente(); // la sesión del cliente se venció
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

// "2026-11-16T19:14:59.873Z" -> "16 nov 2026, 1:14 p. m." en hora de Costa Rica
const formatoFecha = new Intl.DateTimeFormat('es-CR', { dateStyle: 'medium', timeStyle: 'short' });
const formatoSoloFecha = new Intl.DateTimeFormat('es-CR', { dateStyle: 'medium' });

function formatearFecha(valor, { conHora = true } = {}) {
  if (!valor) return '';
  const fecha = new Date(valor);
  if (Number.isNaN(fecha.getTime())) return '';
  return (conHora ? formatoFecha : formatoSoloFecha).format(fecha);
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

/* ---------------- Sesión (administradora o cliente) ---------------- */

let promesaSesion = null;

// quién tiene la sesión abierta: { idUsuario, nombre, esAdministrador } o null.
// Se pide una sola vez por página
function obtenerSesion() {
  if (!promesaSesion) {
    promesaSesion = api('/sesion')
      .then(({ datos }) => datos || null)
      .catch(() => null);
  }
  return promesaSesion;
}

function urlActual() {
  return location.pathname + location.search;
}

function irAlIngresoCliente() {
  location.replace('/cuenta/ingresar.html?volver=' + encodeURIComponent(urlActual()));
}

// Las páginas del cliente (carrito, orden, direcciones, pedidos) la llaman al
// cargar. Sin sesión de cliente van a iniciar sesión y luego regresan (GP002 paso 4.2)
async function exigirCliente(actual) {
  const usuario = await obtenerSesion();
  if (!usuario || usuario.esAdministrador) {
    irAlIngresoCliente();
    return null;
  }
  pintarEncabezadoPublico(actual);
  pintarPie();
  mostrarAvisoPendiente();
  return usuario;
}

async function cerrarSesionCliente() {
  try {
    await api('/sesion', { metodo: 'DELETE' });
  } catch {
    /* aunque falle, se sale */
  }
  location.assign('/');
}

/* ---------------- Indicador del carrito (GP007 paso 2.3) ---------------- */

function ponerIndicadorCarrito(cantidad) {
  const indicador = document.getElementById('indicadorCarrito');
  if (!indicador) return;
  const n = Number(cantidad) || 0;
  indicador.textContent = n > 99 ? '99+' : String(n);
  indicador.hidden = n === 0;
  const enlace = indicador.closest('a');
  enlace?.setAttribute('aria-label', n === 1 ? 'Carrito, 1 producto' : `Carrito, ${n} productos`);
}

async function actualizarIndicadorCarrito() {
  try {
    const { datos } = await api('/cliente/carrito');
    ponerIndicadorCarrito(datos.resumen?.CantidadArticulos);
  } catch {
    /* sin sesión de cliente: el indicador no se muestra */
  }
}

/* ---------------- Encabezado público ---------------- */

function marcaActual(actual, nombre) {
  return actual === nombre ? 'aria-current="page"' : '';
}

async function pintarEncabezadoPublico(actual) {
  const encabezado = document.getElementById('encabezado');
  if (!encabezado) return;
  encabezado.className = 'encabezado';
  encabezado.innerHTML = `
    <div class="contenedor">
      <a class="marca" href="/" aria-label="Confecciones Capanni, ir al catálogo">
        <img src="/img/logo-capanni.svg" alt="Confecciones Capanni" width="53" height="58">
      </a>
      <nav class="menu" aria-label="Principal">
        <a href="/" ${marcaActual(actual, 'catalogo')}>Catálogo</a>
        <a href="/carrito.html" class="enlace-carrito" ${marcaActual(actual, 'carrito')} aria-label="Carrito">
          Carrito <span class="indicador" id="indicadorCarrito" hidden>0</span>
        </a>
        <span id="zonaCuenta"></span>
      </nav>
    </div>`;

  const usuario = await obtenerSesion();
  const zona = document.getElementById('zonaCuenta');
  if (!zona) return;

  if (!usuario) {
    zona.outerHTML = `<a href="/cuenta/ingresar.html?volver=${encodeURIComponent(urlActual())}" ${marcaActual(actual, 'ingresar')}>Iniciar sesión</a>`;
    return;
  }

  if (usuario.esAdministrador) {
    zona.outerHTML = '<a href="/admin/inventario.html">Administración</a>';
    return;
  }

  // cliente: menú de su cuenta (GP002 postcondición 2)
  const primerNombre = String(usuario.nombre || '').split(' ')[0];
  zona.outerHTML = `
    <details class="menu-cuenta">
      <summary>Hola, ${escapar(primerNombre)}</summary>
      <div class="menu-cuenta-lista">
        <a href="/cuenta/pedidos.html" ${marcaActual(actual, 'pedidos')}>Mis pedidos</a>
        <a href="/cuenta/direcciones.html" ${marcaActual(actual, 'direcciones')}>Mis direcciones</a>
        <button type="button" class="boton-texto" id="salirCliente">Cerrar sesión</button>
      </div>
    </details>`;
  document.getElementById('salirCliente').addEventListener('click', cerrarSesionCliente);
  actualizarIndicadorCarrito();
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
        <a href="/admin/pedidos.html" ${actual === 'pedidos' ? 'aria-current="page"' : ''}>Pedidos</a>
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
  // una sesión de cliente no sirve para administrar (GP002 restricción 3)
  if (!usuario || !usuario.esAdministrador) {
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

/* ---------------- Utilidades de formularios ---------------- */

// botón "Mostrar / Ocultar" de las contraseñas: <button data-ver-clave="idDelCampo">
document.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-ver-clave]');
  if (!boton) return;
  const campo = document.getElementById(boton.dataset.verClave);
  const mostrar = campo.type === 'password';
  campo.type = mostrar ? 'text' : 'password';
  boton.textContent = mostrar ? 'Ocultar' : 'Mostrar';
  boton.setAttribute('aria-pressed', String(mostrar));
});

// botones "No" o "Cancelar" de cualquier ventana de diálogo: <button data-cerrar>
document.addEventListener('click', (evento) => {
  const boton = evento.target.closest('dialog [data-cerrar]');
  if (boton) boton.closest('dialog').close();
});

// botones que abren un <input type="file"> escondido: <button data-abrir="idDelInput">
document.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-abrir]');
  if (boton) document.getElementById(boton.dataset.abrir)?.click();
});

// solo se acepta volver a una página de este mismo sitio (nunca a otro dominio)
function destinoSeguro(valor, porDefecto = '/') {
  const texto = String(valor || '');
  return /^\/(?!\/)[\w\-./?=&%]*$/.test(texto) ? texto : porDefecto;
}
