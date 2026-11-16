/* =====================================================================
   Carrito del cliente: /carrito.html
     GP008 Visualizar carrito       GP010 Eliminar carrito
     GP009 Modificar carrito        GP020 Calcular costo (sin envío aquí)
   ===================================================================== */

const el = {
  resumen: document.getElementById('resumenCarrito'),
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoCarrito'),
  compra: document.getElementById('compra'),
  aviso: document.getElementById('avisoNoDisponibles'),
  lineas: document.getElementById('lineasCarrito'),
  montos: document.getElementById('montosCarrito'),
  irOrden: document.getElementById('irOrden'),
  vaciar: document.getElementById('vaciarCarrito'),
  dlgVaciar: document.getElementById('dialogoVaciar'),
  confirmarVaciar: document.getElementById('confirmarVaciar'),
  errorVaciar: document.getElementById('errorVaciar'),
};

let lineas = [];

/* ---------------- Cargar y pintar ---------------- */

async function cargar() {
  try {
    const { datos } = await api('/cliente/carrito');
    pintar(datos);
  } catch (error) {
    if (error.codigo === 50033) return;
    el.compra.hidden = true;
    el.estado.innerHTML = `
      <div class="vacio">
        <h2>No se pudo cargar su carrito</h2>
        <p>${escapar(error.message)}</p>
        <button type="button" class="boton boton-principal" id="reintentar">Intentar de nuevo</button>
      </div>`;
    document.getElementById('reintentar').addEventListener('click', cargar);
  } finally {
    el.cargando.hidden = true;
  }
}

function pintar({ lineas: nuevas, resumen }) {
  lineas = nuevas ?? [];
  ponerIndicadorCarrito(resumen?.CantidadArticulos ?? 0);

  if (!lineas.length) {
    // GP008 flujo alterno 1
    el.compra.hidden = true;
    el.resumen.textContent = '';
    el.estado.innerHTML = `
      <div class="vacio">
        <img class="monograma" src="/img/monograma.svg" alt="">
        <h2>Su carrito está vacío</h2>
        <p>Explore el catálogo y agregue las prendas que le gusten.</p>
        <a class="boton boton-principal" href="/">Ver catálogo</a>
      </div>`;
    return;
  }

  el.estado.innerHTML = '';
  el.compra.hidden = false;
  const n = resumen.CantidadArticulos;
  el.resumen.textContent = n === 1 ? '1 artículo' : `${n} artículos`;

  el.lineas.innerHTML = lineas.map(htmlLinea).join('');

  // GP008 flujo alterno 2 y GP020 flujo alterno 2: los no disponibles no suman
  el.aviso.hidden = !resumen.HayNoDisponibles;
  el.montos.innerHTML = `
    <div><dt>Productos</dt><dd>${escapar(formatearPrecio(resumen.SubtotalProductos))}</dd></div>
    <div class="total"><dt>Total</dt><dd>${escapar(formatearPrecio(resumen.SubtotalProductos))}</dd></div>`;

  // GP011 precondición 2: para la orden todos deben estar disponibles
  const bloquear = Boolean(resumen.HayNoDisponibles);
  el.irOrden.classList.toggle('deshabilitado', bloquear);
  el.irOrden.setAttribute('aria-disabled', String(bloquear));
}

function htmlLinea(l) {
  const disponible = Boolean(l.Disponible);
  let nota = '';
  if (!disponible) {
    nota =
      l.Existencias > 0
        ? `<p class="nota-linea">No disponible: solo quedan ${l.Existencias}. Baje la cantidad.</p>`
        : '<p class="nota-linea">No disponible: se agotó o ya no está en el catálogo.</p>';
  }

  return `
    <li class="linea-carrito ${disponible ? '' : 'no-disponible'}" data-id="${l.IdCarritoDetalle}">
      <a class="miniatura" href="/producto.html?id=${l.IdProducto}" tabindex="-1" aria-hidden="true">
        ${htmlFoto(l, { textoSinFoto: '' })}
      </a>
      <div class="linea-datos">
        <h3><a href="/producto.html?id=${l.IdProducto}">${escapar(l.Nombre)}</a></h3>
        <p class="linea-meta">
          <span class="talla talla-mini">${escapar(l.Talla)}</span>
          <span>${escapar(formatearPrecio(l.PrecioUnitario))} c/u</span>
          ${disponible ? '' : '<span class="estado estado-no">No disponible</span>'}
        </p>
        ${nota}
        <p class="mensaje mensaje-error error-linea" role="alert" hidden></p>
      </div>
      <div class="linea-acciones">
        ${
          l.Existencias > 0
            ? `<div class="cantidad cantidad-pequena">
                <button type="button" data-paso="-1" aria-label="Quitar uno de ${escapar(l.Nombre)}">−</button>
                <input type="text" inputmode="numeric" value="${l.Cantidad}" data-anterior="${l.Cantidad}"
                       aria-label="Cantidad de ${escapar(l.Nombre)}" autocomplete="off">
                <button type="button" data-paso="1" aria-label="Agregar uno de ${escapar(l.Nombre)}">+</button>
              </div>`
            : `<span class="ayuda">Cantidad: ${l.Cantidad}</span>`
        }
        <span class="linea-subtotal">${disponible ? escapar(formatearPrecio(l.Subtotal)) : ''}</span>
        <button type="button" class="boton boton-texto boton-pequeno" data-quitar>Quitar</button>
      </div>
    </li>`;
}

