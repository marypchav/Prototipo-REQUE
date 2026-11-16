/* =====================================================================
   Generar orden: /orden.html
     GP012 Método de entrega (y dirección)   GP013 Adjuntar comprobante
     GP011 Método de pago                    GP014 Confirmar orden
     GP020 Costo del pedido: se recalcula al elegir la entrega
   Lo elegido vive en esta página hasta confirmar (no se guarda en la base).
   ===================================================================== */

const TIPOS_IMAGEN = ['image/png', 'image/jpeg'];
const MAX_IMAGEN = 5 * 1024 * 1024; // GP013 restricción 1

const el = {
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoOrden'),
  form: document.getElementById('formOrden'),
  error: document.getElementById('errorOrden'),
  entregas: document.getElementById('opcionesEntrega'),
  pasoDireccion: document.getElementById('pasoDireccion'),
  direcciones: document.getElementById('opcionesDireccion'),
  pagos: document.getElementById('opcionesPago'),
  pasoComprobante: document.getElementById('pasoComprobante'),
  vistaComprobante: document.getElementById('vistaComprobante'),
  comprobanteCamara: document.getElementById('comprobanteCamara'),
  comprobanteGaleria: document.getElementById('comprobanteGaleria'),
  productos: document.getElementById('resumenProductos'),
  montos: document.getElementById('montosOrden'),
  confirmar: document.getElementById('confirmarOrden'),
};

const eleccion = { entrega: null, direccion: null, pago: null };
let opciones = { metodosEntrega: [], metodosPago: [], direcciones: [] };
let comprobante = null; // File
let urlVistaComprobante = null;

const entregaElegida = () => opciones.metodosEntrega.find((m) => m.IdMetodoEntrega === eleccion.entrega);
const pagoElegido = () => opciones.metodosPago.find((m) => m.IdMetodoPago === eleccion.pago);

// la elección se recuerda si va a agregar una dirección y regresa
function recordarEleccion() {
  guardarTemporal('orden', JSON.stringify({ entrega: eleccion.entrega, pago: eleccion.pago }));
}

/* ---------------- Cargar ---------------- */

async function cargar() {
  try {
    const [{ datos: op }, { datos: carrito }] = await Promise.all([
      api('/cliente/orden/opciones'),
      api('/cliente/carrito'),
    ]);
    opciones = op;

    if (!carrito.lineas.length) {
      el.estado.innerHTML = `
        <div class="vacio">
          <img class="monograma" src="/img/monograma.svg" alt="">
          <h2>Su carrito está vacío</h2>
          <p>Agregue productos para generar una orden.</p>
          <a class="boton boton-principal" href="/">Ver catálogo</a>
        </div>`;
      return;
    }
    if (carrito.resumen.HayNoDisponibles) {
      // GP011 precondición 2: primero hay que arreglar el carrito
      location.replace('/carrito.html');
      return;
    }

    // vuelve de agregar una dirección: se recupera lo que había elegido
    try {
      const guardado = JSON.parse(leerTemporal('orden') || 'null');
      if (guardado) Object.assign(eleccion, { entrega: guardado.entrega, pago: guardado.pago });
    } catch {
      /* nada guardado */
    }
    if (!entregaElegida()) eleccion.entrega = null;
    if (!pagoElegido()) eleccion.pago = null;
    // la dirección más reciente queda marcada (por ejemplo, la que acaba de agregar)
    eleccion.direccion = opciones.direcciones[0]?.IdDireccion ?? null;

    el.form.hidden = false;
    pintarOpciones();
    pintarResumen(carrito);
    if (eleccion.entrega) recalcular();
  } catch (error) {
    if (error.codigo === 50033) return;
    el.estado.innerHTML = `<p class="mensaje mensaje-error">${escapar(error.message)}</p>`;
  } finally {
    el.cargando.hidden = true;
  }
}

/* ---------------- Opciones ---------------- */

function notaEntrega(m) {
  if (!m.FlagRequiereDireccion) return 'Sin costo. Pase por su pedido al taller.';
  if (m.CostoEnvio === null) return 'Costo de envío a coordinar con la administradora.';
  return `Envío: ${formatearPrecio(m.CostoEnvio)}`;
}

