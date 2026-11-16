/* =====================================================================
   Inventario de la administradora: /admin/inventario.html
     GI004 Consultar productos          GI007 Modificar disponibilidad
     GI006 Eliminar producto            GI008 Buscar y filtrar
   Agregar y modificar (GI002, GI003, GI005) están en /admin/producto.html
   ===================================================================== */

const el = {
  resumen: document.getElementById('resumen'),
  form: document.getElementById('formBusqueda'),
  busqueda: document.getElementById('busqueda'),
  categoria: document.getElementById('filtroCategoria'),
  tallas: document.getElementById('filtroTallas'),
  limpiar: document.getElementById('limpiar'),
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoInventario'),
  lista: document.getElementById('listaInventario'),

  dlgExistencias: document.getElementById('dialogoExistencias'),
  formExistencias: document.getElementById('formExistencias'),
  nombreExistencias: document.getElementById('nombreExistencias'),
  camposExistencias: document.getElementById('camposExistencias'),
  errorExistencias: document.getElementById('errorExistencias'),
  guardarExistencias: document.getElementById('guardarExistencias'),

  dlgEliminar: document.getElementById('dialogoEliminar'),
  nombreEliminar: document.getElementById('nombreEliminar'),
  errorEliminar: document.getElementById('errorEliminar'),
  confirmarEliminar: document.getElementById('confirmarEliminar'),
};

let productos = [];
let opcionesPintadas = false;
let productoEnDialogo = null;

/* ---------------- Consultar (GI004 y GI008) ---------------- */

function consultaActual() {
  const params = new URLSearchParams();
  const texto = el.busqueda.value.trim();
  const tallas = [...el.tallas.querySelectorAll('input:checked')].map((i) => i.value);
  if (texto) params.set('busqueda', texto);
  if (el.categoria.value) params.set('categoria', el.categoria.value);
  if (tallas.length) params.set('tallas', tallas.join(','));
  const consulta = params.toString();
  return consulta ? '?' + consulta : '';
}

function hayBusqueda() {
  return consultaActual() !== '';
}

async function cargarInventario({ silencioso = false } = {}) {
  if (!silencioso) el.cargando.hidden = false;
  history.replaceState(null, '', location.pathname + consultaActual());

  try {
    const { datos } = await api('/admin/productos' + consultaActual());
    productos = datos.productos ?? [];
    if (!opcionesPintadas) pintarOpciones(datos.filtros);
    pintarLista(datos.totalInventario ?? 0);
  } catch (error) {
    if (error.codigo === 50033) return; // ya se le está enviando al ingreso
    if (silencioso && productos.length) return;
    el.lista.replaceChildren();
    el.estado.innerHTML = `
      <div class="vacio">
        <h2>No se pudo cargar el inventario</h2>
        <p>${escapar(error.message)}</p>
        <button type="button" class="boton boton-principal" id="reintentar">Intentar de nuevo</button>
      </div>`;
    document.getElementById('reintentar').addEventListener('click', () => cargarInventario());
  } finally {
    el.cargando.hidden = true;
  }
}

// GI008 restricción 1: el menú de filtros muestra todas las categorías y tallas
function pintarOpciones(filtros) {
  const params = new URLSearchParams(location.search);
  const categoriaInicial = params.get('categoria') || '';
  const tallasIniciales = new Set((params.get('tallas') || '').split(','));

  el.categoria.innerHTML =
    '<option value="">Todas</option>' +
    (filtros?.categorias ?? [])
      .map((c) => `<option value="${c.IdCategoria}">${escapar(c.Nombre)}</option>`)
      .join('');
  el.categoria.value = categoriaInicial;

  el.tallas.innerHTML = (filtros?.tallas ?? [])
    .map(
      (t) => `<label>
        <input type="checkbox" value="${t.IdTalla}" ${tallasIniciales.has(String(t.IdTalla)) ? 'checked' : ''}>
        <span class="talla talla-mini">${escapar(t.Nombre)}</span>
        <span class="solo-lector">Talla ${escapar(t.Nombre)}</span>
      </label>`
    )
    .join('');

  opcionesPintadas = true;
}