/* ---------------- GP009 Modificar ---------------- */

async function cambiarCantidad(fila, campo, nuevo) {
  const error = fila.querySelector('.error-linea');
  error.hidden = true;
  const texto = String(nuevo).trim();

  // GP009 flujo alterno 1: cantidad inválida, se conserva la anterior
  if (!/^\d+$/.test(texto) || Number(texto) < 1) {
    campo.value = campo.dataset.anterior;
    error.textContent = 'La cantidad debe ser un número entero mayor que cero.';
    error.hidden = false;
    return;
  }
  if (texto === campo.dataset.anterior) return;

  fila.classList.add('ocupado');
  try {
    const { datos } = await api('/cliente/carrito/' + fila.dataset.id, {
      metodo: 'PUT',
      cuerpo: { cantidad: Number(texto) },
    });
    pintar(datos); // GP009 restricción 2: total recalculado
  } catch (e) {
    campo.value = campo.dataset.anterior;
    error.textContent = e.message; // "Solo hay N disponibles."
    error.hidden = false;
  } finally {
    fila.classList.remove('ocupado');
  }
}

el.lineas.addEventListener('click', async (evento) => {
  const fila = evento.target.closest('[data-id]');
  if (!fila) return;

  const paso = evento.target.closest('[data-paso]');
  if (paso) {
    const campo = fila.querySelector('input');
    const actual = parseInt(campo.dataset.anterior, 10) || 1;
    const nuevo = actual + Number(paso.dataset.paso);
    if (nuevo >= 1) cambiarCantidad(fila, campo, nuevo);
    return;
  }

  if (evento.target.closest('[data-quitar]')) {
    // GP009: quitar un producto. Si era el único, queda vacío (flujo alterno 2)
    fila.classList.add('ocupado');
    try {
      const { mensaje, datos } = await api('/cliente/carrito/' + fila.dataset.id, { metodo: 'DELETE' });
      pintar(datos);
      notificar(mensaje);
    } catch (e) {
      fila.classList.remove('ocupado');
      notificar(e.message, { error: true });
      if (e.codigo === 50049) cargar();
    }
  }
});

el.lineas.addEventListener('change', (evento) => {
  const campo = evento.target.closest('input');
  if (campo) cambiarCantidad(campo.closest('[data-id]'), campo, campo.value);
});

el.lineas.addEventListener('keydown', (evento) => {
  if (evento.key === 'Enter' && evento.target.matches('input')) {
    evento.preventDefault();
    evento.target.blur(); // dispara "change"
  }
});

el.irOrden.addEventListener('click', (evento) => {
  if (el.irOrden.getAttribute('aria-disabled') === 'true') {
    evento.preventDefault();
    el.aviso.focus?.();
    notificar('Quite o ajuste los productos no disponibles para continuar.', { error: true });
  }
});

/* ---------------- GP010 Eliminar carrito ---------------- */

el.vaciar.addEventListener('click', () => {
  el.errorVaciar.hidden = true;
  el.dlgVaciar.showModal(); // "¿Confirma que desea vaciar su carrito?"
});

el.confirmarVaciar.addEventListener('click', async () => {
  el.confirmarVaciar.disabled = true;
  try {
    const { mensaje } = await api('/cliente/carrito', { metodo: 'DELETE' });
    el.dlgVaciar.close();
    pintar({ lineas: [], resumen: { CantidadArticulos: 0 } });
    notificar(mensaje);
  } catch (e) {
    el.errorVaciar.textContent = e.message;
    el.errorVaciar.hidden = false;
  } finally {
    el.confirmarVaciar.disabled = false;
  }
});

/* ---------------- Inicio ---------------- */

(async () => {
  if (!(await exigirCliente('carrito'))) return;

  // viene de una orden que no se pudo confirmar (GP014 flujo alterno 1)
  const noDisponibles = leerTemporal('noDisponibles', { borrar: true });
  if (noDisponibles) {
    const aviso = document.createElement('p');
    aviso.className = 'mensaje mensaje-error';
    aviso.setAttribute('role', 'alert');
    aviso.textContent = `No se pudo confirmar la orden. ${noDisponibles} Ajuste su carrito e intente de nuevo.`;
    el.estado.before(aviso);
  }

  cargar();
})();