function htmlOpcion(nombre, valor, titulo, nota, { marcada = false, deshabilitada = false } = {}) {
  return `
    <label class="opcion ${deshabilitada ? 'deshabilitada' : ''}">
      <input type="radio" name="${nombre}" value="${valor}" ${marcada ? 'checked' : ''} ${deshabilitada ? 'disabled' : ''}>
      <span class="opcion-texto">
        <span class="opcion-titulo">${escapar(titulo)}</span>
        ${nota ? `<span class="opcion-nota">${escapar(nota)}</span>` : ''}
      </span>
    </label>`;
}

function pintarOpciones() {
  const entrega = entregaElegida();
  const conEnvio = Boolean(entrega?.FlagRequiereDireccion);

  // GP012 restricción 1
  el.entregas.innerHTML = opciones.metodosEntrega
    .map((m) => htmlOpcion('entrega', m.IdMetodoEntrega, m.Nombre, notaEntrega(m), { marcada: m.IdMetodoEntrega === eleccion.entrega }))
    .join('');

  // GP012 restricción 2: dirección solo para métodos con envío
  el.pasoDireccion.hidden = !conEnvio;
  el.direcciones.innerHTML = opciones.direcciones.length
    ? opciones.direcciones
        .map((d) =>
          htmlOpcion('direccion', d.IdDireccion, `${d.Provincia}, ${d.Canton}, ${d.Distrito}`, d.OtrasSenas, {
            marcada: d.IdDireccion === eleccion.direccion,
          })
        )
        .join('')
    : '<p class="ayuda">Aún no tiene direcciones registradas. Agregue una para continuar.</p>';

  // GP011: efectivo solo para retiro en el taller
  el.pagos.innerHTML = opciones.metodosPago
    .map((m) => {
      const deshabilitada = Boolean(m.FlagSoloRetiro) && conEnvio;
      let nota = m.FlagRequiereComprobante ? 'Adjunte la imagen del comprobante.' : 'Pago en efectivo al retirar en el taller.';
      if (deshabilitada) nota = 'Disponible solo para retiro en el taller';
      return htmlOpcion('pago', m.IdMetodoPago, m.Nombre, nota, {
        marcada: m.IdMetodoPago === eleccion.pago && !deshabilitada,
        deshabilitada,
      });
    })
    .join('');

  // GP013 precondición 2: el comprobante solo con SINPE Móvil
  el.pasoComprobante.hidden = !pagoElegido()?.FlagRequiereComprobante;
}

el.form.addEventListener('change', (evento) => {
  const campo = evento.target;
  if (campo.name === 'entrega') {
    eleccion.entrega = Number(campo.value);
    // si cambió a un envío y había elegido efectivo, se quita (GP011 restricción 2)
    if (entregaElegida()?.FlagRequiereDireccion && pagoElegido()?.FlagSoloRetiro) eleccion.pago = null;
    pintarOpciones();
    recalcular(); // GP012 paso 6.2
  } else if (campo.name === 'direccion') {
    eleccion.direccion = Number(campo.value);
  } else if (campo.name === 'pago') {
    eleccion.pago = Number(campo.value);
    pintarOpciones();
  } else {
    return;
  }
  el.error.hidden = true;
  recordarEleccion();
});

document.getElementById('agregarDireccion').addEventListener('click', recordarEleccion);

/* ---------------- Resumen y costo (GP020) ---------------- */

async function recalcular() {
  try {
    const { datos } = await api('/cliente/carrito?metodoEntrega=' + (eleccion.entrega ?? ''));
    pintarResumen(datos);
  } catch (error) {
    if (error.codigo !== 50033) notificar(error.message, { error: true });
  }
}

function pintarResumen({ lineas, resumen }) {
  el.productos.innerHTML = lineas
    .map(
      (l) => `
      <li>
        <span>${escapar(l.Nombre)} <span class="ayuda">talla ${escapar(l.Talla)} × ${l.Cantidad}</span></span>
        <span>${escapar(formatearPrecio(l.Subtotal))}</span>
      </li>`
    )
    .join('');

  const entrega = entregaElegida();
  let envio = '<dd class="ayuda">Elija la entrega</dd>';
  if (entrega && !entrega.FlagRequiereDireccion) envio = '<dd>Sin costo</dd>';
  else if (resumen.EnvioACoordinar) envio = '<dd>Por coordinar</dd>';
  else if (entrega) envio = `<dd>${escapar(formatearPrecio(resumen.CostoEnvio))}</dd>`;

  el.montos.innerHTML = `
    <div><dt>Productos</dt><dd>${escapar(formatearPrecio(resumen.SubtotalProductos))}</dd></div>
    <div><dt>Envío</dt>${envio}</div>
    <div class="total"><dt>Total</dt><dd>${escapar(formatearPrecio(resumen.Total))}</dd></div>
    ${
      resumen.EnvioACoordinar
        ? '<p class="ayuda">El costo de envío se coordinará con la administradora y no está incluido en el total.</p>'
        : ''
    }`;
}