function pintarLista(totalInventario) {
  el.estado.innerHTML = '';
  el.resumen.textContent =
    totalInventario === 1 ? '1 producto registrado' : `${totalInventario} productos registrados`;

  if (totalInventario === 0) {
    // GI004 alterno
    el.lista.replaceChildren();
    el.estado.innerHTML = `
      <div class="vacio">
        <img class="monograma" src="/img/monograma.svg" alt="">
        <h2>Aún no hay productos registrados en el inventario</h2>
        <p>Agregue el primero para que aparezca en el catálogo.</p>
        <a class="boton boton-principal" href="/admin/producto.html">Agregar producto</a>
      </div>`;
    return;
  }

  if (!productos.length) {
    // GI008 alterno
    el.lista.replaceChildren();
    el.estado.innerHTML = `
      <div class="vacio">
        <img class="monograma" src="/img/monograma.svg" alt="">
        <h2>No se han encontrado productos que coincidan con la búsqueda</h2>
        <p>Revise lo que escribió o quite algún filtro.</p>
        <button type="button" class="boton boton-principal" id="limpiarVacio">Limpiar búsqueda</button>
      </div>`;
    document.getElementById('limpiarVacio').addEventListener('click', limpiarBusqueda);
    return;
  }

  if (hayBusqueda()) {
    el.resumen.textContent += `; ${productos.length} coinciden con la búsqueda`;
  }

  el.lista.innerHTML = productos.map(htmlFila).join('');
}

function htmlFila(p) {
  const disponible = Boolean(p.Disponible);
  const tallas = p.tallas ?? [];

  return `
    <li class="fila-producto ${claseCategoria(p.IdCategoria)}" data-id="${p.IdProducto}">
      <div class="miniatura">${htmlFoto(p, { textoSinFoto: '' })}</div>
      <div class="fila-datos">
        <h2>${escapar(p.Nombre)}</h2>
        <div class="linea">
          <span class="categoria-texto">${escapar(p.Categoria)}</span>
          <span class="precio">${escapar(formatearPrecio(p.Precio))}</span>
          <span class="estado ${disponible ? 'estado-si' : 'estado-no'}">${disponible ? 'Disponible' : 'Agotado'}</span>
        </div>
        <div class="existencias" aria-label="Existencias por talla">
          ${
            tallas.length
              ? tallas
                  .map(
                    (t) => `<span class="existencia ${Number(t.Cantidad) > 0 ? '' : 'en-cero'}">
                      <b>${escapar(t.Talla)}</b> ${Number(t.Cantidad)}
                    </span>`
                  )
                  .join('')
              : '<span class="existencia en-cero">Sin tallas registradas</span>'
          }
        </div>
      </div>
      <div class="fila-acciones">
        <a class="boton boton-secundario boton-pequeno" href="/admin/producto.html?id=${p.IdProducto}">Modificar</a>
        <button type="button" class="boton boton-secundario boton-pequeno" data-accion="existencias">Modificar disponibilidad</button>
        <button type="button" class="boton boton-texto boton-pequeno" data-accion="eliminar">Eliminar</button>
      </div>
    </li>`;
}

/* ---------------- Búsqueda y filtros ---------------- */

el.form.addEventListener('submit', (evento) => {
  evento.preventDefault();
  cargarInventario();
});

// los filtros se aplican al momento; el texto, al tocar "Buscar"
el.categoria.addEventListener('change', () => cargarInventario());
el.tallas.addEventListener('change', () => cargarInventario());

function limpiarBusqueda() {
  el.busqueda.value = '';
  el.categoria.value = '';
  el.tallas.querySelectorAll('input:checked').forEach((i) => (i.checked = false));
  cargarInventario();
}

el.limpiar.addEventListener('click', limpiarBusqueda);

/* ---------------- Acciones de cada fila ---------------- */

el.lista.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-accion]');
  if (!boton) return;
  const id = Number(boton.closest('[data-id]').dataset.id);
  const producto = productos.find((p) => p.IdProducto === id);
  if (!producto) return;

  if (boton.dataset.accion === 'existencias') abrirExistencias(producto);
  if (boton.dataset.accion === 'eliminar') abrirEliminar(producto);
});

