/* =====================================================================
   Detalle de un producto: /producto.html?id=5
     CP008 Ver detalle del producto     CP011 Compartir producto
     CP003, CP004, CP005 tallas, precio y "Agotado"
     CP010 se actualiza solo si la administradora cambia este producto
   ===================================================================== */

const idProducto = Number(new URLSearchParams(location.search).get('id'));
const urlCatalogo = leerTemporal('ultimoCatalogo') || '/';

const el = {
  cargando: document.getElementById('cargando'),
  detalle: document.getElementById('detalle'),
  volver: document.getElementById('volverCatalogo'),
};

let productoActual = null;
let tallaElegida = null; // IdTalla marcado por el cliente
let temporizadorRegreso = null;

el.volver.href = urlCatalogo; // CP008: vuelve con los mismos filtros

/* ---------------- Cargar ---------------- */

async function cargarProducto({ desdeTiempoReal = false } = {}) {
  if (!Number.isInteger(idProducto) || idProducto <= 0) {
    pintarNoDisponible({ mientrasLoVeia: false });
    return;
  }

  try {
    const { datos } = await api('/productos/' + idProducto);
    const estabaDisponible = Boolean(productoActual?.Disponible);
    productoActual = datos;
    pintarProducto(datos);
    if (desdeTiempoReal && estabaDisponible && !datos.Disponible) {
      notificar('Este producto se acaba de agotar.'); // CP008 alterno y CP005
    }
  } catch (error) {
    if (error.codigo === 50011) {
      // eliminado. Si el cliente lo estaba viendo, se le regresa al catálogo (CP008 alterno)
      pintarNoDisponible({ mientrasLoVeia: desdeTiempoReal });
    } else if (!(desdeTiempoReal && productoActual)) {
      pintarError(error);
    }
  } finally {
    el.cargando.hidden = true;
  }
}

/* ---------------- Pintar ---------------- */

function pintarProducto(p) {
  const disponible = Boolean(p.Disponible);
  const conPrecio = precioValido(p.Precio);
  const tallas = (p.tallas ?? []).filter((t) => Number(t.Cantidad) > 0);

  // si la talla que había elegido se agotó, se desmarca
  if (!tallas.some((t) => t.IdTalla === tallaElegida)) tallaElegida = null;

  document.title = `${p.Nombre} | Confecciones Capanni`;

  el.detalle.innerHTML = `
    <article class="detalle ${claseCategoria(p.IdCategoria)}">
      <div class="detalle-foto">
        ${htmlFoto(p, { textoSinFoto: 'Este producto aún no tiene foto' })}
        ${disponible ? '' : '<span class="sello-agotado">Agotado</span>'}
      </div>

      <div class="detalle-info">
        <div>
          <span class="categoria-texto">${escapar(p.Categoria)}</span>
          <h1>${escapar(p.Nombre)}</h1>
        </div>

        <p class="detalle-precio ${conPrecio ? '' : 'sin-precio'}">${escapar(formatearPrecio(p.Precio))}</p>

        ${p.Descripcion ? `<p class="detalle-descripcion">${escapar(p.Descripcion)}</p>` : ''}

        <div class="filtro-grupo">
          <p class="filtro-titulo" id="tituloTallasDetalle">Tallas disponibles</p>
          ${
            tallas.length
              ? `<div class="tallas-opciones" role="radiogroup" aria-labelledby="tituloTallasDetalle">
                  ${tallas
                    .map(
                      (t) => `<label>
                        <input type="radio" name="talla" value="${t.IdTalla}" ${t.IdTalla === tallaElegida ? 'checked' : ''}>
                        <span class="talla">${escapar(t.Talla)}</span>
                        <span class="solo-lector">Talla ${escapar(t.Talla)}</span>
                      </label>`
                    )
                    .join('')}
                </div>`
              : '<p class="sin-tallas">Sin tallas disponibles</p>'
          }
        </div>

        ${
          disponible && tallas.length
            ? `<div class="campo campo-cantidad">
                <label for="cantidad">Cantidad</label>
                <div class="cantidad">
                  <button type="button" data-paso="-1" aria-label="Quitar uno">−</button>
                  <input type="text" id="cantidad" inputmode="numeric" value="1" autocomplete="off">
                  <button type="button" data-paso="1" aria-label="Agregar uno">+</button>
                </div>
              </div>`
            : ''
        }

        <div class="detalle-acciones">
          <button type="button" class="boton boton-principal" id="agregarCarrito"
            ${disponible && conPrecio ? '' : 'disabled'}>
            ${disponible ? 'Agregar al carrito' : 'Agotado'}
          </button>
          <button type="button" class="boton boton-secundario" id="compartir" aria-expanded="false" aria-controls="panelCompartir">
            Compartir
          </button>
        </div>
        <p class="mensaje mensaje-error" id="errorCarrito" role="alert" hidden></p>

        <div class="compartir-panel" id="panelCompartir" hidden>
          <label for="enlaceProducto" class="filtro-titulo">Enlace del producto</label>
          <div class="fila-enlace">
            <input type="text" id="enlaceProducto" readonly value="${escapar(enlaceDelProducto())}">
            <button type="button" class="boton boton-principal boton-pequeno" id="copiarEnlace">Copiar enlace</button>
          </div>
          ${
            puedeCompartirConApps()
              ? '<button type="button" class="boton boton-secundario boton-pequeno" id="compartirApps">Enviar por WhatsApp u otra aplicación</button>'
              : ''
          }
        </div>
      </div>
    </article>`;

  conectarAcciones();
}