/* ---------------- GP013 Comprobante ---------------- */

function elegirComprobante(evento) {
  const archivo = evento.target.files?.[0];
  evento.target.value = '';
  if (!archivo) return;

  // GP013 flujo alterno: formato o tamaño no permitido, que elija otro
  if (!TIPOS_IMAGEN.includes(archivo.type)) return mostrarError('Solo se permiten imágenes PNG o JPG.');
  if (archivo.size > MAX_IMAGEN) return mostrarError('La imagen no puede superar los 5 MB.');

  el.error.hidden = true;
  if (urlVistaComprobante) URL.revokeObjectURL(urlVistaComprobante);
  comprobante = archivo; // se puede reemplazar antes de confirmar (flujo alterno)
  urlVistaComprobante = URL.createObjectURL(archivo);
  el.vistaComprobante.innerHTML = `
    <img src="${urlVistaComprobante}" alt="Vista previa del comprobante">
    <p class="mensaje mensaje-ok">Comprobante adjuntado. Puede cambiarlo antes de confirmar.</p>`;
  el.vistaComprobante.hidden = false;
}

el.comprobanteCamara.addEventListener('change', elegirComprobante);
el.comprobanteGaleria.addEventListener('change', elegirComprobante);

/* ---------------- GP014 Confirmar ---------------- */

function mostrarError(texto) {
  el.error.textContent = texto;
  el.error.hidden = false;
  el.error.focus();
}

// GP014 flujo alterno 2: se indica lo que falta
function faltante() {
  const entrega = entregaElegida();
  if (!entrega) return 'Seleccione un método de entrega.';
  if (entrega.FlagRequiereDireccion && !opciones.direcciones.some((d) => d.IdDireccion === eleccion.direccion)) {
    return 'Seleccione una dirección de envío.';
  }
  const pago = pagoElegido();
  if (!pago) return 'Seleccione un método de pago.';
  if (pago.FlagRequiereComprobante && !comprobante) return 'Adjunte el comprobante de pago de SINPE Móvil.';
  return null;
}

el.form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  const falta = faltante();
  if (falta) return mostrarError(falta);

  const formulario = new FormData();
  formulario.append('idMetodoEntrega', eleccion.entrega);
  formulario.append('idMetodoPago', eleccion.pago);
  if (entregaElegida().FlagRequiereDireccion) formulario.append('idDireccion', eleccion.direccion);
  if (pagoElegido().FlagRequiereComprobante) formulario.append('comprobante', comprobante);

  el.confirmar.disabled = true;
  el.confirmar.textContent = 'Confirmando…';

  try {
    const { mensaje, datos } = await api('/cliente/pedidos', { metodo: 'POST', formulario });
    leerTemporal('orden', { borrar: true });
    // GP014 paso 2.5: confirmación con el número de pedido
    avisarEnSiguientePagina(mensaje);
    location.replace(`/cuenta/pedido.html?id=${datos.idPedido}&nuevo=1`);
  } catch (error) {
    if (error.codigo === 50033) return;
    if (error.codigo === 50055 || error.codigo === 50050) {
      // GP014 flujo alterno 1: se indica cuáles fallaron y vuelve al carrito
      const lista = (error.datos ?? []).map((f) => `${f.NombreProducto} (talla ${f.NombreTalla})`).join(', ');
      guardarTemporal('noDisponibles', lista ? `Estos productos ya no están disponibles: ${lista}.` : error.message);
      location.replace('/carrito.html');
      return;
    }
    mostrarError(error.message);
    el.confirmar.disabled = false;
    el.confirmar.textContent = 'Confirmar orden';
  }
});

/* ---------------- Inicio ---------------- */

(async () => {
  if (!(await exigirCliente('carrito'))) return;
  cargar();
})();