// los botones [data-cerrar] de los diálogos los maneja comun.js

/* ---------------- GI007 Modificar disponibilidad ---------------- */

async function abrirExistencias(producto) {
  productoEnDialogo = producto;
  el.nombreExistencias.textContent = producto.Nombre;
  el.errorExistencias.hidden = true;
  el.camposExistencias.innerHTML = '<p class="ayuda">Cargando…</p>';
  el.dlgExistencias.showModal();

  try {
    // trae las 6 tallas, incluso las que el producto aún no tiene
    const { datos } = await api('/admin/productos/' + producto.IdProducto);
    el.camposExistencias.innerHTML = datos.tallas
      .map(
        (t) => `<div class="talla-existencia">
          <label for="existencia-${t.IdTalla}" class="talla">${escapar(t.Talla)}</label>
          <input type="text" inputmode="numeric" id="existencia-${t.IdTalla}"
                 data-talla="${t.IdTalla}" value="${Number(t.Cantidad) || 0}" autocomplete="off">
        </div>`
      )
      .join('');
    el.camposExistencias.querySelector('input')?.focus();
  } catch (error) {
    el.camposExistencias.innerHTML = '';
    el.errorExistencias.textContent = error.message;
    el.errorExistencias.hidden = false;
  }
}

el.formExistencias.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  el.errorExistencias.hidden = true;

  const campos = [...el.camposExistencias.querySelectorAll('input[data-talla]')];
  let hayError = false;
  const tallas = campos.map((campo) => {
    const texto = campo.value.trim();
    const valido = /^\d+$/.test(texto); // GI007 alterno: sin letras, decimales ni negativos
    if (valido) campo.removeAttribute('aria-invalid');
    else campo.setAttribute('aria-invalid', 'true');
    if (!valido) hayError = true;
    return { idTalla: Number(campo.dataset.talla), cantidad: Number(texto) };
  });

  if (!campos.length) return;
  if (hayError) {
    el.errorExistencias.textContent =
      'Las cantidades deben ser números enteros, sin decimales, letras ni valores negativos.';
    el.errorExistencias.hidden = false;
    el.camposExistencias.querySelector('[aria-invalid]')?.focus();
    return;
  }

  el.guardarExistencias.disabled = true;
  try {
    const { mensaje } = await api(`/admin/productos/${productoEnDialogo.IdProducto}/existencias`, {
      metodo: 'PUT',
      cuerpo: { tallas },
    });
    el.dlgExistencias.close();
    notificar(mensaje || 'La disponibilidad fue actualizada.');
    cargarInventario({ silencioso: true });
  } catch (error) {
    el.errorExistencias.textContent = error.message;
    el.errorExistencias.hidden = false;
  } finally {
    el.guardarExistencias.disabled = false;
  }
});

/* ---------------- GI006 Eliminar producto ---------------- */

function abrirEliminar(producto) {
  productoEnDialogo = producto;
  el.nombreEliminar.textContent = `${producto.Nombre} dejará de mostrarse en el catálogo.`;
  el.errorEliminar.hidden = true;
  el.dlgEliminar.showModal();
}

el.confirmarEliminar.addEventListener('click', async () => {
  el.confirmarEliminar.disabled = true;
  try {
    const { mensaje } = await api('/admin/productos/' + productoEnDialogo.IdProducto, { metodo: 'DELETE' });
    el.dlgEliminar.close();
    notificar(mensaje || 'El producto fue eliminado exitosamente.');
    cargarInventario({ silencioso: true });
  } catch (error) {
    el.errorEliminar.textContent = error.message;
    el.errorEliminar.hidden = false;
  } finally {
    el.confirmarEliminar.disabled = false;
  }
});

/* ---------------- Inicio ---------------- */

(async () => {
  const usuario = await exigirSesion('inventario');
  if (!usuario) return;

  el.busqueda.value = new URLSearchParams(location.search).get('busqueda') || '';
  await cargarInventario();

  // si otra persona o un pedido cambia el inventario, la lista se refresca sola
  escucharCatalogo(
    () => cargarInventario({ silencioso: true }),
    () => cargarInventario({ silencioso: true })
  );
})();