function pintarNoDisponible({ mientrasLoVeia }) {
  productoActual = null;
  document.title = 'Producto no disponible | Confecciones Capanni';
  el.detalle.innerHTML = `
    <div class="vacio no-disponible" role="alert">
      <img class="monograma" src="/img/monograma.svg" alt="">
      <h1 style="font-size:1.6rem">Este producto ya no está disponible</h1>
      <p>${mientrasLoVeia ? 'Lo llevaremos al catálogo en unos segundos.' : 'Puede ver las demás prendas en el catálogo.'}</p>
      <a class="boton boton-principal" href="${escapar(urlCatalogo)}">Ir al catálogo</a>
    </div>`;

  if (mientrasLoVeia) {
    clearTimeout(temporizadorRegreso);
    temporizadorRegreso = setTimeout(() => location.assign(urlCatalogo), 5000);
  }
}

function pintarError(error) {
  el.detalle.innerHTML = `
    <div class="vacio no-disponible">
      <img class="monograma" src="/img/monograma.svg" alt="">
      <h1 style="font-size:1.6rem">No se pudo cargar el producto</h1>
      <p>${escapar(error.message || MENSAJE_INESPERADO)}</p>
      <button type="button" class="boton boton-principal" id="reintentar">Intentar de nuevo</button>
    </div>`;
  document.getElementById('reintentar').addEventListener('click', () => cargarProducto());
}

/* ---------------- Acciones ---------------- */

function conectarAcciones() {
  const errorCarrito = document.getElementById('errorCarrito');

  el.detalle.querySelectorAll('input[name="talla"]').forEach((radio) => {
    radio.addEventListener('change', () => {
      tallaElegida = Number(radio.value);
      errorCarrito.hidden = true;
    });
  });

  // botones − y + de la cantidad
  el.detalle.querySelectorAll('[data-paso]').forEach((boton) => {
    boton.addEventListener('click', () => {
      const campo = document.getElementById('cantidad');
      const actual = parseInt(campo.value, 10) || 1;
      campo.value = Math.max(1, actual + Number(boton.dataset.paso));
      errorCarrito.hidden = true;
    });
  });

  document.getElementById('agregarCarrito').addEventListener('click', () => {
    if (!tallaElegida) {
      errorCarrito.textContent = 'Seleccione una talla.';
      errorCarrito.hidden = false;
      return;
    }
    agregarAlCarrito(productoActual, tallaElegida);
  });

  const botonCompartir = document.getElementById('compartir');
  const panel = document.getElementById('panelCompartir');
  botonCompartir.addEventListener('click', () => {
    panel.hidden = !panel.hidden;
    botonCompartir.setAttribute('aria-expanded', String(!panel.hidden));
  });

  document.getElementById('copiarEnlace').addEventListener('click', copiarEnlace);
  document.getElementById('compartirApps')?.addEventListener('click', compartirConApps);
}

/*
GP007 Agregar productos al carrito. Sin sesión de cliente se le lleva a
iniciar sesión o registrarse y luego regresa a este producto (flujo alterno 1).
El carrito no reserva: las existencias se garantizan al confirmar la orden.
*/
async function agregarAlCarrito(producto, idTalla) {
  const errorCarrito = document.getElementById('errorCarrito');
  const boton = document.getElementById('agregarCarrito');
  const talla = (producto.tallas ?? []).find((t) => t.IdTalla === idTalla);
  const texto = (document.getElementById('cantidad')?.value ?? '1').trim();

  const mostrar = (mensaje) => {
    errorCarrito.textContent = mensaje;
    errorCarrito.hidden = false;
  };

  // GP007 restricción 2: entero positivo y sin superar las existencias
  if (!/^\d+$/.test(texto) || Number(texto) < 1) {
    return mostrar('La cantidad debe ser un número entero mayor que cero.');
  }
  if (talla && Number(texto) > talla.Cantidad) {
    return mostrar(talla.Cantidad === 1 ? 'Solo hay 1 disponible.' : `Solo hay ${talla.Cantidad} disponibles.`);
  }

  const usuario = await obtenerSesion();
  if (!usuario) {
    irAlIngresoCliente();
    return;
  }
  if (usuario.esAdministrador) {
    return mostrar('Con la cuenta de administración no se puede comprar. Inicie sesión como cliente.');
  }

  boton.disabled = true;
  try {
    const { mensaje, datos } = await api('/cliente/carrito', {
      metodo: 'POST',
      cuerpo: { idProductoTalla: talla.IdProductoTalla, cantidad: Number(texto) },
    });
    // GP007 paso 2.3: confirmación y el indicador del carrito al día
    ponerIndicadorCarrito(datos.cantidadArticulos);
    notificar(`${mensaje} Talla ${talla.Talla}, cantidad ${texto}.`);
  } catch (error) {
    if (error.codigo === 50033) return irAlIngresoCliente();
    mostrar(error.message); // GP007 flujo alterno 2: agotado o supera existencias
  } finally {
    boton.disabled = false;
  }
}

/* ---------------- CP011 Compartir ---------------- */

function enlaceDelProducto() {
  return `${location.origin}/producto.html?id=${idProducto}`;
}

function puedeCompartirConApps() {
  return typeof navigator.share === 'function';
}

async function compartirConApps() {
  try {
    // solo se envía el enlace y el nombre: ningún dato del cliente (CP011 restricción 2)
    await navigator.share({
      title: productoActual?.Nombre ?? 'Confecciones Capanni',
      text: `Mire este producto de Confecciones Capanni: ${productoActual?.Nombre ?? ''}`,
      url: enlaceDelProducto(),
    });
    notificar('Enlace compartido.');
  } catch (error) {
    if (error?.name !== 'AbortError') notificar('No se pudo compartir. Copie el enlace.', { error: true });
  }
}

// CP011 alterno: si el dispositivo no tiene menú de compartir, solo se copia
async function copiarEnlace() {
  const texto = enlaceDelProducto();
  try {
    await navigator.clipboard.writeText(texto);
    notificar('Enlace copiado.');
    return;
  } catch {
    /* navigator.clipboard solo existe con https o localhost; abajo el plan B */
  }

  const campo = document.getElementById('enlaceProducto');
  campo.focus();
  campo.select();
  let copiado = false;
  try {
    copiado = document.execCommand('copy');
  } catch {
    copiado = false;
  }
  notificar(copiado ? 'Enlace copiado.' : 'Mantenga presionado el enlace para copiarlo.', { error: !copiado });
}

/* ---------------- Inicio ---------------- */

pintarEncabezadoPublico('producto');
pintarPie();
cargarProducto();

// CP010: si cambia este producto (o varios a la vez), se vuelve a pedir
escucharCatalogo(
  (id) => {
    if (id === null || id === idProducto) cargarProducto({ desdeTiempoReal: true });
  },
  () => cargarProducto({ desdeTiempoReal: true })
);
